import 'package:ecoshop_client/features/revision/application/revision_providers.dart';
import 'package:ecoshop_client/features/revision/data/revision_repository.dart';
import 'package:ecoshop_client/features/revision/domain/examen.dart';
import 'package:ecoshop_client/features/revision/domain/examen_national.dart';
import 'package:ecoshop_client/features/revision/domain/maitrise.dart';
import 'package:ecoshop_client/features/revision/domain/quiz.dart';
import 'package:ecoshop_client/features/revision/presentation/ecran_espace_examen.dart';
import 'package:ecoshop_client/features/revision/presentation/ecran_examen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

QuestionQuiz q(String id, String matiere, String competence) => QuestionQuiz.depuisJson({
      'id': id,
      'matiere_id': matiere,
      'version': 1,
      'type': 'vrai_faux',
      'difficulte': 'moyen',
      'competence_id': competence,
      'enonce': 'Q $id',
      'contenu': const <String, dynamic>{},
      'reponse': {'valeur': true},
      'explication': 'E',
    });

final paquet = PaquetRevision(
  matieres: const [MatiereRevision(id: 'math', nom: 'Mathématiques'), MatiereRevision(id: 'fr', nom: 'Français')],
  competences: const [
    CompetenceRevision(id: 'k_math', matiereId: 'math', libelle: 'Fractions'),
    CompetenceRevision(id: 'k_fr', matiereId: 'fr', libelle: 'Accords'),
  ],
  questions: [for (var i = 0; i < 6; i++) q('m$i', 'math', 'k_math'), for (var i = 0; i < 6; i++) q('f$i', 'fr', 'k_fr')],
);

Map<String, dynamic> json({bool finPrimaire = false, bool strict = false, List<Map<String, dynamic>> blancs = const []}) => {
      'id': 'bepc',
      'code': 'BEPC',
      'nom': 'Brevet d’Études du Premier Cycle',
      'organisme': 'Ministère',
      'pays_code': 'GN',
      'fin_primaire': finPrimaire,
      'mois_session': 6,
      'session': null,
      'epreuves': [
        {'id': 'e_math', 'libelle': 'Mathématiques', 'duree_min': 120, 'coefficient': 3, 'questions_blanc': 5, 'matiere_id': 'math'},
        {'id': 'e_fr', 'libelle': 'Français', 'duree_min': 90, 'coefficient': 1, 'questions_blanc': 5, 'matiere_id': 'fr'},
      ],
      'annales': [
        {'id': 'a1', 'annee': 2025, 'titre': 'BEPC 2025 Maths', 'source': 'Ministère', 'epreuve_id': 'e_math', 'questions': ['m0', 'm1']},
      ],
      'blancs': blancs,
      'chrono_strict': strict,
    };

void main() {
  group('espace d’examen', () {
    test('date estimée au 15 du mois de session si aucune date n’est déclarée', () {
      final x = EspaceExamen.depuisJson(json());
      final d = x.dateExamen(DateTime(2026, 10, 31))!;
      expect(d.date, DateTime(2027, 6, 15));
      expect(d.estimee, isTrue);
      expect(x.joursRestants(DateTime(2027, 6, 1)), 14);
    });

    test('note prévisionnelle pondérée par les coefficients (RG-013-02)', () {
      final x = EspaceExamen.depuisJson(json(blancs: [
        {'epreuve_id': 'e_math', 'nombre': 2, 'derniere_note': 8, 'meilleure_note': 10},
      ]));
      // Maths : blanc 8/20 (coef 3) ; français : maîtrise 70 % → 14/20 (coef 1).
      final p = x.notePrevisionnelle(ProfilMaitrise({'k_fr': const CompetenceMaitrise(competenceId: 'k_fr', maitrise: 0.7, reponses: 5)}), paquet)!;
      expect(p.note, 9.5);
      expect(p.couverture, 1);
      expect(x.epreuvePrioritaire(const ProfilMaitrise(), paquet)!.id, 'e_math');
    });

    test('fin de primaire : chronomètre indicatif sauf si le parent l’active (13.3)', () {
      expect(EspaceExamen.depuisJson(json()).remiseAutomatique, isTrue);
      expect(EspaceExamen.depuisJson(json(finPrimaire: true)).remiseAutomatique, isFalse);
      expect(EspaceExamen.depuisJson(json(finPrimaire: true, strict: true)).remiseAutomatique, isTrue);
    });

    test('chronomètre indicatif : la copie n’est pas ramassée, le dépassement est compté', () {
      final debut = DateTime(2026, 10, 31, 9);
      final e = SessionExamen(
        id: 'x',
        ficheId: 'f',
        dureeLimiteS: 60,
        commenceLe: debut,
        remiseAutomatique: false,
        examenId: 'bepc',
        epreuveId: 'e_math',
        questions: [q('m0', 'math', 'k_math')],
      );
      expect(e.depassementS(debut.add(const Duration(seconds: 90))), 30);
      e.remettre(debut.add(const Duration(seconds: 90)));
      expect(e.dureeS, 90, reason: 'temps réel, au-delà du conseillé');
      expect(e.versTentative()['examen_id'], 'bepc');
      expect(e.versTentative()['epreuve_id'], 'e_math');
    });
  });

  testWidgets('écran de l’espace : compte à rebours, épreuves, annales', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final espace = EspaceRevision(
      niveau: const NiveauRevision(niveauId: 'n10', nom: '10e', grade: 10),
      paquet: paquet,
      traces: const {},
      resume: const ResumeRevision(),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        espaceRevisionProvider('f1').overrideWith((ref) async => espace),
        espacesExamensProvider('f1').overrideWith((ref) async => [EspaceExamen.depuisJson(json())]),
        progressionRevisionProvider((fiche: 'f1', petites: false)).overrideWith((ref) async => const ProgressionRevision()),
      ],
      child: const MaterialApp(home: EcranEspaceExamen(ficheId: 'f1', prenom: 'Awa', parent: false, examenId: 'bepc')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Préparer le BEPC'), findsOneWidget);
    expect(find.byKey(const Key('examen_compte_rebours')), findsOneWidget);
    expect(find.textContaining('date estimée'), findsOneWidget);
    expect(find.byKey(const Key('examen_prevision_vide')), findsOneWidget);
    expect(find.byKey(const ValueKey('epreuve_e_math')), findsOneWidget);
    expect(find.text('BEPC 2025 Maths'), findsOneWidget);
    expect(find.textContaining('S’entraîner en priorité : Mathématiques'), findsOneWidget);

    // Version interactive de l'annale : examen à la durée de l'épreuve.
    await tester.tap(find.byKey(const ValueKey('annale_faire_a1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(EcranExamen), findsOneWidget);
    expect(find.text('02:00:00'), findsNothing);
    expect(find.text('2:00:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // arrête le chronomètre
  });
}
