import 'package:ecoshop_client/features/planification/domain/moteur_emploi_du_temps.dart';
import 'package:flutter_test/flutter_test.dart';

const _grille = [
  CreneauEmploi(debut: '08:00', fin: '09:00'),
  CreneauEmploi(debut: '09:00', fin: '10:00'),
  CreneauEmploi(debut: '10:00', fin: '10:15', cours: false, libelle: 'Récréation'),
  CreneauEmploi(debut: '10:15', fin: '11:15'),
  CreneauEmploi(debut: '11:15', fin: '12:15'),
  CreneauEmploi(debut: '12:15', fin: '14:00', cours: false, libelle: 'Midi'),
  CreneauEmploi(debut: '14:00', fin: '15:00'),
  CreneauEmploi(debut: '15:00', fin: '16:00'),
];

CoursAPlacer _cours(String id, String classe, String prof, int heures,
        {int duree = 60, String? groupe, int coef = 1, String? salle}) =>
    CoursAPlacer(
      id: id,
      classeId: classe,
      nomClasse: classe,
      groupeId: groupe,
      nomGroupe: groupe,
      enseignantId: prof,
      nomEnseignant: prof,
      matiereId: id,
      nomMatiere: id,
      salleId: salle,
      minutesParSemaine: heures * 60,
      dureeSeance: duree,
      coefficient: coef.toDouble(),
    );

bool _chevauche(SeancePlacee a, SeancePlacee b) =>
    a.jour == b.jour && minutesDe(a.debut) < minutesDe(b.fin) && minutesDe(b.debut) < minutesDe(a.fin);

void _verifierAucunConflit(ResultatEmploi r) {
  for (var i = 0; i < r.seances.length; i++) {
    for (var j = i + 1; j < r.seances.length; j++) {
      final a = r.seances[i];
      final b = r.seances[j];
      if (!_chevauche(a, b)) continue;
      expect(a.cours.enseignantId == b.cours.enseignantId, isFalse, reason: 'enseignant à deux endroits : ${a.cours.libelle} / ${b.cours.libelle}');
      if (a.cours.classeId == b.cours.classeId) {
        final parallele = a.cours.groupeId != null && b.cours.groupeId != null && a.cours.groupeId != b.cours.groupeId;
        expect(parallele, isTrue, reason: 'classe à deux endroits : ${a.cours.libelle} / ${b.cours.libelle}');
      }
      if (a.cours.salleId != null) expect(a.cours.salleId == b.cours.salleId, isFalse, reason: 'salle occupée deux fois');
    }
  }
}

