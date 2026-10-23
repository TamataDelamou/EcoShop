import 'package:ecoshop_client/features/cahier_liaison/application/cahier_liaison_providers.dart';
import 'package:ecoshop_client/features/cahier_liaison/domain/cahier_liaison.dart';
import 'package:ecoshop_client/features/cahier_liaison/presentation/ecran_cahier_liaison.dart';
import 'package:ecoshop_client/features/cahier_liaison/presentation/ecran_eleves_liaison.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FauxCahier implements CahierLiaisonRepository {
  _FauxCahier({this.mots = const [], this.liste = const []});

  List<MotLiaison> mots;
  List<EleveLiaison> liste;
  final appels = <String>[];
  bool horsLigne = false;

  @override
  Future<List<EleveLiaison>> eleves({String? etablissementId}) async => liste;

  @override
  Future<List<MotLiaison>> cahier(String ficheEleveId) async => mots;

  @override
  Future<bool> ecrireMot(String ficheEleveId, String corps) async {
    appels.add('mot:$ficheEleveId:$corps');
    return !horsLigne;
  }

  @override
  Future<bool> repondre({required String ficheEleveId, required String motId, required String corps}) async {
    appels.add('reponse:$motId:$corps');
    return !horsLigne;
  }

  @override
  Future<void> confirmerLecture(String motId) async => appels.add('lu:$motId');

  @override
  Future<void> masquer(String messageId, String motif) async => appels.add('masquer:$messageId:$motif');
}

MotLiaison _mot({bool lu = false, int? lectures, int? parents, List<MessageLiaison> reponses = const []}) => MotLiaison(
      id: 'm1',
      ficheEleveId: 'f1',
      corps: 'Awa a oublié son cahier de maths.',
      creeLe: DateTime(2026, 10, 23, 8),
      auteur: 'M. Camara',
      lu: lu,
      lectures: lectures,
      parents: parents,
      reponses: reponses,
    );

void main() {
  Future<void> monter(WidgetTester tester, _FauxCahier faux, Widget ecran) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [cahierLiaisonRepositoryProvider.overrideWithValue(faux)],
      child: MaterialApp(home: ecran),
    ));
    await tester.pumpAndSettle();
  }

  const ecranParent = EcranCahierLiaison(ficheEleveId: 'f1', nomEleve: 'Awa', personnel: false);
  const ecranProf = EcranCahierLiaison(ficheEleveId: 'f1', nomEleve: 'Awa', personnel: true);
  const ecranDirection = EcranCahierLiaison(ficheEleveId: 'f1', nomEleve: 'Awa', personnel: true, direction: true);

  testWidgets('parent : « J’ai lu », réponse ; pas de nouveau mot ni de masquage', (tester) async {
    final faux = _FauxCahier(mots: [_mot()]);
    await monter(tester, faux, ecranParent);

    expect(find.byKey(const Key('champ_nouveau_mot')), findsNothing);
    expect(find.byKey(const Key('masquer_m1')), findsNothing);
    await tester.tap(find.byKey(const Key('confirmer_m1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('champ_reponse_m1')), 'Merci, je le lui rappelle.');
    await tester.tap(find.byKey(const Key('envoyer_reponse_m1')));
    await tester.pumpAndSettle();

    expect(faux.appels, ['lu:m1', 'reponse:m1:Merci, je le lui rappelle.']);
  });

  testWidgets('parent : lecture déjà confirmée affichée', (tester) async {
    await monter(tester, _FauxCahier(mots: [_mot(lu: true)]), ecranParent);
    expect(find.text('Lecture confirmée'), findsOneWidget);
    expect(find.byKey(const Key('confirmer_m1')), findsNothing);
  });

  testWidgets('enseignant : voit qui a lu, écrit un mot ; sans réseau, prévenu de l’envoi différé', (tester) async {
    final faux = _FauxCahier(mots: [_mot(lectures: 1, parents: 2)])..horsLigne = true;
    await monter(tester, faux, ecranProf);

    expect(find.text('Lu par 1/2 parent(s)'), findsOneWidget);
    expect(find.byKey(const Key('masquer_m1')), findsNothing, reason: 'seule la direction masque');
    await tester.enterText(find.byKey(const Key('champ_nouveau_mot')), 'Sortie vendredi.');
    await tester.tap(find.byKey(const Key('bouton_envoyer_mot')));
    await tester.pumpAndSettle();

    expect(faux.appels, ['mot:f1:Sortie vendredi.']);
    expect(find.textContaining('partira dès le retour de la connexion'), findsOneWidget);
  });

  testWidgets('direction : masque une réponse avec une raison (journalisé)', (tester) async {
    final faux = _FauxCahier(mots: [
      _mot(lectures: 1, parents: 1, reponses: [
        MessageLiaison(id: 'r1', corps: 'Propos déplacés', creeLe: DateTime(2026, 10, 23, 9), auteur: 'Un parent', auteurParent: true),
      ]),
    ]);
    await monter(tester, faux, ecranDirection);

    await tester.tap(find.byKey(const Key('masquer_r1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('inscrite au journal'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('champ_motif_masquage')), 'Propos déplacés');
    await tester.tap(find.widgetWithText(FilledButton, 'Masquer'));
    await tester.pumpAndSettle();

    expect(faux.appels, ['masquer:r1:Propos déplacés']);
  });

  testWidgets('choix de l’élève : badge des messages à lire', (tester) async {
    await monter(
      tester,
      _FauxCahier(liste: const [EleveLiaison(ficheEleveId: 'f1', nom: 'Awa Bah', classe: 'CM1', aLire: 2)]),
      const EcranElevesLiaison(),
    );
    expect(find.text('Awa Bah'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });
}
