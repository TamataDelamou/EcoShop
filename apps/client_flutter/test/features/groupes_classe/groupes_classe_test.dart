import 'dart:convert';

import 'package:drift/native.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/offline/lecture_hors_ligne.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/core/sync/sync_engine.dart';
import 'package:ecoshop_client/features/groupes_classe/application/groupes_classe_providers.dart';
import 'package:ecoshop_client/features/groupes_classe/data/supabase_groupes_classe_repository.dart';
import 'package:ecoshop_client/features/groupes_classe/domain/groupe_classe.dart';
import 'package:ecoshop_client/features/groupes_classe/presentation/ecran_fil_groupe.dart';
import 'package:ecoshop_client/features/groupes_classe/presentation/ecran_groupes_classe.dart';
import 'package:ecoshop_client/features/groupes_classe/presentation/ecran_heures_messagerie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Groupes de classe (REG-34) : dépôt hors connexion d'abord (réseau
/// simulé) et écrans.
class _Faux implements GroupesClasseRepository {
  _Faux({this.groupes = const MesGroupes(), this.messages = const []});

  MesGroupes groupes;
  List<MessageGroupe> messages;
  List<SignalementGroupe> liste = const [];
  final appels = <String>[];
  bool horsLigne = false;

  @override
  Future<MesGroupes> mesGroupes(String etablissementId) async => groupes;

  @override
  Future<List<MessageGroupe>> fil(String groupeId) async => messages;

  @override
  Future<bool> envoyer(String groupeId, String corps) async {
    appels.add('envoyer:$groupeId:$corps');
    return !horsLigne;
  }

  @override
  Future<void> marquerLu(String groupeId) async => appels.add('lu:$groupeId');

  @override
  Future<String> creer(String classeId) async {
    appels.add('creer:$classeId');
    return 'g-$classeId';
  }

  @override
  Future<void> regler(String groupeId, {required bool elevesPeuventEcrire, required bool actif}) async =>
      appels.add('regler:$groupeId:$elevesPeuventEcrire:$actif');

  @override
  Future<void> signaler(String messageId, String motif) async => appels.add('signaler:$messageId:$motif');

  @override
  Future<void> masquer(String messageId, String motif) async => appels.add('masquer:$messageId:$motif');

  @override
  Future<List<SignalementGroupe>> signalements(String groupeId) async => liste;

  @override
  Future<void> ecarter(String signalementId) async => appels.add('ecarter:$signalementId');

  @override
  Future<HeuresMessagerie?> heures(String etablissementId) async =>
      const HeuresMessagerie(debut: '07:00', fin: '19:00', jours: [1, 2, 3, 4, 5, 6]);

  @override
  Future<void> definirHeures(String etablissementId,
          {required String debut, required String fin, required List<int> jours}) async =>
      appels.add('heures:$debut-$fin:${jours.join(',')}');
}

const _groupeEleve = GroupeClasse(id: 'g1', nom: 'Classe 6e A', classeId: 'c1', classe: '6e A');
const _groupeProf = GroupeClasse(id: 'g1', nom: 'Classe 6e A', classeId: 'c1', classe: '6e A', moderateur: true);

MessageGroupe _msg(String id, String corps, {bool deMoi = false, bool adulte = false}) =>
    MessageGroupe(id: id, creeLe: DateTime(2026, 10, 28, 10), auteur: deMoi ? null : 'M. Camara', deMoi: deMoi, adulte: adulte, corps: corps);

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
          if (rpc == 'envoyer_message_groupe' && corps[rpc]!['p_corps'] == 'tard') {
            return http.Response(jsonEncode({'code': '42501', 'message': 'HORS_HEURES_MESSAGERIE'}), 403,
                headers: {'content-type': 'application/json'}, request: requete);
          }
          final reponse = switch (rpc) {
            'mes_groupes_classe' => {
                'groupes': [
                  {'id': 'g1', 'nom': 'Classe 6e A', 'classe_id': 'c1', 'classe': '6e A', 'statut': 'active',
                   'eleves_peuvent_ecrire': true, 'moderateur': false, 'non_lus': 2,
                   'dernier': {'auteur': 'M. Camara', 'extrait': 'Bienvenue', 'cree_le': '2026-10-28T10:00:00Z'}},
                ],
                'classes_sans_groupe': <Object>[],
              },
            'fil_groupe_classe' => [
                {'id': 'm1', 'auteur': 'M. Camara', 'adulte': true, 'corps': 'Bienvenue', 'masque': false,
                 'cree_le': '2026-10-28T10:00:00Z'},
              ],
            _ => {'deja_recu': false},
          };
          return http.Response(jsonEncode(reponse), 200, headers: {'content-type': 'application/json'}, request: requete);
        }),
      );
}

