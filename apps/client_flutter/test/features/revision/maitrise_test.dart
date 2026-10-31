import 'package:ecoshop_client/features/revision/application/revision_providers.dart';
import 'package:ecoshop_client/features/revision/data/revision_repository.dart';
import 'package:ecoshop_client/features/revision/domain/maitrise.dart';
import 'package:ecoshop_client/features/revision/domain/quiz.dart';
import 'package:ecoshop_client/features/revision/presentation/progression.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

QuestionQuiz q(String id, String competence, {String matiere = 'm1', String? chapitre, String difficulte = 'moyen'}) =>
    QuestionQuiz.depuisJson({
      'id': id,
      'matiere_id': matiere,
      'version': 1,
      'type': 'vrai_faux',
      'difficulte': difficulte,
      'competence_id': competence,
      'chapitre_id': chapitre,
      'enonce': 'Q $id',
      'contenu': const <String, dynamic>{},
      'reponse': {'valeur': true},
      'explication': 'E',
    });

final paquet = PaquetRevision(
  matieres: const [MatiereRevision(id: 'm1', nom: 'Maths'), MatiereRevision(id: 'm2', nom: 'Français')],
  chapitres: const [ChapitreRevision(id: 'ch1', matiereId: 'm1', titre: 'Les fractions')],
  competences: const [
    CompetenceRevision(id: 'frac', matiereId: 'm1', libelle: 'Fractions'),
    CompetenceRevision(id: 'geo', matiereId: 'm1', libelle: 'Géométrie'),
    CompetenceRevision(id: 'conj', matiereId: 'm2', libelle: 'Conjugaison'),
  ],
  questions: [
    for (var i = 0; i < 6; i++) q('f$i', 'frac', chapitre: 'ch1', difficulte: i < 2 ? 'facile' : 'difficile'),
    for (var i = 0; i < 4; i++) q('g$i', 'geo'),
    for (var i = 0; i < 4; i++) q('c$i', 'conj', matiere: 'm2'),
  ],
);

CompetenceMaitrise m(String id, double v, int n, {bool echecs = false}) =>
    CompetenceMaitrise(competenceId: id, maitrise: v, reponses: n, echecsRepetes: echecs);

