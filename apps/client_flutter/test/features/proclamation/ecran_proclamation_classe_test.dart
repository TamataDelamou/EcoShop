import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/proclamation/application/proclamation_providers.dart';
import 'package:ecoshop_client/features/proclamation/domain/eleve_mention.dart';
import 'package:ecoshop_client/features/proclamation/domain/proclamation_repository.dart';
import 'package:ecoshop_client/features/proclamation/presentation/ecran_proclamation_classe.dart';
import 'package:ecoshop_client/features/scolarite/domain/classe.dart';

/// Faux port [ProclamationRepository] — la couche SQL (RLS, verrou total,
/// exigence de mention) a déjà été vérifiée en local (pgTAP,
/// `tests/rls/55`) ; ce test-ci vérifie uniquement le câblage de l'écran.
class _FauxProclamationRepository implements ProclamationRepository {
  _FauxProclamationRepository({
    required bool estExamen,
    required bool estProclamee,
    List<EleveMention> eleves = const [],
    this.erreurProclamation,
  })  : _estExamen = estExamen,
        _estProclamee = estProclamee,
        _eleves = eleves;

  bool _estExamen;
  bool _estProclamee;
  List<EleveMention> _eleves;
  final String? erreurProclamation;
  bool proclamerAppele = false;
  String? derniereMentionDefinie;

  @override
  Future<bool> classeEstExamen(String classeId) async => _estExamen;

  @override
  Future<bool> classeEstProclamee({required String classeId, required String anneeScolaireId}) async =>
      _estProclamee;

  @override
  Future<List<EleveMention>> elevesDeClasse(String classeId) async => _eleves;

  @override
  Future<void> definirMentionFinale({required String inscriptionId, required String mention}) async {
    derniereMentionDefinie = mention;
    _eleves = [
      for (final e in _eleves)
        if (e.inscriptionId == inscriptionId)
          EleveMention(
            inscriptionId: e.inscriptionId,
            ficheEleveId: e.ficheEleveId,
            nom: e.nom,
            prenom: e.prenom,
            mentionFinale: mention,
          )
        else
          e,
    ];
  }

  @override
  Future<void> proclamerClasse({required String classeId, required String anneeScolaireId}) async {
    proclamerAppele = true;
    if (erreurProclamation != null) {
      throw ErreurProclamation(erreurProclamation!);
    }
    _estProclamee = true;
  }
}

final _classeTest = Classe(
  id: 'c1',
  etablissementId: 'e1',
  anneeScolaireId: 'a1',
  code: 'TermA',
  nom: 'Terminale A',
);

void main() {
  Future<void> monter(WidgetTester tester, {required ProclamationRepository depot}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [proclamationRepositoryProvider.overrideWithValue(depot)],
        child: MaterialApp(home: EcranProclamationClasse(classe: _classeTest)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('classe non-examen : aucune mention requise, bouton Proclamer disponible', (tester) async {
    final depot = _FauxProclamationRepository(estExamen: false, estProclamee: false);
    await monter(tester, depot: depot);

    expect(find.textContaining('n\'est pas une classe d\'examen'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Proclamer la classe'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Proclamer la classe'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Proclamer'));
    await tester.pumpAndSettle();

    expect(depot.proclamerAppele, isTrue);
  });

  testWidgets('classe examen : liste les élèves avec leur mention, sélectionner appelle le port', (tester) async {
    final depot = _FauxProclamationRepository(
      estExamen: true,
      estProclamee: false,
      eleves: const [
        EleveMention(inscriptionId: 'i1', ficheEleveId: 'f1', nom: 'Bah', prenom: 'Alpha'),
      ],
    );
    await monter(tester, depot: depot);

    expect(find.text('Alpha Bah'), findsOneWidget);
    expect(find.text('Mention non définie'), findsOneWidget);

    await tester.tap(find.text('Admis(e)'));
    await tester.pumpAndSettle();

    expect(depot.derniereMentionDefinie, 'admis');
  });

  testWidgets('proclamation refusée (mention manquante) affiche un message explicite', (tester) async {
    final depot = _FauxProclamationRepository(
      estExamen: true,
      estProclamee: false,
      eleves: const [
        EleveMention(inscriptionId: 'i1', ficheEleveId: 'f1', nom: 'Bah', prenom: 'Alpha'),
      ],
      erreurProclamation: 'MENTION_MANQUANTE',
    );
    await monter(tester, depot: depot);

    await tester.tap(find.widgetWithText(FilledButton, 'Proclamer la classe'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Proclamer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('n\'ont pas encore de mention finale'), findsOneWidget);
  });

  testWidgets('classe déjà proclamée : verrou affiché, aucun bouton', (tester) async {
    final depot = _FauxProclamationRepository(estExamen: true, estProclamee: true);
    await monter(tester, depot: depot);

    expect(find.textContaining('verrouillage définitif'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Proclamer la classe'), findsNothing);
  });
}
