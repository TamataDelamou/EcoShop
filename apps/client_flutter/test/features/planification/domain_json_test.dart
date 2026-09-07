import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/planification/domain/conflit_emploi.dart';
import 'package:ecoshop_client/features/planification/domain/emploi_du_temps.dart';
import 'package:ecoshop_client/features/planification/domain/enums_planification.dart';
import 'package:ecoshop_client/features/planification/domain/evenement_agenda.dart';
import 'package:ecoshop_client/features/planification/domain/progression_pedagogique.dart';
import 'package:ecoshop_client/features/planification/domain/salle.dart';

void main() {
  group('Salle', () {
    test('libelle combine code et nom quand le nom est renseigné', () {
      const salle = Salle(id: 's1', etablissementId: 'et1', code: 'A101', nom: 'Amphi');
      expect(salle.libelle, 'A101 — Amphi');
    });

    test('libelle retombe sur le code seul quand le nom est vide', () {
      const salle = Salle(id: 's1', etablissementId: 'et1', code: 'A101');
      expect(salle.libelle, 'A101');
    });
  });

  group('EmploiDuTemps', () {
    test('versJsonEcriture/depuisJsonEcriture font un aller-retour fidèle', () {
      final emploi = EmploiDuTemps(
        id: 'e1',
        etablissementId: 'et1',
        anneeScolaireId: 'a1',
        classeId: 'c1',
        enseignantProfileId: 'p1',
        salleId: 's1',
        jourSemaine: 2,
        heureDebut: '08:00',
        heureFin: '09:00',
        type: TypeSeance.examen,
        deviceId: 'dev1',
      );

      final relu = EmploiDuTemps.depuisJsonEcriture(emploi.versJsonEcriture());

      expect(relu.jourSemaine, 2);
      expect(relu.type, TypeSeance.examen);
      expect(relu.heureDebut, '08:00');
    });

    test('versJsonEcriture n\'expose pas les noms d\'affichage', () {
      final emploi = EmploiDuTemps(
        id: 'e1',
        etablissementId: 'et1',
        anneeScolaireId: 'a1',
        classeId: 'c1',
        jourSemaine: 1,
        heureDebut: '08:00',
        heureFin: '09:00',
        nomEnseignant: 'Mme Diallo',
      );

      expect(emploi.versJsonEcriture().containsKey('nom_enseignant'), isFalse);
    });
  });

  group('EvenementAgenda', () {
    test('versJsonEcriture/depuisJsonEcriture font un aller-retour fidèle', () {
      final evenement = EvenementAgenda(
        id: 'ev1',
        etablissementId: 'et1',
        anneeScolaireId: 'a1',
        classeId: 'c1',
        titre: 'Conseil de classe',
        type: TypeEvenementAgenda.conseilClasse,
        dateDebut: DateTime(2026, 3, 10),
        dateFin: DateTime(2026, 3, 10),
        heureDebut: '17:00',
        rappel: true,
      );

      final relu = EvenementAgenda.depuisJsonEcriture(evenement.versJsonEcriture());

      expect(relu.type, TypeEvenementAgenda.conseilClasse);
      expect(relu.rappel, isTrue);
      expect(relu.heureDebut, '17:00');
    });
  });

  group('ProgressionPedagogique', () {
    test('versJsonEcriture/depuisJsonEcriture font un aller-retour fidèle', () {
      final progression = ProgressionPedagogique(
        id: 'pr1',
        etablissementId: 'et1',
        anneeScolaireId: 'a1',
        classeId: 'c1',
        enseignantProfileId: 'p1',
        seance: 'Séance de rattrapage',
        statut: StatutProgression.proposee,
        datePrevue: DateTime(2026, 3, 15),
      );

      final relue = ProgressionPedagogique.depuisJsonEcriture(progression.versJsonEcriture());

      expect(relue.statut, StatutProgression.proposee);
      expect(relue.seance, 'Séance de rattrapage');
    });
  });

  group('ConflitEmploi', () {
    test('depuisJson lit les colonnes de detecter_conflits_emploi et tronque les heures', () {
      final conflit = ConflitEmploi.depuisJson({
        'type': 'salle',
        'a': 'e1',
        'b': 'e2',
        'jour_semaine': 3,
        'heure_debut': '08:00:00',
        'heure_fin': '09:00:00',
      });

      expect(conflit.type, 'salle');
      expect(conflit.heureDebut, '08:00');
      expect(conflit.heureFin, '09:00');
    });
  });
}