void main() {
  group('recommandation du jour (14.2)', () {
    Recommandation reco(ProfilMaitrise p, {RevisionsDuJour r = const RevisionsDuJour(), bool petites = false}) =>
        recommandationDuJour(paquet: paquet, profil: p, revisions: r, petitesClasses: petites)!;

    test('oubli : les révisions du jour passent en premier', () {
      final r = reco(const ProfilMaitrise(), r: const RevisionsDuJour(dues: 2, questionIds: ['f1', 'g2']));
      expect(r.type, TypeRecommandation.repetition);
      expect(r.config.questionIds, ['f1', 'g2']);
    });

    test('échecs répétés : retour à la leçon, questions faciles', () {
      final r = reco(ProfilMaitrise({'frac': m('frac', 0.2, 4, echecs: true)}));
      expect(r.type, TypeRecommandation.retourLecon);
      expect(r.raison, contains('« Les fractions »'));
      expect(r.config.difficultes, {Difficulte.facile});
    });

    test('erreur : exercice similaire sur la compétence faible', () {
      final r = reco(ProfilMaitrise({'frac': m('frac', 0.8, 6), 'geo': m('geo', 0.3, 3)}));
      expect(r.type, TypeRecommandation.similaire);
      expect(r.config.competenceId, 'geo');
    });

    test('maîtrise : nouvelle compétence de la matière, sinon plus difficile', () {
      expect(reco(ProfilMaitrise({'frac': m('frac', 0.9, 6)})).config.competenceId, 'geo');
      final defi = reco(ProfilMaitrise({'frac': m('frac', 0.9, 6), 'geo': m('geo', 0.6, 3)}));
      expect(defi.type, TypeRecommandation.plusDifficile);
      expect(defi.config.difficultes, {Difficulte.difficile, Difficulte.expert});
    });

    test('rien encore : un quiz rapide pour faire le point', () {
      expect(reco(const ProfilMaitrise()).type, TypeRecommandation.decouverte);
    });
  });

  group('choix des questions d’une compétence', () {
    test('80 % la compétence, 20 % d’acquis à consolider', () {
      final traces = {
        for (final id in ['g0', 'g1', 'c0']) id: TraceQuestion(vues: 1, dernierScore: 1, derniereFois: DateTime(2026, 10, 1)),
      };
      final l = choisirQuestions(paquet, const ConfigQuiz(mode: ModeQuiz.competence, competenceId: 'frac', nombre: 5),
          traces: traces);
      expect(l.where((x) => x.contenu.competenceId == 'frac').length, 4);
      expect(l.where((x) => x.contenu.competenceId != 'frac').length, 1);
    });

    test('révisions du jour : les questions imposées, dans l’ordre', () {
      final l = choisirQuestions(paquet, const ConfigQuiz(mode: ModeQuiz.repetition, questionIds: ['g3', 'inconnue', 'f0']));
      expect(l.map((x) => x.id), ['g3', 'f0']);
    });

    test('une carte revue aujourd’hui sur cet appareil disparaît de la file', () {
      final maintenant = DateTime(2026, 10, 31, 18);
      final r = const RevisionsDuJour(dues: 3, questionIds: ['f0', 'f1', 'g0'])
          .sansDejaRevues({'f1': TraceQuestion(vues: 2, dernierScore: 1, derniereFois: DateTime(2026, 10, 31, 9))}, maintenant);
      expect(r.questionIds, ['f0', 'g0']);
      expect(r.dues, 2);
    });

    test('plafond plus bas du CP1 au CE2 (15.1)', () {
      expect(plafondRevisions(petitesClasses: true), lessThan(plafondRevisions(petitesClasses: false)));
    });
  });

  group('plan de révision (15.2)', () {
    final plan = PlanRevision(titre: 'BEPC', echeance: DateTime(2026, 12, 30), matieres: const ['m1', 'm2'], questionsParJour: 10);

    test('plus de jours pour la matière à fort coefficient et à points faibles', () {
      final missions = missionsDuPlan(
        plan: plan,
        maintenant: DateTime(2026, 10, 31),
        coefficients: const {'m1': 4, 'm2': 2},
        faiblesParMatiere: const {'m1': 1},
      );
      expect(missions.length, 14);
      final maths = missions.where((x) => x.matiereId == 'm1').length;
      final francais = missions.where((x) => x.matiereId == 'm2').length;
      expect(maths, greaterThan(francais * 2));
      expect(missions.where((x) => x.examenBlanc).length, 2, reason: 'un examen blanc par semaine');
    });

    test('la veille de l’examen : examen blanc ; après l’échéance : rien', () {
      final veille = missionsDuPlan(plan: plan, maintenant: DateTime(2026, 12, 29));
      expect(veille.single.examenBlanc, isTrue);
      expect(missionsDuPlan(plan: plan, maintenant: DateTime(2026, 12, 30)), isEmpty);
    });
  });

  group('vue de la classe', () {
    test('à reprendre : un élève sur trois ou plus sous 50 %', () {
      final v = MaitriseClasse.depuisJson({
        'eleves': 30,
        'eleves_actifs': 12,
        'competences': [
          {'competence_id': 'geo', 'libelle': 'Géométrie', 'eleves': 9, 'sous_seuil': 4, 'maitrise_moyenne': 0.45, 'eleves_sous_seuil': ['Awa BAH']},
          {'competence_id': 'frac', 'libelle': 'Fractions', 'eleves': 9, 'sous_seuil': 1, 'maitrise_moyenne': 0.7},
        ],
      });
      expect(v.aReprendre().map((c) => c.libelle), ['Géométrie']);
    });
  });

  testWidgets('progression : du CP1 au CE2, l’enfant ne voit pas de pourcentage', (tester) async {
    final espace = EspaceRevision(
      niveau: const NiveauRevision(niveauId: 'n', nom: 'CP1', grade: 1),
      paquet: paquet,
      traces: const {},
      resume: const ResumeRevision(),
    );
    Widget ecran(bool chiffres) => MaterialApp(
          home: EcranProfilMaitrise(
            espace: espace,
            profil: ProfilMaitrise({'frac': m('frac', 0.3, 4)}),
            voirChiffres: chiffres,
            titre: 'Ma progression',
            lancer: (_) {},
          ),
        );
    await tester.pumpWidget(ecran(false));
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('À renforcer'), findsOneWidget);
    await tester.pumpWidget(ecran(true));
    expect(find.text('À renforcer · 30 %'), findsOneWidget);
  });

  testWidgets('vue de classe : compétences à reprendre et élèves concernés', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        maitriseClasseProvider('c1').overrideWith((ref) async => MaitriseClasse.depuisJson({
              'eleves': 3,
              'eleves_actifs': 2,
              'competences': [
                {'competence_id': 'geo', 'libelle': 'Géométrie', 'eleves': 2, 'sous_seuil': 1, 'maitrise_moyenne': 0.5, 'eleves_sous_seuil': ['Awa BAH']},
              ],
            })),
      ],
      child: const MaterialApp(home: EcranMaitriseClasse(classeId: 'c1', nom: '7e A')),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('À reprendre en classe : Géométrie'), findsOneWidget);
    await tester.tap(find.text('Géométrie'));
    await tester.pumpAndSettle();
    expect(find.text('Awa BAH'), findsOneWidget);
  });
}
