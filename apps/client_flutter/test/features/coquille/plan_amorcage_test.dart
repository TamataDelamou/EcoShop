import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/offline/amorcage.dart';
import 'package:ecoshop_client/features/coquille/application/plan_amorcage.dart';

/// REG-35 lot 2 — ce que chaque rôle lit d'avance.
void main() {
  late List<String> lues;

  SourcesAmorcage sources({int classes = 3}) {
    Future<Object?> noter(String quoi) async {
      lues.add(quoi);
      return null;
    }

    return SourcesAmorcage(
      structure: (e) async {
        lues.add('structure:$e');
        return (anneeId: 'a2026', classes: [for (var i = 1; i <= classes; i++) (id: 'c$i', nom: 'Classe $i')]);
      },
      inscriptionsDeClasse: (c) => noter('eleves:$c'),
      affectationsDeClasse: (c) => noter('enseignants:$c'),
      emploisDeClasse: (c) => noter('edt:$c'),
      evaluationsDeClasse: (c) => noter('evaluations:$c'),
      mesAffectations: (e) async => ['c2'],
      emploisDeEnseignant: (p, e, a) => noter('edt_enseignant:$p'),
      mesEnfants: (e) async => ['f1', 'f2'],
      maFiche: () async => 'f9',
      classeActuelleDeFiche: (f) async => 'classe_de_$f',
      notesDeFiche: (f) => noter('notes:$f'),
      bulletinsDeFiche: (f) => noter('bulletins:$f'),
      presencesDeFiche: (f) => noter('absences:$f'),
      retardsDeFiche: (f) => noter('retards:$f'),
      sanctionsDeFiche: (f) => noter('sanctions:$f'),
      cahierDeFiche: (f) => noter('cahier:$f'),
      annonces: () => noter('annonces'),
      personnel: (e) => noter('personnel:$e'),
      encaissementsRecents: (e) => noter('encaissements:$e'),
      fraisScolarite: (e, a) => noter('tarifs:$a'),
      agendaEtablissement: (e, a) => noter('agenda:$a'),
    );
  }

  Future<EtatAmorcage> amorcer(RoleRacine role, {int classes = 3}) => executerAmorcage(planAmorcage(
        role: role,
        etablissementId: 'ecole',
        profileId: 'moi',
        sources: sources(classes: classes),
      ));

  setUp(() => lues = []);

  test('Direction : chaque classe (élèves, emploi du temps, évaluations, enseignants), personnel, tarifs', () async {
    final fin = await amorcer(RoleRacine.direction);
    expect(fin.issue, IssueAmorcage.termine);
    for (final c in ['c1', 'c2', 'c3']) {
      expect(lues, containsAll(['eleves:$c', 'edt:$c', 'evaluations:$c', 'enseignants:$c']));
    }
    expect(lues, containsAll(['annonces', 'personnel:ecole', 'encaissements:ecole', 'tarifs:a2026', 'agenda:a2026']));
    expect(lues.where((l) => l.startsWith('notes:')), isEmpty, reason: 'pas de lecture élève par élève');
  });

  test('école de 2 000 élèves (50 classes) : environ 200 lectures, jamais par élève', () async {
    final fin = await amorcer(RoleRacine.direction, classes: 50);
    expect(fin.faites, lessThan(220));
    expect(fin.faites, greaterThan(200));
  });

  test('Enseignant : seulement ses classes et son emploi du temps', () async {
    await amorcer(RoleRacine.enseignant);
    expect(lues, containsAll(['eleves:c2', 'edt:c2', 'evaluations:c2', 'edt_enseignant:moi']));
    expect(lues, isNot(contains('eleves:c1')));
    expect(lues, isNot(contains('enseignants:c2')));
    expect(lues, isNot(contains('personnel:ecole')));
  });

  test('Parent : les données de chacun de ses enfants dans cette école', () async {
    await amorcer(RoleRacine.parent);
    for (final f in ['f1', 'f2']) {
      expect(lues, containsAll(['notes:$f', 'bulletins:$f', 'absences:$f', 'retards:$f', 'sanctions:$f', 'cahier:$f']));
      expect(lues, contains('edt:classe_de_$f'));
    }
    expect(lues, isNot(contains('structure:ecole')));
  });

  test('Élève : sa fiche et l\'emploi du temps de sa classe', () async {
    await amorcer(RoleRacine.eleve);
    expect(lues, containsAll(['notes:f9', 'absences:f9', 'edt:classe_de_f9', 'annonces']));
  });

  test('Vendeur : seulement les annonces', () async {
    await amorcer(RoleRacine.vendeur);
    expect(lues, ['annonces']);
  });
}
