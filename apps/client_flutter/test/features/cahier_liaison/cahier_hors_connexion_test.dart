import 'dart:convert';

import 'package:drift/native.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/offline/lecture_hors_ligne.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/cahier_liaison/data/supabase_cahier_liaison_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cahier de liaison hors connexion d'abord : fil lisible sans réseau ;
/// réponse, mot et « J'ai lu » gardés en file, affichés aussitôt, renvoyés
/// avec leur clé au retour du réseau (dépôt réel, réseau simulé).
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
            'cahier_liaison' => [
                {
                  'id': 'm1',
                  'fiche_eleve_id': 'f1',
                  'corps': 'Awa a oublié son cahier de maths.',
                  'cree_le': '2026-10-23T08:00:00Z',
                  'auteur': 'M. Camara',
                  'lu': false,
                  'reponses': <Object>[],
                },
              ],
            'destinataires_liaison' => {
                'heures': {'debut': '07:00', 'fin': '19:00', 'jours': [1, 2, 3, 4, 5, 6], 'ouverte': true},
                'destinataires': [
                  {'id': 'dir', 'nom': 'Mme Diallo', 'role': 'Direction'},
                  {'id': 'prof', 'nom': 'M. Camara', 'role': 'Mathématiques'},
                ],
              },
            _ => {'deja_recu': false},
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
  late SupabaseCahierLiaisonRepository depot;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    serveur = _Serveur();
    client = serveur.client();
    file = DriftSyncRepository(db);
    depot = SupabaseCahierLiaisonRepository(
      client,
      file,
      LectureHorsLigne(CacheDocumentStore(db, 'cahier_liaison_hl'), ValueNotifier<DateTime?>(null)),
    );
  });

  tearDown(() async {
    await client.dispose();
    await db.close();
  });

  test('sans réseau : le fil déjà reçu reste lisible', () async {
    await depot.cahier('f1');
    serveur.enLigne = false;
    expect((await depot.cahier('f1')).single.corps, 'Awa a oublié son cahier de maths.');
  });

  test('« J’ai lu » et réponse sans réseau : affichés aussitôt, envoyés au retour avec leur clé', () async {
    await depot.cahier('f1');
    serveur.enLigne = false;
    await depot.confirmerLecture('m1');
    final recue = await depot.repondre(ficheEleveId: 'f1', motId: 'm1', corps: ' Merci, je le lui rappelle. ');
    expect(recue, isFalse);

    final mot = (await depot.cahier('f1')).single;
    expect(mot.lu, isTrue);
    expect(mot.reponses.single.enAttenteEnvoi, isTrue);
    expect(mot.reponses.single.corps, 'Merci, je le lui rappelle.');

    serveur.enLigne = true;
    for (final e in await file.entreesEnAttente()) {
      await RejeuCahierLiaison(client).rejouer(e);
    }
    expect(serveur.appels, containsAll(['confirmer_lecture_liaison', 'repondre_liaison']));
    expect(serveur.corps['repondre_liaison']!['p_mot'], 'm1');
    expect(serveur.corps['repondre_liaison']!['p_id'], mot.reponses.single.id, reason: 'même clé : aucun doublon');
  });

  test('nouveau mot sans réseau : en tête du fil « en attente d’envoi »', () async {
    serveur.enLigne = false;
    await depot.ecrireMot('f1', 'Sortie scolaire vendredi.');
    final fil = await depot.cahier('f1');
    expect(fil.first.enAttenteEnvoi, isTrue);
    expect(fil.first.corps, 'Sortie scolaire vendredi.');
  });

  test('message à l’école sans réseau (REG-34) : destinataire affiché, envoyé au retour avec sa clé', () async {
    final contacts = await depot.contacts('f1');
    expect(contacts.heures!.libelle, 'du lundi au samedi, de 7 h à 19 h');
    expect([for (final d in contacts.destinataires) d.nom], ['Mme Diallo', 'M. Camara']);

    serveur.enLigne = false;
    expect((await depot.contacts('f1')).destinataires, hasLength(2), reason: 'contacts lisibles sans réseau');
    final recu = await depot.ecrireAEcole(ficheEleveId: 'f1', destinataireId: 'prof', corps: ' Awa sera absente vendredi. ');
    expect(recu, isFalse);

    final mot = (await depot.cahier('f1')).first;
    expect(mot.enAttenteEnvoi, isTrue);
    expect(mot.auteurParent, isTrue);
    expect(mot.destinataire, 'M. Camara');

    serveur.enLigne = true;
    for (final e in await file.entreesEnAttente()) {
      await RejeuCahierLiaison(client).rejouer(e);
    }
    expect(serveur.corps['ecrire_mot_parent'], {
      'p_id': mot.id,
      'p_fiche': 'f1',
      'p_destinataire': 'prof',
      'p_corps': 'Awa sera absente vendredi.',
    }, reason: 'seuls les paramètres de la fonction partent, pas les indications d’affichage');
  });
}
