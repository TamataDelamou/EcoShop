import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/chat_ia/application/chat_ia_providers.dart';
import 'package:ecoshop_client/features/chat_ia/domain/chat_ia_repository.dart';
import 'package:ecoshop_client/features/chat_ia/domain/detail_eleve_pseudonymise.dart';
import 'package:ecoshop_client/features/chat_ia/domain/message_chat_ia.dart';
import 'package:ecoshop_client/features/chat_ia/domain/persona_ia.dart';
import 'package:ecoshop_client/features/chat_ia/presentation/ecran_chat_ia.dart';
import 'package:ecoshop_client/features/scolarite/application/scolarite_providers.dart';

/// Faux port [ChatIaRepository] — simule les deux Edge Functions sans
/// réseau ni Supabase. La couche SQL/Edge Functions elle-même a déjà été
/// vérifiée bout-en-bout en local (podman/supabase functions serve, M16
/// sous-livrable 3/7) ; ce test-ci vérifie uniquement le câblage de l'écran
/// Flutter construit dans ce complément (envoi, affichage, déclenchement
/// structuré, action « qui sont-ils ? », affichage du détail pseudonymisé).
class _FauxChatIaRepository implements ChatIaRepository {
  _FauxChatIaRepository({this.messagesExistants = const []});

  final List<String> messagesEnvoyes = [];
  final List<MessageChatIa> messagesExistants;
  int _compteurMessage = 0;

  @override
  Future<String> obtenirConversationLibre(String etablissementId) async => 'conv-libre-$etablissementId';

  @override
  Future<List<MessageChatIa>> historique(String conversationId) async => messagesExistants;

  @override
  Future<ReponseChatIa> envoyerMessage({
    String? conversationId,
    String? etablissementId,
    required String message,
  }) async {
    messagesEnvoyes.add(message);
    if (message == 'Qui sont-ils ?') {
      return const ReponseChatIa(
        conversationId: 'conv-risque',
        reponse: 'Voici la liste : Élève A, Élève B.',
        detailEleves: [
          DetailElevePseudonymise(pseudonyme: 'Élève A', matricule: 'MAT001', nom: 'Dupont', prenom: 'Jean'),
        ],
      );
    }
    return ReponseChatIa(conversationId: conversationId ?? 'conv-libre', reponse: 'Réponse simulée.');
  }

  @override
  Future<ReponseAnalyseRisque> demarrerAnalyseRisque({
    required String etablissementId,
    required String cibleType,
    String? cibleId,
  }) async {
    return const ReponseAnalyseRisque(
      conversationId: 'conv-risque',
      messageDeclencheur: "Analyse du risque d'échec pour l'établissement entier. Effectif : 100. "
          "Élèves à risque d'échec (score de risque ≥ 0,6) : 7.",
      reponse: '7 élèves sont actuellement identifiés à risque.',
      cibleLabel: "l'établissement entier",
      effectif: 100,
      elevesARisque: 7,
    );
  }

  @override
  Future<MessageChatIa> enregistrerMessage({
    required String conversationId,
    required String sender,
    required String content,
  }) async {
    _compteurMessage++;
    return MessageChatIa(
      id: 'm$_compteurMessage',
      conversationId: conversationId,
      sender: sender,
      content: content,
      createdAt: DateTime.now(),
    );
  }
}

void main() {
  Future<void> monter(
    WidgetTester tester, {
    required PersonaIa persona,
    required _FauxChatIaRepository depot,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatIaRepositoryProvider.overrideWithValue(depot),
          structureEtablissementProvider.overrideWith((ref, anneeId) async => null),
        ],
        child: MaterialApp(home: EcranChatIa(etablissementId: 'et1', persona: persona)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("Tuteur-IA (élève) : envoi d'un message affiche la bulle utilisateur puis la réponse", (tester) async {
    final depot = _FauxChatIaRepository();
    await monter(tester, persona: PersonaIa.eleve, depot: depot);

    expect(find.text('Tuteur-IA'), findsOneWidget);
    // Persona non-direction : jamais de déclenchement structuré.
    expect(find.byIcon(Icons.query_stats_outlined), findsNothing);

    await tester.enterText(find.byType(TextField), 'Comment factoriser x²-1 ?');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(depot.messagesEnvoyes, ['Comment factoriser x²-1 ?']);
    expect(find.text('Comment factoriser x²-1 ?'), findsOneWidget);
    expect(find.text('Réponse simulée.'), findsOneWidget);
  });

  testWidgets(
    'Directeur-Adviser : déclenchement structuré puis « Qui sont-ils ? » révèle le détail pseudonymisé',
    (tester) async {
      final depot = _FauxChatIaRepository();
      await monter(tester, persona: PersonaIa.direction, depot: depot);

      expect(find.text('Directeur-Adviser'), findsOneWidget);
      expect(find.byIcon(Icons.query_stats_outlined), findsOneWidget);

      // 1) Déclenchement structuré — jamais à partir d'un texte libre.
      await tester.tap(find.byIcon(Icons.query_stats_outlined));
      await tester.pumpAndSettle();
      expect(find.text("L'établissement entier"), findsOneWidget);

      await tester.tap(find.text('Analyser'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Analyse du risque d'échec pour l'établissement entier"),
        findsOneWidget,
      );
      expect(find.text('7 élèves sont actuellement identifiés à risque.'), findsOneWidget);

      // 2) L'action rapide « Qui sont-ils ? » n'apparaît qu'après le
      //    déclenchement (conversation groundée).
      expect(find.text('Qui sont-ils ?'), findsOneWidget);
      await tester.tap(find.text('Qui sont-ils ?'));
      await tester.pumpAndSettle();

      expect(depot.messagesEnvoyes, ['Qui sont-ils ?']);
      expect(find.text('Voici la liste : Élève A, Élève B.'), findsOneWidget);

      // 3) Le détail pseudonymisé est replié par défaut, révélé sur action
      //    explicite — jamais envoyé à Anthropic, seulement affiché ici.
      expect(find.text('Élève A → Jean Dupont (MAT001)'), findsNothing);
      await tester.tap(find.textContaining('voir les identités'));
      await tester.pumpAndSettle();
      expect(find.text('Élève A → Jean Dupont (MAT001)'), findsOneWidget);
    },
  );

  testWidgets(
    'Continuité (complément 3/7) : réouvrir l\'écran recharge la conversation libre existante, jamais vide',
    (tester) async {
      final depot = _FauxChatIaRepository(
        messagesExistants: [
          MessageChatIa(
            id: 'm1',
            conversationId: 'conv-libre-et1',
            sender: 'user',
            content: 'Question posée hier',
            createdAt: DateTime(2026, 3, 1),
          ),
          MessageChatIa(
            id: 'm2',
            conversationId: 'conv-libre-et1',
            sender: 'assistant',
            content: 'Réponse donnée hier',
            createdAt: DateTime(2026, 3, 1, 0, 1),
          ),
        ],
      );

      await monter(tester, persona: PersonaIa.eleve, depot: depot);

      // Aucun envoi n'a eu lieu dans ce test : ces messages viennent
      // uniquement du rechargement d'historique à l'ouverture de l'écran.
      expect(depot.messagesEnvoyes, isEmpty);
      expect(find.text('Question posée hier'), findsOneWidget);
      expect(find.text('Réponse donnée hier'), findsOneWidget);
    },
  );
}
