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
import 'package:ecoshop_client/core/sync/sync_engine.dart';
import 'package:ecoshop_client/features/reseau/data/supabase_reseau_repository.dart';
import 'package:ecoshop_client/features/reseau/domain/reseau.dart';

const _reseau = 'r-1';
const _ecole = 'e-1';

/// Faux serveur : réponses par fonction appelée ; `enLigne = false` simule
/// une coupure (exception de transport, comme un téléphone sans réseau).
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
          // Une fonction appelée sans paramètres envoie le corps « null ».
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

Map<String, dynamic> _monReseau({String statutEcole = 'invite', String? role}) => {
      'reseau_id': _reseau,
      'nom': 'Réseau EPN',
      'denomination': 'Église Protestante Nationale',
      'devise_code': 'GNF',
      'mon_role': role,
      'ecoles': [
        {'etablissement_id': _ecole, 'nom': 'École Bambino Emmaüs', 'ville': 'Conakry', 'statut': statutEcole},
      ],
      'responsables': <Object>[],
    };

void main() {
  late AppDatabase db;
  late DriftSyncRepository file;
  late _Serveur serveur;
  late SupabaseReseauRepository depot;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    file = DriftSyncRepository(db);
    serveur = _Serveur();
    depot = SupabaseReseauRepository(
      serveur.client(),
      file,
      LectureHorsLigne(CacheDocumentStore(db, 'reseau_hl'), ValueNotifier<DateTime?>(null)),
    );
  });

  tearDown(() => db.close());

  test('mes réseaux : servis depuis l’appareil quand le réseau tombe', () async {
    serveur.reponses['mes_reseaux'] = [_monReseau(statutEcole: 'membre', role: 'direction_generale')];
    final enLigne = await depot.mesReseaux();
    expect(enLigne.single.estDirectionGenerale, isTrue);

    serveur.enLigne = false;
    final horsLigne = await depot.mesReseaux();
    expect(horsLigne.single.nom, 'Réseau EPN');
    expect(horsLigne.single.ecoles.single.statut, 'membre');
  });

  test('circulaire rédigée sans réseau : gardée avec sa clé, affichée « en attente d’envoi »', () async {
    serveur.enLigne = false;
    final recue = await depot.publierCirculaire(
      reseauId: _reseau,
      titre: 'Examens blancs',
      corps: 'Semaine du 8 mars.',
      importante: true,
    );
    expect(recue, isFalse);

    final entree = (await file.entreesEnAttente()).single;
    expect(entree.entite, SupabaseReseauRepository.entiteCirculaire);
    final params = (jsonDecode(entree.payload)['params'] as Map).cast<String, dynamic>();
    expect(params['p_id'], entree.id, reason: 'la clé rend le renvoi idempotent au serveur');

    final liste = await depot.circulaires(_reseau);
    expect(liste.single.titre, 'Examens blancs');
    expect(liste.single.enAttenteEnvoi, isTrue);
    expect(RejeuReseau.libelle(entree), contains('Examens blancs'));
  });

  test('réponse à une invitation sans réseau : l’école apparaît déjà membre', () async {
    serveur.reponses['mes_reseaux'] = [_monReseau()];
    await depot.mesReseaux();
    serveur.enLigne = false;

    final recue = await depot.repondreInvitation(reseauId: _reseau, etablissementId: _ecole, accepter: true);
    expect(recue, isFalse);
    expect((await depot.mesReseaux()).single.ecoles.single.statut, 'membre');
  });

  test('avec réseau : envoi direct, rien en file', () async {
    serveur.reponses['publier_circulaire_reseau'] = {'deja_recue': false, 'destinataires': 3};
    final recue = await depot.publierCirculaire(reseauId: _reseau, titre: 'Rentrée', corps: 'Le 5 octobre.', importante: false);
    expect(recue, isTrue);
    expect(serveur.appels['publier_circulaire_reseau']?['p_reseau'], _reseau);
    expect(await file.entreesEnAttente(), isEmpty);
  });

  test('refus du serveur traduit en message clair ; au rejeu, rejet définitif expliqué', () async {
    serveur.refus['dissoudre_reseau'] = 'CONFIRMATION_INCORRECTE';
    await expectLater(
      depot.dissoudre(_reseau, 'mauvais nom'),
      throwsA(isA<ErreurReseau>().having((e) => e.messageUtilisateur, 'message', contains('ne correspond pas'))),
    );

    serveur.refus['repondre_invitation_reseau'] = 'RESEAU_DISSOUS';
    const entree = SyncEntree(
      id: 'invitation:r-1:e-1',
      entite: SupabaseReseauRepository.entiteInvitation,
      operation: 'rpc',
      payload: '{"rpc":"repondre_invitation_reseau","params":{"p_reseau":"r-1","p_etablissement":"e-1","p_accepter":true}}',
    );
    await expectLater(
      RejeuReseau(serveur.client()).rejouer(entree),
      throwsA(isA<RejetDefinitif>().having((r) => r.message, 'message', contains('dissous'))),
    );
  });

  test('tableau de bord : totaux et présence moyenne des écoles qui ont des relevés', () {
    final t = TableauBordReseau.depuisJson({
      'reseau': {'nom': 'Réseau EPN', 'devise_code': 'GNF'},
      'ecoles': [
        {'etablissement_id': 'a', 'nom': 'A', 'effectif': 120, 'taux_presence': 90.0, 'taux_recouvrement': 40.0, 'montant_du': 100, 'montant_encaisse': 40},
        {'etablissement_id': 'b', 'nom': 'B', 'effectif': 80, 'taux_presence': 80.0},
        {'etablissement_id': 'c', 'nom': 'C', 'effectif': 0},
      ],
      'totaux': {'effectif': 200, 'taux_recouvrement': 40.0, 'alertes_decrochage': 2},
      'genere_le': '2026-10-22T08:00:00Z',
    });
    expect(t.effectif, 200);
    expect(t.tauxPresenceMoyen, 85.0);
    expect(t.ecoles.first.tauxRecouvrement, 40.0);
    expect(t.ecoles.last.tauxPresence, isNull);
  });
}