void main() {
  group('dépôt hors connexion d’abord', () {
    late AppDatabase db;
    late _Serveur serveur;
    late SupabaseClient client;
    late DriftSyncRepository file;
    late SupabaseGroupesClasseRepository depot;

    setUp(() {
      db = AppDatabase.pourTests(NativeDatabase.memory());
      serveur = _Serveur();
      client = serveur.client();
      file = DriftSyncRepository(db);
      depot = SupabaseGroupesClasseRepository(
        client,
        file,
        LectureHorsLigne(CacheDocumentStore(db, 'groupes_classe_hl'), ValueNotifier<DateTime?>(null)),
      );
    });

    tearDown(() async {
      await client.dispose();
      await db.close();
    });

    test('sans réseau : groupes et fil déjà reçus restent lisibles', () async {
      await depot.mesGroupes('e1');
      await depot.fil('g1');
      serveur.enLigne = false;
      expect((await depot.mesGroupes('e1')).groupes.single.nonLus, 2);
      expect((await depot.fil('g1')).single.corps, 'Bienvenue');
    });

    test('message sans réseau : affiché « en attente », renvoyé au retour avec sa clé', () async {
      await depot.fil('g1');
      serveur.enLigne = false;
      expect(await depot.envoyer('g1', ' Merci monsieur '), isFalse);
      final fil = await depot.fil('g1');
      expect(fil.last.enAttenteEnvoi, isTrue);
      expect(fil.last.corps, 'Merci monsieur');

      serveur.enLigne = true;
      for (final e in await file.entreesEnAttente()) {
        await RejeuGroupesClasse(client).rejouer(e);
      }
      expect(serveur.corps['envoyer_message_groupe'], {'p_id': fil.last.id, 'p_groupe': 'g1', 'p_corps': 'Merci monsieur'});
    });

    test('refus métier au rejeu (hors des heures) : rejet définitif expliqué', () async {
      serveur.enLigne = false;
      await depot.envoyer('g1', 'tard');
      serveur.enLigne = true;
      final entree = (await file.entreesEnAttente()).single;
      await expectLater(
        RejeuGroupesClasse(client).rejouer(entree),
        throwsA(isA<RejetDefinitif>().having((r) => r.message, 'message', contains('heures de l’école'))),
      );
    });

    test('refus en ligne : erreur traduite, rien n’est gardé', () async {
      await expectLater(depot.envoyer('g1', 'tard'),
          throwsA(isA<ErreurGroupe>().having((e) => e.code, 'code', 'HORS_HEURES_MESSAGERIE')));
      expect(await file.entreesEnAttente(), isEmpty);
    });
  });

  group('écrans', () {
    Future<void> monter(WidgetTester tester, _Faux faux, Widget ecran) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [groupesClasseRepositoryProvider.overrideWithValue(faux)],
        child: MaterialApp(home: ecran),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('enseignant : ouvre le groupe d’une classe qui n’en a pas', (tester) async {
      final faux = _Faux(groupes: const MesGroupes(classesSansGroupe: [ClasseSansGroupe(classeId: 'c2', classe: '6e B')]));
      await monter(tester, faux, const EcranGroupesClasse(etablissementId: 'e1'));

      expect(find.textContaining('du lundi au samedi, de 7 h à 19 h'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ouvrir_groupe_c2')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Les parents n’y ont pas accès'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Ouvrir'));
      await tester.pumpAndSettle();
      expect(faux.appels, ['creer:c2']);
    });

    testWidgets('liste : non lus, signalements, groupe réservé aux annonces', (tester) async {
      final faux = _Faux(groupes: const MesGroupes(groupes: [
        GroupeClasse(id: 'g1', nom: 'Classe 6e A', classeId: 'c1', classe: '6e A', nonLus: 3),
        GroupeClasse(id: 'g2', nom: 'Classe 6e B', classeId: 'c2', classe: '6e B', moderateur: true, signalements: 1,
            elevesPeuventEcrire: false),
      ]));
      await monter(tester, faux, const EcranGroupesClasse(etablissementId: 'e1', direction: true));
      expect(find.byKey(const Key('non_lus_g1')), findsOneWidget);
      expect(find.text('1 signalé'), findsOneWidget);
      expect(find.textContaining('Annonces seulement'), findsOneWidget);
      expect(find.byKey(const Key('regler_heures')), findsOneWidget, reason: 'la direction règle les heures');
    });

    testWidgets('élève : écrit dans sa classe, signale ; ni retrait ni réglages', (tester) async {
      final faux = _Faux(messages: [_msg('m1', 'Bienvenue', adulte: true)]);
      await monter(tester, faux, const EcranFilGroupe(groupe: _groupeEleve, etablissementId: 'e1'));

      expect(faux.appels, ['lu:g1'], reason: 'le fil ouvert est marqué lu');
      expect(find.byKey(const Key('reglages_groupe')), findsNothing);
      await tester.enterText(find.byKey(const Key('champ_message_groupe')), 'Merci monsieur');
      await tester.tap(find.byKey(const Key('bouton_envoyer_groupe')));
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const ValueKey('message_m1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action_retirer')), findsNothing);
      await tester.tap(find.byKey(const Key('action_signaler')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ_motif_signalement')), 'Pas gentil');
      await tester.tap(find.widgetWithText(FilledButton, 'Signaler'));
      await tester.pumpAndSettle();

      expect(faux.appels, ['lu:g1', 'envoyer:g1:Merci monsieur', 'signaler:m1:Pas gentil']);
      expect(find.text('Merci, le message a été signalé.'), findsOneWidget);
    });

    testWidgets('élève : groupe réservé aux annonces — lecture seule', (tester) async {
      const annonces = GroupeClasse(id: 'g1', nom: 'Classe 6e A', classeId: 'c1', classe: '6e A', elevesPeuventEcrire: false);
      await monter(tester, _Faux(), const EcranFilGroupe(groupe: annonces, etablissementId: 'e1'));
      expect(find.byKey(const Key('champ_message_groupe')), findsNothing);
      expect(find.textContaining('seuls les enseignants y écrivent'), findsOneWidget);
    });

    testWidgets('élève : message retiré, sans le texte', (tester) async {
      final faux = _Faux(messages: [MessageGroupe(id: 'm2', creeLe: DateTime(2026, 10, 28), auteur: 'Sekou', masque: true)]);
      await monter(tester, faux, const EcranFilGroupe(groupe: _groupeEleve, etablissementId: 'e1'));
      expect(find.text('Message retiré'), findsOneWidget);
    });

    testWidgets('enseignant : retire un message avec une raison, réserve le groupe aux annonces', (tester) async {
      final faux = _Faux(messages: [_msg('m2', 'Hors sujet')]);
      await monter(tester, faux, const EcranFilGroupe(groupe: _groupeProf, etablissementId: 'e1'));

      await tester.longPress(find.byKey(const ValueKey('message_m2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action_retirer')));
      await tester.pumpAndSettle();
      expect(find.textContaining('inscrite au journal'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('champ_motif_masquage')), 'Hors sujet');
      await tester.tap(find.widgetWithText(FilledButton, 'Masquer'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reglages_groupe')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reglage_eleves_ecrivent')));
      await tester.tap(find.byKey(const Key('enregistrer_reglages')));
      await tester.pumpAndSettle();

      expect(faux.appels, ['lu:g1', 'masquer:m2:Hors sujet', 'regler:g1:false:true']);
      expect(find.textContaining('seuls les enseignants y écrivent'), findsOneWidget);
      expect(find.byKey(const Key('champ_message_groupe')), findsOneWidget, reason: 'l’enseignant écrit toujours');
    });

    testWidgets('enseignant : traite un signalement', (tester) async {
      final faux = _Faux(messages: [_msg('m3', 'Moqueries')])
        ..liste = const [SignalementGroupe(id: 's1', messageId: 'm3', motif: 'Moqueries', par: 'Awa', extrait: 'Moqueries')];
      await monter(tester, faux, const EcranFilGroupe(groupe: _groupeProf, etablissementId: 'e1'));
      await tester.tap(find.byKey(const Key('voir_signalements')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('retirer_s1')));
      await tester.pumpAndSettle();
      expect(faux.appels, contains('masquer:m3:Signalé : Moqueries'));
    });

    testWidgets('direction : heures de messagerie, aperçu et contrôle', (tester) async {
      final faux = _Faux();
      await monter(tester, faux, const EcranHeuresMessagerie(
        etablissementId: 'e1',
        actuelles: HeuresMessagerie(debut: '07:00', fin: '19:00', jours: [1, 2, 3, 4, 5, 6]),
      ));
      expect(find.textContaining('du lundi au samedi, de 7 h à 19 h'), findsOneWidget);
      await tester.tap(find.byKey(const Key('jour_6')));
      await tester.pumpAndSettle();
      expect(find.textContaining('du lundi au vendredi'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('enregistrer_heures')));
      await tester.tap(find.byKey(const Key('enregistrer_heures')));
      await tester.pumpAndSettle();
      expect(faux.appels, ['heures:07:00-19:00:1,2,3,4,5']);
    });
  });
}
