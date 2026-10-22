import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/offline/lecture_hors_ligne.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/reseau/data/supabase_transferts_reseau_repository.dart';
import 'package:ecoshop_client/features/reseau/domain/regles_transferts.dart';
import 'package:ecoshop_client/features/reseau/domain/reseau.dart';

const _ecole = 'e-a';

class _Serveur {
  bool enLigne = true;
  final appels = <String, Map<String, dynamic>>{};
  final reponses = <String, Object?>{};
  final refus = <String, String>{};

  SupabaseClient client() => SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        accessToken: () async => 'test-jwt',
        httpClient: MockClient((request) async {
          if (!enLigne) throw http.ClientException('Failed host lookup');
          final nom = request.url.pathSegments.last;
          final corps = request.body.isEmpty ? null : jsonDecode(request.body);
          appels[nom] = corps is Map ? corps.cast<String, dynamic>() : {};
          final r = refus[nom];
          if (r != null) {
            return http.Response(jsonEncode({'code': 'P0001', 'message': r}), 400,
                headers: {'content-type': 'application/json'}, request: request);
          }
          return http.Response(jsonEncode(reponses[nom]), 200,
              headers: {'content-type': 'application/json'}, request: request);
        }),
      );
}

Map<String, dynamic> _transfert(String id, String statut, {String sens = 'arrivee'}) => {
      'id': id,
      'reseau_id': 'r-1',
      'statut': statut,
      'motif': 'Déménagement',
      'sens': sens,
      'eleve': 'Awa BAH',
      'origine_id': 'e-b',
      'origine': 'École Kindia',
      'destination_id': _ecole,
      'destination': 'École Emmaüs',
      'inscription_offerte': true,
      'dossier': {'classe': '6e A', 'absences': 2, 'retards': 1},
      'demande_le': '2026-10-20T10:00:00Z',
    };