void main() {
  group('Moteur d’emploi du temps (REG-24)', () {
    test('place toutes les séances sans conflit', () {
      final donnees = DonneesEmploi(
        jours: const [1, 2, 3, 4, 5],
        creneaux: _grille,
        budget: const Duration(milliseconds: 1500),
        cours: [
          _cours('Maths 6A', '6A', 'Diallo', 5, coef: 4),
          _cours('Français 6A', '6A', 'Camara', 5, coef: 4),
          _cours('Anglais 6A', '6A', 'Bah', 3),
          _cours('SVT 6A', '6A', 'Sow', 2, duree: 120, salle: 'LABO'),
          _cours('Maths 6B', '6B', 'Diallo', 5, coef: 4),
          _cours('Français 6B', '6B', 'Camara', 5, coef: 4),
          _cours('Anglais 6B', '6B', 'Bah', 3),
          _cours('SVT 6B', '6B', 'Sow', 2, duree: 120, salle: 'LABO'),
        ],
      );
      expect(MoteurEmploiDuTemps.diagnostiquer(donnees), isEmpty);
      final r = MoteurEmploiDuTemps(donnees).resoudre(departs: 2);
      expect(r.nonPlacees, isEmpty);
      expect(r.seances.length, r.bilan.seancesTotal);
      _verifierAucunConflit(r);
      // Une séance de 2 h ne coupe jamais une pause.
      for (final s in r.seances.where((s) => s.cours.dureeSeance == 120)) {
        expect(minutesDe(s.fin) - minutesDe(s.debut), 120, reason: s.debut);
      }
    });

    test('respecte les indisponibilités, les demi-journées libres et les séances verrouillées', () {
      final donnees = DonneesEmploi(
        jours: const [1, 2, 3, 4, 5],
        creneaux: _grille,
        demiJourneesLibres: const {3: 'apres_midi'},
        budget: const Duration(milliseconds: 1000),
        indisponibilites: const [IndisponibiliteEmploi(enseignantId: 'Diallo', jour: 1)],
        seancesFixes: const [
          SeanceFixeEmploi(classeId: '6A', enseignantId: 'Camara', jour: 2, debut: '08:00', fin: '09:00'),
        ],
        cours: [
          _cours('Maths 6A', '6A', 'Diallo', 4),
          _cours('Français 6A', '6A', 'Camara', 4),
        ],
      );
      final r = MoteurEmploiDuTemps(donnees).resoudre(departs: 1);
      expect(r.nonPlacees, isEmpty);
      for (final s in r.seances) {
        if (s.cours.enseignantId == 'Diallo') expect(s.jour, isNot(1), reason: 'Diallo indisponible le lundi');
        if (s.jour == 3) expect(minutesDe(s.debut) < 12 * 60 + 30, isTrue, reason: 'mercredi après-midi libre');
        expect(s.jour == 2 && s.debut == '08:00', isFalse, reason: 'créneau verrouillé');
      }
    });

    // REG-41 : une séance de semaine A et une séance de semaine B partagent
    // le même créneau (classe, enseignant et salle).
    test('semaines A et B : deux cours une semaine sur deux occupent le même créneau', () {
      // Un seul créneau dans la semaine : les deux cours (même classe, même
      // enseignant, même salle) ne passent que superposés, l'un en semaine A,
      // l'autre en semaine B.
      final donnees = DonneesEmploi(
        jours: const [1],
        creneaux: const [CreneauEmploi(debut: '08:00', fin: '09:00')],
        budget: const Duration(milliseconds: 500),
        cours: const [
          CoursAPlacer(id: 'TP A', classeId: '6A', nomClasse: '6A', enseignantId: 'Sow', matiereId: 'TP A',
              nomMatiere: 'TP A', salleId: 'LABO', minutesParSemaine: 60, semaine: 'A'),
          CoursAPlacer(id: 'TP B', classeId: '6A', nomClasse: '6A', enseignantId: 'Sow', matiereId: 'TP B',
              nomMatiere: 'TP B', salleId: 'LABO', minutesParSemaine: 60, semaine: 'B'),
        ],
      );
      final r = MoteurEmploiDuTemps(donnees).resoudre(departs: 1);
      expect(r.nonPlacees, isEmpty);
      final a = r.seances.firstWhere((s) => s.cours.id == 'TP A');
      expect(a.versJsonServeur()['semaine'], 'A');

      // Sans alternance, le second cours ne trouve pas de place.
      final sansAlternance = DonneesEmploi(
        jours: const [1],
        creneaux: const [CreneauEmploi(debut: '08:00', fin: '09:00')],
        budget: const Duration(milliseconds: 500),
        cours: const [
          CoursAPlacer(id: 'TP 1', classeId: '6A', nomClasse: '6A', enseignantId: 'Sow', minutesParSemaine: 60),
          CoursAPlacer(id: 'TP 2', classeId: '6A', nomClasse: '6A', enseignantId: 'Sow', minutesParSemaine: 60),
        ],
      );
      expect(MoteurEmploiDuTemps(sansAlternance).resoudre(departs: 1).nonPlacees, hasLength(1));
    });

    test('deux groupes d’une même classe peuvent avoir cours en même temps', () {
      // 18 h de grille (3 jours x 6 h) : 6 h de tronc commun + 2 x 10 h de
      // langues ne passent que si les deux groupes sont en parallèle.
      final donnees = DonneesEmploi(
        jours: const [1, 2, 3],
        creneaux: _grille,
        budget: const Duration(milliseconds: 1500),
        cours: [
          _cours('Maths', '6A', 'Diallo', 6),
          _cours('Anglais', '6A', 'Bah', 10, groupe: 'G1'),
          _cours('Arabe', '6A', 'Kaba', 10, groupe: 'G2'),
        ],
      );
      final r = MoteurEmploiDuTemps(donnees).resoudre(departs: 2);
      expect(r.nonPlacees, isEmpty);
      _verifierAucunConflit(r);
    });

    test('signale une classe qui a plus d’heures que la grille', () {
      final donnees = DonneesEmploi(
        jours: const [1],
        creneaux: _grille,
        cours: [_cours('Maths', '6A', 'Diallo', 8)],
      );
      expect(MoteurEmploiDuTemps.diagnostiquer(donnees), isNotEmpty);
      final r = MoteurEmploiDuTemps(DonneesEmploi(
        jours: const [1],
        creneaux: _grille,
        budget: const Duration(milliseconds: 300),
        cours: [_cours('Maths', '6A', 'Diallo', 8)],
      )).resoudre(departs: 1);
      expect(r.nonPlacees, isNotEmpty);
      expect(r.nonPlacees.first.raison, isNotEmpty);
    });

    test('découpe le volume en séances', () {
      expect(_cours('X', 'c', 'p', 3, duree: 120).seances(), [120, 60]);
      expect(_cours('X', 'c', 'p', 4, duree: 120).seances(), [120, 120]);
      expect(_cours('X', 'c', 'p', 2).seances(), [60, 60]);
    });
  });
}
