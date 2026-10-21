import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/core/sync/sync_engine.dart';
import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/export_pdf/data/recu_pdf_builder.dart';
import 'package:ecoshop_client/features/scolarite/data/cached_scolarite_repository.dart';
import 'package:ecoshop_client/features/scolarite/data/rejeu_encaissements.dart';
import 'package:ecoshop_client/features/scolarite/domain/encaissement_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/scolarite_repository.dart';
import 'package:ecoshop_client/features/scolarite/domain/solde_scolarite.dart';

/// Serveur injoignable, ou joignable selon [enLigne].
class _Distant implements ScolariteRepository {
  bool enLigne = false;
  final List<EncaissementScolarite> recus = [];

  Never _horsLigne() => throw const ErreurScolarite('HORS_CONNEXION');

  @override
  Future<EncaissementScolarite> enregistrerEncaissement(EncaissementScolarite e) async {
    if (!enLigne) _horsLigne();
    recus.add(e);
    return EncaissementScolarite.depuisJson({...e.versJsonCache(), 'numero_recu': 'SCO-2026-000001', 'saisi_par': 'p1'});
  }

  @override
  Future<void> annulerEncaissement({required String encaissementId, required String motif}) async {
    if (!enLigne) _horsLigne();
  }

  @override
  Future<SoldeScolarite> soldeScolarite(String inscriptionId) async {
    if (!enLigne) _horsLigne();
    return const SoldeScolarite(montantDu: 1000000, montantPaye: 200000, solde: 800000);
  }

  @override
  Future<List<EncaissementScolarite>> encaissementsDeInscription(String inscriptionId) async =>
      enLigne ? const [] : _horsLigne();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late DriftSyncRepository file;
  late _Distant distant;
  late CachedScolariteRepository depot;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    file = DriftSyncRepository(db);
    distant = _Distant();
    depot = CachedScolariteRepository(distant, CacheDocumentStore(db, 'scolarite'), file, () async => 'c4d5e6f7-0000');
  });

  tearDown(() => db.close());

  EncaissementScolarite saisie({double montant = 300000}) => EncaissementScolarite(
        id: '',
        etablissementId: 'e1',
        ficheEleveId: 'f1',
        inscriptionId: 'i1',
        montant: montant,
        datePaiement: DateTime(2026, 10, 21),
        saisiPar: '',
      );

  test('encaissement sans réseau : reçu provisoire numéroté par appareil, mis en file avec sa clé', () async {
    final e1 = await depot.enregistrerEncaissement(saisie());
    final e2 = await depot.enregistrerEncaissement(saisie(montant: 100000));

    expect(e1.enAttenteEnvoi, isTrue);
    expect(e1.numeroProvisoire, 'PROV-C4D5-0001');
    expect(e2.numeroProvisoire, 'PROV-C4D5-0002');
    expect(e1.id, isNotEmpty);
    final entree = (await file.entreesEnAttente()).first;
    expect(entree.entite, CachedScolariteRepository.entiteEncaissement);
    final params = jsonDecode(entree.payload) as Map<String, dynamic>;
    expect(params['p_id'], e1.id, reason: 'la clé rend le renvoi idempotent au serveur');
    expect(params['p_numero_provisoire'], 'PROV-C4D5-0001');
    expect(params['p_saisi_le'], isNotNull);
  });

  test('historique et solde tiennent compte de ce qui attend l\'envoi', () async {
    // Solde connu en ligne, puis plus de réseau.
    distant.enLigne = true;
    await depot.soldeScolarite('i1');
    await depot.encaissementsDeInscription('i1');
    distant.enLigne = false;

    final e = await depot.enregistrerEncaissement(saisie());
    final historique = await depot.encaissementsDeInscription('i1');
    expect(historique.single.id, e.id);
    expect(historique.single.enAttenteEnvoi, isTrue);

    final solde = await depot.soldeScolarite('i1');
    expect(solde.montantPaye, 500000);
    expect(solde.solde, 500000);

    await depot.annulerEncaissement(encaissementId: e.id, motif: 'Erreur de montant');
    final apres = await depot.encaissementsDeInscription('i1');
    expect(apres.single.estValide, isFalse, reason: 'annulation sans réseau visible tout de suite');
    expect((await depot.soldeScolarite('i1')).solde, 800000);
  });

  test('avec réseau : envoi direct avec la clé de l\'appareil, numéro définitif', () async {
    distant.enLigne = true;
    final e = await depot.enregistrerEncaissement(saisie());
    expect(e.enAttenteEnvoi, isFalse);
    expect(e.numeroRecu, 'SCO-2026-000001');
    expect(distant.recus.single.id, isNotEmpty);
    expect(await file.entreesEnAttente(), isEmpty);
  });

  test('reçu PDF provisoire, et libellé du refus au rejeu', () async {
    final e = await depot.enregistrerEncaissement(saisie());
    final octets = await construireRecuPdf(
      encaissement: e,
      fiche: FicheEleve(id: 'f1', etablissementId: 'e1', matricule: 'M-1', nom: 'BAH', prenom: 'A', dateNaissance: DateTime(2014)),
      etablissement: const Etablissement(id: 'e1', nom: 'École', slug: 'ecole'),
      variante: AppThemeVariant.francophoneCfa,
    );
    expect(String.fromCharCodes(octets.take(5)), '%PDF-');

    final entree = (await file.entreesEnAttente()).first;
    expect(RejeuEncaissements.libelle(entree), contains('PROV-C4D5-0001'));
    expect(RejeuEncaissements.messageRejet('REFUS'), contains('régularisé'));
    expect(
      const SyncEntree(id: 'x', entite: 'encaissements_scolarite_annulation', operation: 'update', payload: '{}').entite,
      CachedScolariteRepository.entiteAnnulationEncaissement,
    );
  });
}
