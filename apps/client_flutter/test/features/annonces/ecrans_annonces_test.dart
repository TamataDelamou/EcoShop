import 'package:ecoshop_client/features/annonces/application/annonces_providers.dart';
import 'package:ecoshop_client/features/annonces/domain/annonce.dart';
import 'package:ecoshop_client/features/annonces/presentation/ecran_annonces.dart';
import 'package:ecoshop_client/features/annonces/presentation/ecran_annonces_direction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FauxAnnonces implements AnnoncesRepository {
  _FauxAnnonces({this.recues = const [], this.ecole = const []});

  List<Annonce> recues;
  List<Annonce> ecole;
  final appels = <String>[];
  ErreurAnnonces? erreur;

  @override
  Future<List<Annonce>> mesAnnonces() async => recues;

  @override
  Future<void> marquerLue(String annonceId) async => appels.add('lue:$annonceId');

  @override
  Future<List<Annonce>> annoncesEtablissement(String etablissementId) async => ecole;

  @override
  Future<PorteesDisponibles> portees(String etablissementId) async => const PorteesDisponibles(
        classes: [CibleAnnonce('c1', 'CM1'), CibleAnnonce('c2', 'CM2')],
        niveaux: [CibleAnnonce('n1', 'Primaire CM')],
      );

  @override
  Future<ResultatPublication> publier({
    required String etablissementId,
    required PorteeAnnonce portee,
    String? cibleId,
    required String titre,
    required String corps,
    bool importante = false,
    bool parSms = false,
  }) async {
    appels.add('publier:${portee.code}:$cibleId:$titre:$importante:$parSms');
    final e = erreur;
    if (e != null) throw e;
    return const ResultatPublication(recue: true, familles: 24, sms: 10, smsNonEnvoyes: 14);
  }

  @override
  Future<void> masquer(String annonceId, String motif) async => appels.add('masquer:$annonceId:$motif');
}

Annonce _annonce(String id, {bool lue = false, int? familles, int? lues, DateTime? masquee}) => Annonce(
      id: id,
      etablissementId: 'e1',
      etablissement: 'École Bambino',
      titre: 'Réunion $id',
      corps: 'Réunion des parents samedi à 9 h dans la cour de l’école.',
      portee: PorteeAnnonce.ecole,
      publieeLe: DateTime(2026, 10, 23, 8),
      lue: lue,
      familles: familles,
      famillesLues: lues,
      masqueeLe: masquee,
    );

void main() {
  Future<void> monter(WidgetTester tester, _FauxAnnonces faux, Widget ecran) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [annoncesRepositoryProvider.overrideWithValue(faux)],
      child: MaterialApp(home: ecran),
    ));
    await tester.pumpAndSettle();
  }

  group('Familles et élèves', () {
    testWidgets('ouvrir une annonce non lue confirme la lecture, une seule fois', (tester) async {
      final faux = _FauxAnnonces(recues: [_annonce('a1'), _annonce('a2', lue: true)]);
      await monter(tester, faux, const EcranAnnonces());

      expect(find.byIcon(Icons.circle), findsOneWidget, reason: 'une seule non lue');
      await tester.tap(find.text('Réunion a1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réunion a1'));
      await tester.tap(find.text('Réunion a1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réunion a2'));
      await tester.pumpAndSettle();

      expect(faux.appels, ['lue:a1'], reason: 'déjà lue : rien n’est renvoyé');
      expect(find.byIcon(Icons.circle), findsNothing);
    });

    testWidgets('aucune annonce : message engageant', (tester) async {
      await monter(tester, _FauxAnnonces(), const EcranAnnonces());
      expect(find.textContaining('Vous serez prévenu(e)'), findsOneWidget);
    });
  });

  group('Direction', () {
    testWidgets('combien de familles ont lu ; masquée affichée comme telle', (tester) async {
      final faux = _FauxAnnonces(ecole: [
        _annonce('a1', familles: 24, lues: 17),
        _annonce('a2', familles: 3, lues: 0, masquee: DateTime(2026, 10, 23, 9)),
      ]);
      await monter(tester, faux, const EcranAnnoncesDirection(etablissementId: 'e1'));

      expect(find.textContaining('17/24 familles ont lu'), findsOneWidget);
      expect(find.textContaining('Masquée'), findsOneWidget);
      expect(find.byKey(const Key('masquer_a2')), findsNothing, reason: 'déjà masquée');
    });

    testWidgets('publier pour une classe : la classe est obligatoire ; SMS et important transmis', (tester) async {
      final faux = _FauxAnnonces();
      await monter(tester, faux, const EcranAnnoncesDirection(etablissementId: 'e1'));

      await tester.tap(find.byKey(const Key('bouton_nouvelle_annonce')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Classe'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ_titre_annonce')), 'Sortie au musée');
      await tester.enterText(find.byKey(const Key('champ_corps_annonce')), 'Jeudi, retour à 16 h.');
      await tester.ensureVisible(find.byKey(const Key('bouton_publier_annonce')));
      await tester.tap(find.byKey(const Key('bouton_publier_annonce')));
      await tester.pumpAndSettle();
      expect(faux.appels, isEmpty);
      expect(find.text('Choisissez une classe.'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('choix_cible')));
      await tester.tap(find.byKey(const Key('choix_cible')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CM2').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('interrupteur_sms')));
      await tester.tap(find.byKey(const Key('interrupteur_sms')));
      await tester.tap(find.byKey(const Key('interrupteur_important')));
      await tester.ensureVisible(find.byKey(const Key('bouton_publier_annonce')));
      await tester.tap(find.byKey(const Key('bouton_publier_annonce')));
      await tester.pumpAndSettle();

      expect(faux.appels, ['publier:classe:c2:Sortie au musée:true:true']);
      expect(find.textContaining('24 famille(s)'), findsOneWidget);
      expect(find.textContaining('14 SMS non envoyé(s) : crédits épuisés'), findsOneWidget);
    });

    testWidgets('masquer : raison demandée, action annoncée comme journalisée', (tester) async {
      final faux = _FauxAnnonces(ecole: [_annonce('a1', familles: 2, lues: 1)]);
      await monter(tester, faux, const EcranAnnoncesDirection(etablissementId: 'e1'));

      await tester.tap(find.byKey(const Key('masquer_a1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('inscrite au journal'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('champ_motif_masquage')), 'Mauvaise date');
      await tester.tap(find.widgetWithText(FilledButton, 'Masquer'));
      await tester.pumpAndSettle();

      expect(faux.appels, ['masquer:a1:Mauvaise date']);
    });
  });
}