void main() {
  late AppDatabase db;
  late DriftSyncRepository file;
  late _Serveur serveur;
  late SupabaseTransfertsReseauRepository depot;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    file = DriftSyncRepository(db);
    serveur = _Serveur();
    depot = SupabaseTransfertsReseauRepository(
      serveur.client(),
      file,
      LectureHorsLigne(CacheDocumentStore(db, 'reseau_hl'), ValueNotifier<DateTime?>(null)),
    );
  });
  tearDown(() => db.close());

  test('règles : lues en ligne, resservies sans réseau, phrases pour les écoles', () async {
    serveur.reponses['regles_reseau'] = {
      'reseau_id': 'r-1',
      'devise_code': 'GNF',
      'politique_frais': 'commune',
      'transferts_ouverts': true,
      'quitus_requis': true,
      'validation_reseau': true,
      'inscription_offerte': false,
      'dossier_partage': true,
      'grille': [
        {'niveau_id': null, 'niveau': 'Tous niveaux (par défaut)', 'montant_annuel': 1200000, 'frais_inscription': 50000,
         'tarif_ecole': 1200000},
      ],
      'niveaux': [
        {'id': 'n-6', 'nom': '6e', 'ordre': 7},
      ],
    };
    final r = await depot.regles('r-1', etablissementId: _ecole);
    expect(r.grilleCommune, isTrue);
    expect(r.grille.single.montantAnnuel, 1200000);
    expect(r.niveaux.single.nom, '6e');
    expect(r.conditionsTransfert, contains('La Direction Générale valide chaque transfert.'));

    serveur.enLigne = false;
    expect((await depot.regles('r-1', etablissementId: _ecole)).politiqueFrais, 'commune');
  });

  test('règles : la Direction Générale les envoie toutes, la grille ligne à ligne', () async {
    serveur.reponses['parametrer_reseau'] = {'reseau_id': 'r-1', 'politique_frais': 'indicative'};
    await depot.parametrer(const ReglesReseau(reseauId: 'r-1', politiqueFrais: 'indicative', quitusRequis: false));
    expect(serveur.appels['parametrer_reseau'], containsPair('p_quitus_requis', false));
    expect(serveur.appels['parametrer_reseau'], containsPair('p_politique_frais', 'indicative'));

    serveur.reponses['enregistrer_grille_reseau'] = {'lignes': 1};
    await depot.enregistrerGrille('r-1', const [LigneGrilleReseau(niveauId: 'n-6', niveau: '6e', montantAnnuel: 900000)]);
    expect((serveur.appels['enregistrer_grille_reseau']!['p_lignes'] as List).single,
        {'niveau_id': 'n-6', 'montant_annuel': 900000.0, 'frais_inscription': 0.0});
  });

  test('refus du serveur expliqué (frais non soldés)', () async {
    serveur.refus['demander_transfert_reseau'] = 'SOLDE_IMPAYE';
    await expectLater(
      depot.demander(
        etablissementId: _ecole,
        eleve: const EleveTransferable(ficheId: 'f-1', nom: 'BAH', prenom: 'Awa', solde: 50000),
        destination: const DestinationTransfert(etablissementId: 'e-b', nom: 'École Kindia', reseau: 'EPN'),
        motif: 'Déménagement',
      ),
      throwsA(isA<ErreurReseau>().having((e) => e.messageUtilisateur, 'message', contains('soldés'))),
    );
  });

  test('sans réseau : demande gardée avec sa clé, visible « en attente d’envoi »', () async {
    serveur.reponses['transferts_reseau_liste'] = <Object>[];
    await depot.transferts(etablissementId: _ecole);
    serveur.enLigne = false;

    final recue = await depot.demander(
      etablissementId: _ecole,
      eleve: const EleveTransferable(ficheId: 'f-1', nom: 'BAH', prenom: 'Awa'),
      destination: const DestinationTransfert(etablissementId: 'e-b', nom: 'École Kindia', reseau: 'EPN'),
      motif: 'Déménagement',
    );
    expect(recue, isFalse);

    final entree = (await file.entreesEnAttente()).single;
    expect(entree.entite, SupabaseTransfertsReseauRepository.entiteDemande);
    final params = (jsonDecode(entree.payload)['params'] as Map).cast<String, dynamic>();
    expect(params['p_id'], entree.id, reason: 'la clé rend le renvoi idempotent');
    expect(SupabaseTransfertsReseauRepository.libelle(entree), 'Transfert de Awa BAH vers École Kindia');

    final liste = await depot.transferts(etablissementId: _ecole);
    expect(liste.single.enAttenteEnvoi, isTrue);
    expect(liste.single.sens, 'depart');
    expect(liste.single.libelleStatut, 'En attente d’envoi');
  });

  test('accueil sans réseau : l’élève apparaît déjà accueilli', () async {
    serveur.reponses['transferts_reseau_liste'] = [_transfert('t-1', 'en_attente_accueil')];
    expect((await depot.transferts(etablissementId: _ecole)).single.enCours, isTrue);
    serveur.enLigne = false;

    final recue = await depot.repondre(transfertId: 't-1', accepter: true, classeId: 'c-6');
    expect(recue, isFalse);
    final t = (await depot.transferts(etablissementId: _ecole)).single;
    expect(t.statut, 'transfere');
    expect(t.enAttenteEnvoi, isTrue);
    expect(t.dossier?['absences'], 2);
  });

  test('validation du réseau sans connexion : refus motivé visible', () async {
    serveur.reponses['transferts_reseau_liste'] = [_transfert('t-2', 'a_valider_reseau')];
    await depot.transferts(reseauId: 'r-1');
    serveur.enLigne = false;
    await depot.valider(transfertId: 't-2', accorder: false, motif: 'Dossier incomplet');
    final t = (await depot.transferts(reseauId: 'r-1')).single;
    expect(t.libelleStatut, 'En attente d’envoi');
    expect(t.motifRefus, 'Dossier incomplet');
    expect(t.refusePar, 'reseau');
  });

  test('classes d’accueil : complète signalée', () {
    const c = ClasseAccueil(classeId: 'c', nom: '6e B', capacite: 40, effectif: 40);
    expect(c.complete, isTrue);
  });
}
