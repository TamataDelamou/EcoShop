import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/chat_ia/application/chat_ia_providers.dart';
import 'package:ecoshop_client/features/chat_ia/domain/chat_ia_repository.dart';
import 'package:ecoshop_client/features/chat_ia/domain/message_chat_ia.dart';
import 'package:ecoshop_client/features/scan_exercice/application/scan_exercice_providers.dart';
import 'package:ecoshop_client/features/scan_exercice/domain/scan_exercice_repository.dart';
import 'package:ecoshop_client/features/scan_exercice/presentation/ecran_scan_exercice.dart';

/// Faux port [ScanExerciceRepository] — simule `demarrer_scan_exercice` sans
/// réseau ni Supabase. La couche SQL/Edge Function elle-même a déjà été
/// vérifiée bout-en-bout en local (podman/pgTAP, `tests/rls/
/// 44_m16_scan_exercice.sql`, 23 assertions) ; ce test-ci vérifie uniquement
/// le câblage de l'écran Flutter : le consentement obligatoire, la capture
/// du premier tour, puis la continuité du guidage via `ChatIaRepository`
/// (réutilisation intégrale de l'infrastructure du sous-livrable 3/7).
class _FauxScanExerciceRepository implements ScanExerciceRepository {
  final List<String> texteDemarre = [];
  final List<bool> consentementDemarre = [];

  @override
  Future<ReponseScanExercice> demarrerScan({
    required String etablissementId,
    required String ficheEleveId,
    required String texteExtrait,
    required bool consentement,
  }) async {
    texteDemarre.add(texteExtrait);
    consentementDemarre.add(consentement);
    return const ReponseScanExercice(
      conversationId: 'conv-scan-1',
      matiere: 'Mathématiques',
      chapitre: 'Équations du premier degré',
      reply: 'Analysons ensemble : quelle est la première étape pour isoler x ?',
    );
  }
}

class _FauxChatIaRepository implements ChatIaRepository {
  final List<String> messagesEnvoyes = [];
  int _compteurMessage = 0;

  @override
  Future<String> obtenirConversationLibre(String etablissementId) async => 'conv-libre';

  @override
  Future<List<MessageChatIa>> historique(String conversationId) async => const [];

  @override
  Future<ReponseChatIa> envoyerMessage({
    String? conversationId,
    String? etablissementId,
    required String message,
  }) async {
    messagesEnvoyes.add(message);
    return ReponseChatIa(conversationId: conversationId ?? 'conv-scan-1', reponse: 'C\'est bien, continue ainsi.');
  }

  @override
  Future<ReponseAnalyseRisque> demarrerAnalyseRisque({
    required String etablissementId,
    required String cibleType,
    String? cibleId,
  }) {
    throw UnimplementedError();
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
    required _FauxScanExerciceRepository depotScan,
    required _FauxChatIaRepository depotChat,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scanExerciceRepositoryProvider.overrideWithValue(depotScan),
          chatIaRepositoryProvider.overrideWithValue(depotChat),
        ],
        child: const MaterialApp(
          home: EcranScanExercice(etablissementId: 'et1', ficheEleveId: 'fiche1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("« Analyser » reste désactivé tant que le texte est vide ou le consentement absent", (tester) async {
    await monter(tester, depotScan: _FauxScanExerciceRepository(), depotChat: _FauxChatIaRepository());

    FilledButton bouton() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Analyser'));

    expect(bouton().onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, '2x + 3 = 11');
    await tester.pump();
    expect(bouton().onPressed, isNull, reason: 'texte présent mais consentement non coché');

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(bouton().onPressed, isNotNull, reason: 'texte + consentement explicites réunis');
  });

  testWidgets(
    'Démarrage du scan : affiche matière/chapitre + première réponse, puis la continuation réutilise ChatIaRepository',
    (tester) async {
      final depotScan = _FauxScanExerciceRepository();
      final depotChat = _FauxChatIaRepository();
      await monter(tester, depotScan: depotScan, depotChat: depotChat);

      await tester.enterText(find.byType(TextField).first, 'Résoudre : 2x + 3 = 11');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Analyser'));
      await tester.pumpAndSettle();

      expect(depotScan.texteDemarre, ['Résoudre : 2x + 3 = 11']);
      expect(depotScan.consentementDemarre, [true]);
      expect(find.textContaining('Mathématiques'), findsOneWidget);
      expect(find.textContaining('Équations du premier degré'), findsOneWidget);
      expect(
        find.text('Analysons ensemble : quelle est la première étape pour isoler x ?'),
        findsOneWidget,
      );

      // Le tour suivant passe par `ChatIaRepository.envoyerMessage`, jamais
      // un second appel à `demarrer_scan_exercice`.
      await tester.enterText(find.byType(TextField).first, 'x = 4 ?');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(depotChat.messagesEnvoyes, ['x = 4 ?']);
      expect(find.text('x = 4 ?'), findsOneWidget);
      expect(find.text('C\'est bien, continue ainsi.'), findsOneWidget);
    },
  );
}
