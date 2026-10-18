import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/core/sync/sync_engine.dart';
import 'package:ecoshop_client/features/comptabilite/data/dons_hors_ligne_repository.dart';
import 'package:ecoshop_client/features/comptabilite/data/pieces_hors_ligne_repository.dart';
import 'package:ecoshop_client/features/comptabilite/data/rejeu_comptabilite.dart';
import 'package:ecoshop_client/features/comptabilite/domain/dons.dart';
import 'package:ecoshop_client/features/comptabilite/domain/pieces_comptables.dart';

/// Serveur injoignable (ou joignable selon [enLigne]).
class _DonsServeur implements DonsRepository {
  bool enLigne = false;
  final List<SaisieDon> recus = [];

  Never _horsLigne() => throw const ErreurDons('HORS_CONNEXION');

  @override
  Future<ResultatDon> enregistrerDon(SaisieDon saisie) async {
    if (!enLigne) _horsLigne();
    recus.add(saisie);
    return ResultatDon(id: saisie.id!, numeroRecu: 'REC-2026-000001', comptabilise: true);
  }

  @override
  Future<List<Don>> dons(String etablissementId, int annee) async => enLigne ? const [] : _horsLigne();

  @override
  Future<List<Donateur>> donateurs(String etablissementId) async => enLigne ? const [] : _horsLigne();

  @override
  Future<List<AffectationDon>> affectations(String etablissementId) async => enLigne ? const [] : _horsLigne();

  @override
  Future<String> enregistrerDonateur(Donateur donateur) async => enLigne ? donateur.id! : _horsLigne();

  @override
  Future<double> constaterEmploi({
    required String affectationId,
    required double montant,
    required String libelle,
    required DateTime date,
  }) async =>
      enLigne ? 0 : _horsLigne();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _PiecesServeur implements PiecesComptablesRepository {
  @override
  Future<String> enregistrer(SaisiePiece saisie) async => throw const ErreurPiecesComptables('HORS_CONNEXION');

  @override
  Future<String> valider(String pieceId) async => throw const ErreurPiecesComptables('HORS_CONNEXION');

  @override
  Future<List<PieceComptable>> pieces(String etablissementId, String exerciceId) async =>
      throw const ErreurPiecesComptables('HORS_CONNEXION');

  @override
  Future<List<ExerciceComptable>> exercices(String etablissementId) async => [
        ExerciceComptable(id: 'x2026', libelle: 'Exercice 2026', dateDebut: DateTime(2026), dateFin: DateTime(2026, 12, 31), cloture: false),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late DriftSyncRepository file;
  late _DonsServeur serveur;
  late DonsHorsLigneRepository dons;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    file = DriftSyncRepository(db);
    serveur = _DonsServeur();
    dons = DonsHorsLigneRepository(serveur, file, CacheDocumentStore(db, 'comptabilite_hl'), () async => 'a3f2c9d1-0000');
  });

  tearDown(() => db.close());

  SaisieDon saisie({String? donateurId}) => SaisieDon(
        etablissementId: 'e1',
        montant: 250000,
        nature: NatureDon.quete,
        date: DateTime(2026, 10, 11),
        donateurId: donateurId,
      );

  test('don sans réseau : reçu provisoire numéroté par appareil, mis en file', () async {
    final r1 = await dons.enregistrerDon(saisie());
    final r2 = await dons.enregistrerDon(saisie());

    expect(r1.provisoire, isTrue);
    expect(r1.numeroRecu, 'PROV-A3F2-0001');
    expect(r2.numeroRecu, 'PROV-A3F2-0002');
    final file1 = (await file.entreesEnAttente()).first;
    expect(file1.entite, 'dons');
    final params = jsonDecode(file1.payload) as Map<String, dynamic>;
    expect(params['p_id'], r1.id, reason: 'la clé de l\'appareil rend l\'envoi idempotent');
    expect(params['p_numero_provisoire'], 'PROV-A3F2-0001');
  });

  test('listes : ce qui attend l\'envoi apparaît tout de suite, avec le nom du donateur', () async {
    final donateurId = await dons.enregistrerDonateur(const Donateur(etablissementId: 'e1', nom: 'CAMARA', prenom: 'Ibrahima'));
    await dons.enregistrerDon(saisie(donateurId: donateurId));

    expect((await dons.donateurs('e1')).single.nomComplet, 'CAMARA Ibrahima');
    final liste = await dons.dons('e1', 2026);
    expect(liste.single.provisoire, isTrue);
    expect(liste.single.donateurAffiche, 'CAMARA Ibrahima');
    expect(liste.single.numeroRecu, 'PROV-A3F2-0001');

    final recu = await dons.recu(liste.single.id);
    expect(recu.provisoire, isTrue);
    expect(recu.donateurNom, 'CAMARA Ibrahima');
  });

  test('avec réseau : envoyé directement, avec la clé de l\'appareil', () async {
    serveur.enLigne = true;
    final r = await dons.enregistrerDon(saisie());
    expect(r.provisoire, isFalse);
    expect(serveur.recus.single.id, isNotNull);
    expect(await file.entreesEnAttente(), isEmpty);
  });

  test('emploi des fonds : attend le réseau (solde vérifié au serveur)', () async {
    expect(
      dons.constaterEmploi(affectationId: 'a1', montant: 1, libelle: 'x', date: DateTime(2026)),
      throwsA(isA<ErreurDons>().having((e) => e.code, 'code', 'RESEAU_REQUIS_EMPLOI')),
    );
  });

  test('brouillard sans réseau : en file et dans la liste ; validation en ligne seulement', () async {
    final pieces = PiecesHorsLigneRepository(_PiecesServeur(), file);
    final id = await pieces.enregistrer(SaisiePiece(
      etablissementId: 'e1',
      journalId: 'j1',
      datePiece: DateTime(2026, 10, 12),
      libelle: 'Craies',
      lignes: const [LignePiece(compteId: 'c605', debit: 30000), LignePiece(compteId: 'c571', credit: 30000)],
    ));

    final liste = await pieces.pieces('e1', 'x2026');
    expect(liste.single.id, id);
    expect(liste.single.reference, PiecesHorsLigneRepository.referenceEnAttente);
    expect(liste.single.totalDebit, 30000);
    expect(
      pieces.valider(id),
      throwsA(isA<ErreurPiecesComptables>().having((e) => e.code, 'code', 'VALIDATION_EN_LIGNE')),
    );

    await pieces.supprimerBrouillard(id);
    expect(await file.entreesEnAttente(), isEmpty, reason: 'jamais parti : simplement retiré de la file');
  });

  test('refus au rejeu : libellé et explication lisibles', () {
    const entree = SyncEntree(
      id: 'd1',
      entite: 'dons',
      operation: 'upsert',
      payload: '{"p_nature":"quete","p_montant":250000,"p_date":"2026-10-11","p_numero_provisoire":"PROV-A3F2-0001"}',
    );
    final libelle = RejeuComptabilite.libelle(entree);
    expect(libelle, startsWith('Quête de 250'));
    expect(libelle, endsWith('du 11/10 (reçu PROV-A3F2-0001)'));
    expect(RejeuComptabilite.messageRejet('pieces_brouillard', 'PERIODE_CLOTUREE'), contains('clôturée'));
    expect(RejeuComptabilite.messageRejet('dons', 'REFUS'), contains('droits'));
  });
}
