import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/rh_personnel/domain/absence_personnel.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/conge.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/contrat.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/effectif_categorie.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/employe.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/enums_rh.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/recommandation_formation.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/remplacement_suggere.dart';

void main() {
  group('Employe', () {
    test('versJsonCache/depuisJsonCache font un aller-retour fidèle', () {
      final employe = Employe(
        id: 'e1',
        etablissementId: 'et1',
        profileId: 'p1',
        matricule: 'MAT-001',
        categorie: CategorieEmploye.enseignant,
        dateEmbauche: DateTime(2020, 9, 1),
        statut: StatutEmploye.actif,
        nomAffiche: 'Aïcha Diallo',
      );

      final relu = Employe.depuisJsonCache(employe.versJsonCache());

      expect(relu.matricule, 'MAT-001');
      expect(relu.categorie, CategorieEmploye.enseignant);
      expect(relu.nomAffiche, 'Aïcha Diallo');
    });

    test('versJsonEcriture n\'expose pas le nom affiché', () {
      final employe = Employe(
        id: 'e1',
        etablissementId: 'et1',
        profileId: 'p1',
        matricule: 'MAT-001',
        dateEmbauche: DateTime(2020, 9, 1),
        nomAffiche: 'Aïcha Diallo',
      );

      expect(employe.versJsonEcriture().containsKey('nom_affiche'), isFalse);
    });
  });

  group('Contrat', () {
    test('estEnCours est faux pour un contrat expiré', () {
      final contrat = Contrat(
        id: 'c1',
        etablissementId: 'et1',
        employeId: 'e1',
        type: TypeContrat.cdd,
        dateDebut: DateTime(2020, 1, 1),
        dateFin: DateTime(2020, 12, 31),
        salaireBase: 500000,
      );

      expect(contrat.estEnCours, isFalse);
    });

    test('estEnCours est vrai pour un CDI sans date de fin', () {
      final contrat = Contrat(
        id: 'c1',
        etablissementId: 'et1',
        employeId: 'e1',
        type: TypeContrat.cdi,
        dateDebut: DateTime(2020, 1, 1),
        salaireBase: 500000,
      );

      expect(contrat.estEnCours, isTrue);
    });

    test('versJsonEcriture omet l\'identifiant (généré côté serveur)', () {
      final contrat = Contrat(
        id: 'c1',
        etablissementId: 'et1',
        employeId: 'e1',
        dateDebut: DateTime(2020, 1, 1),
        salaireBase: 500000,
      );

      expect(contrat.versJsonEcriture().containsKey('id'), isFalse);
    });
  });

  group('Conge', () {
    test('versJsonEcriture/depuisJsonEcriture font un aller-retour fidèle', () {
      final conge = Conge(
        id: 'g1',
        etablissementId: 'et1',
        employeId: 'e1',
        type: TypeConge.maladie,
        dateDebut: DateTime(2026, 3, 1),
        dateFin: DateTime(2026, 3, 5),
        nbJours: 5,
        motif: 'Grippe',
      );

      final relu = Conge.depuisJsonEcriture(conge.versJsonEcriture());

      expect(relu.type, TypeConge.maladie);
      expect(relu.nbJours, 5);
      expect(relu.statut, StatutConge.demande);
    });

    test('versJsonEcriture n\'expose pas les champs de validation', () {
      final conge = Conge(
        id: 'g1',
        etablissementId: 'et1',
        employeId: 'e1',
        dateDebut: DateTime(2026, 3, 1),
        dateFin: DateTime(2026, 3, 5),
        nbJours: 5,
        validePar: 'rh1',
      );

      expect(conge.versJsonEcriture().containsKey('valide_par'), isFalse);
    });
  });

  group('AbsencePersonnel', () {
    test('versJsonEcriture/depuisJsonEcriture font un aller-retour fidèle', () {
      final absence = AbsencePersonnel(
        id: 'a1',
        etablissementId: 'et1',
        employeId: 'e1',
        dateAbsence: DateTime(2026, 3, 1),
        type: TypeAbsencePersonnel.maladie,
        justifie: true,
        motif: 'Certificat médical',
      );

      final relue = AbsencePersonnel.depuisJsonEcriture(absence.versJsonEcriture());

      expect(relue.type, TypeAbsencePersonnel.maladie);
      expect(relue.justifie, isTrue);
    });
  });

  group('EffectifCategorie', () {
    test('depuisJson lit les colonnes de analyser_effectifs', () {
      final effectif = EffectifCategorie.depuisJson({
        'categorie': 'enseignant',
        'effectif': 12,
        'anciennete_moyenne_jours': 730.5,
        'masse_salariale_base': 6000000,
      });

      expect(effectif.categorie, 'enseignant');
      expect(effectif.effectif, 12);
      expect(effectif.ancienneteMoyenneJours, 730.5);
    });
  });

  group('RemplacementSuggere', () {
    test('depuisJson lit les colonnes de optimiser_remplacements', () {
      final remplacement = RemplacementSuggere.depuisJson({
        'employe_absent_id': 'e1',
        'absent_matricule': 'MAT-001',
        'remplacant_id': 'e2',
        'remplacant_matricule': 'MAT-002',
      });

      expect(remplacement.absentMatricule, 'MAT-001');
      expect(remplacement.remplacantMatricule, 'MAT-002');
    });
  });

  group('RecommandationFormation', () {
    test('depuisJson lit les colonnes de recommander_formation', () {
      final recommandation = RecommandationFormation.depuisJson({
        'programme_matiere_id': 'm1',
        'code': 'MATH-6E',
        'libelle': 'Mathématiques 6e',
        'raison': 'Matière non couverte',
      });

      expect(recommandation.code, 'MATH-6E');
      expect(recommandation.libelle, 'Mathématiques 6e');
    });
  });
}
