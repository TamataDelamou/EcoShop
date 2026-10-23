import 'dart:convert';

import 'package:drift/native.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/offline/lecture_hors_ligne.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/annonces/data/supabase_annonces_repository.dart';
import 'package:ecoshop_client/features/annonces/domain/annonce.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Annonces hors connexion d'abord : lecture des annonces déjà reçues,
/// publication et confirmation de lecture gardées en file, renvoyées sans
/// doublon au retour du réseau (dépôt réel, seul le réseau est simulé).
class _Serveur {
  bool enLigne = true;
  final appels = <String>[];
  final corps = <String, Map<String, dynamic>>{};

  SupabaseClient client() => SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit),
        httpClient: MockClient((requete) async {
          if (!enLigne) throw http.ClientException('Failed host lookup');
          final rpc = requete.url.pathSegments.last;
          appels.add(rpc);
          final decode = requete.body.isEmpty ? null : jsonDecode(requete.body);
          corps[rpc] = decode is Map ? decode.cast<String, dynamic>() : const {};
          final reponse = switch (rpc) {
            'mes_annonces' => [
                {
                  'id': 'a1',
                  'etablissement_id': 'e1',
                  'etablissement': 'École Bambino',
                  'titre': 'Réunion des parents',
                  'corps': 'Samedi 9 h',
                  'portee': 'ecole',
                  'publiee_le': '2026-10-23T08:00:00Z',
                  'lue': false,
                },
              ],
            'publier_annonce' => {'id': corps[rpc]!['p_id'], 'deja_recue': false, 'familles': 12, 'sms': 0, 'sms_non_envoyes': 0},
            'annonces_etablissement' => <Object>[],
            _ => null,
          };
          return http.Response(jsonEncode(reponse), 200, headers: {'content-type': 'application/json'}, request: requete);
        }),
      );
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SupabaseClient client;
  late DriftSyncRepository file;
  late SupabaseAnnoncesRepository depot;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    serveur = _Serveur();
    client = serveur.client();
    file = DriftSyncRepository(db);
    depot = SupabaseAnnoncesRepository(
      client,
      file,
      LectureHorsLigne(CacheDocumentStore(db, 'annonces_hl'), ValueNotifier<DateTime?>(null)),
    );
  });

  tearDown(() async {
    await client.dispose();
    await db.close();
  });

  test('sans réseau : les annonces déjà reçues restent lisibles', () async {
    expect((await depot.mesAnnonces()).single.titre, 'Réunion des parents');

    serveur.enLigne = false;
    final horsLigne = await depot.mesAnnonces();
    expect(horsLigne.single.titre, 'Réunion des parents');
  });

  test('lecture confirmée sans réseau : gardée, affichée « lue », envoyée au retour', () async {
    await depot.mesAnnonces();
    serveur.enLigne = false;
    await depot.marquerLue('a1');

    expect((await depot.mesAnnonces()).single.lue, isTrue, reason: 'affichée lue tout de suite');
    expect(await file.entreesEnAttente(), hasLength(1));

    serveur.enLigne = true;
    final entree = (await file.entreesEnAttente()).single;
    await RejeuAnnonces(client).rejouer(entree);
    expect(serveur.appels.last, 'marquer_annonce_lue');
    expect(serveur.corps['marquer_annonce_lue'], {'p_annonce': 'a1'});
  });

  test('publication sans réseau : gardée avec sa clé, visible « en attente », renvoyée telle quelle', () async {
    serveur.enLigne = false;
    final r = await depot.publier(
      etablissementId: 'e1',
      portee: PorteeAnnonce.classe,
      cibleId: 'c1',
      titre: '  Sortie au musée ',
      corps: 'Jeudi, retour 16 h',
      parSms: true,
    );
    expect(r.recue, isFalse);

    final liste = await depot.annoncesEtablissement('e1');
    expect(liste.single.enAttenteEnvoi, isTrue);
    expect(liste.single.titre, 'Sortie au musée');

    serveur.enLigne = true;
    final entree = (await file.entreesEnAttente()).single;
    final cle = (jsonDecode(entree.payload)['params'] as Map)['p_id'];
    await RejeuAnnonces(client).rejouer(entree);
    expect(serveur.corps['publier_annonce']!['p_id'], cle, reason: 'même clé : le serveur reconnaît un renvoi');
    expect(serveur.corps['publier_annonce']!['p_cible'], 'c1');
    expect(serveur.corps['publier_annonce']!['p_par_sms'], isTrue);
  });

  test('publication en ligne : nombre de familles renvoyé', () async {
    final r = await depot.publier(etablissementId: 'e1', portee: PorteeAnnonce.ecole, titre: 'Rentrée', corps: 'Lundi 8 h');
    expect(r.recue, isTrue);
    expect(r.familles, 12);
    expect(serveur.corps['publier_annonce']!['p_cible'], isNull, reason: 'toute l’école : pas de cible');
    expect(await file.entreesEnAttente(), isEmpty);
  });
}
