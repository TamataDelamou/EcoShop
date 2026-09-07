import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/scolarite/domain/affectation_enseignant.dart';
import 'package:ecoshop_client/features/scolarite/domain/annee_scolaire.dart';
import 'package:ecoshop_client/features/scolarite/domain/classe.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/inscription.dart';
import 'package:ecoshop_client/features/scolarite/domain/structure_etablissement.dart';

void main() {
  group('FicheEleve', () {
    test('depuisJson/versJson font un aller-retour fidèle', () {
      final fiche = FicheEleve(
        id: 'f1',
        etablissementId: 'e1',
        matricule: 'MAT-1',
        nom: 'Camara',
        prenom: 'Mariam',
        dateNaissance: DateTime(2014, 6, 12),
        sexe: 'F',
        estSupervise: true,
      );

      final relue = FicheEleve.depuisJson(fiche.versJson());

      expect(relue.nomComplet, 'Mariam Camara');
      expect(relue.estSupervise, isTrue);
      expect(relue.dateNaissance, DateTime(2014, 6, 12));
    });
  });

  group('Inscription', () {
    test('versJsonCache/depuisJson conservent fiche et classe embarquées', () {
      final classe = const Classe(
        id: 'c1',
        etablissementId: 'e1',
        anneeScolaireId: 'a1',
        code: '6EA',
        nom: '6e A',
      );
      final fiche = FicheEleve(
        id: 'f1',
        etablissementId: 'e1',
        matricule: 'MAT-1',
        nom: 'Bah',
        prenom: 'Sekou',
        dateNaissance: DateTime(2013, 1, 1),
      );
      final inscription = Inscription(
        id: 'i1',
        etablissementId: 'e1',
        ficheEleveId: fiche.id,
        classeId: classe.id,
        anneeScolaireId: 'a1',
        dateInscription: DateTime(2026, 9, 1),
        fiche: fiche,
        classe: classe,
      );

      final relue = Inscription.depuisJson(inscription.versJsonCache());

      expect(relue.fiche?.nomComplet, 'Sekou Bah');
      expect(relue.classe?.nom, '6e A');
    });
  });

  group('AffectationEnseignant', () {
    test('versJsonCache/depuisJsonCache conservent noms et classe', () {
      const affectation = AffectationEnseignant(
        id: 'aff1',
        etablissementId: 'e1',
        anneeScolaireId: 'a1',
        enseignantProfileId: 'p1',
        classeId: 'c1',
        nomEnseignant: 'Fatou Sow',
        nomMatiere: 'Mathématiques',
        classe: Classe(
          id: 'c1',
          etablissementId: 'e1',
          anneeScolaireId: 'a1',
          code: '6EA',
          nom: '6e A',
        ),
      );

      final relue = AffectationEnseignant.depuisJsonCache(affectation.versJsonCache());

      expect(relue.nomEnseignant, 'Fatou Sow');
      expect(relue.nomMatiere, 'Mathématiques');
      expect(relue.classe?.nom, '6e A');
    });
  });

  group('StructureEtablissement', () {
    test('anneeCourante retombe sur la première année si aucune n\'est marquée courante', () {
      final structure = StructureEtablissement(
        unites: const [],
        anneesScolaires: [
          AnneeScolaire(
            id: 'a1',
            etablissementId: 'e1',
            libelle: '2025-2026',
            dateDebut: DateTime(2025, 9, 1),
            dateFin: DateTime(2026, 7, 1),
          ),
          AnneeScolaire(
            id: 'a2',
            etablissementId: 'e1',
            libelle: '2026-2027',
            dateDebut: DateTime(2026, 9, 1),
            dateFin: DateTime(2027, 7, 1),
          ),
        ],
        classes: const [],
        periodes: const [],
      );

      expect(structure.anneeCourante?.id, 'a1');
    });

    test('anneeCourante retient l\'année marquée courante même si elle n\'est pas la première', () {
      final structure = StructureEtablissement(
        unites: const [],
        anneesScolaires: [
          AnneeScolaire(
            id: 'a1',
            etablissementId: 'e1',
            libelle: '2025-2026',
            dateDebut: DateTime(2025, 9, 1),
            dateFin: DateTime(2026, 7, 1),
          ),
          AnneeScolaire(
            id: 'a2',
            etablissementId: 'e1',
            libelle: '2026-2027',
            dateDebut: DateTime(2026, 9, 1),
            dateFin: DateTime(2027, 7, 1),
            courante: true,
          ),
        ],
        classes: const [],
        periodes: const [],
      );

      expect(structure.anneeCourante?.id, 'a2');
    });
  });
}
