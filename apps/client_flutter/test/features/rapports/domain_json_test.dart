import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/rapports/domain/anomalie_statistique.dart';
import 'package:ecoshop_client/features/rapports/domain/enums_rapports.dart';
import 'package:ecoshop_client/features/rapports/domain/indicateur_cle.dart';
import 'package:ecoshop_client/features/rapports/domain/rapport.dart';
import 'package:ecoshop_client/features/rapports/domain/recommandation_strategique.dart';

void main() {
  group('Rapport', () {
    test('versJsonEcriture/depuisJsonEcriture font un aller-retour fidèle', () {
      final rapport = Rapport(
        id: 'r1',
        etablissementId: 'et1',
        anneeScolaireId: 'a1',
        classeId: 'c1',
        type: 'bulletin',
        format: TypeExport.excel,
        demandeHorsLigne: true,
      );

      final relu = Rapport.depuisJsonEcriture(rapport.versJsonEcriture());

      expect(relu.type, 'bulletin');
      expect(relu.format, TypeExport.excel);
      expect(relu.demandeHorsLigne, isTrue);
    });

    test('versJsonEcriture n\'expose pas le statut ni le fichier généré', () {
      final rapport = Rapport(
        id: 'r1',
        etablissementId: 'et1',
        anneeScolaireId: 'a1',
        type: 'bulletin',
        statut: StatutRapport.genere,
        fichierUrl: 'https://exemple/fichier.pdf',
      );

      final json = rapport.versJsonEcriture();
      expect(json.containsKey('statut'), isFalse);
      expect(json.containsKey('fichier_url'), isFalse);
    });
  });

  group('IndicateurCle', () {
    test('estUnTaux distingue les indicateurs en proportion des effectifs bruts', () {
      final taux = IndicateurCle.depuisJson({
        'id': 'i1',
        'etablissement_id': 'et1',
        'annee_scolaire_id': 'a1',
        'code': 'taux_reussite',
        'valeur_numeric': 0.72,
        'calcule_le': '2026-03-01T00:00:00Z',
      });
      final effectif = IndicateurCle.depuisJson({
        'id': 'i2',
        'etablissement_id': 'et1',
        'annee_scolaire_id': 'a1',
        'code': 'effectifs',
        'valeur_numeric': 320,
        'calcule_le': '2026-03-01T00:00:00Z',
      });

      expect(taux.estUnTaux, isTrue);
      expect(effectif.estUnTaux, isFalse);
      expect(taux.libelle, 'Taux de réussite');
    });
  });

  group('AnomalieStatistique', () {
    test('depuisJson lit les colonnes réelles', () {
      final anomalie = AnomalieStatistique.depuisJson({
        'id': 'an1',
        'etablissement_id': 'et1',
        'annee_scolaire_id': 'a1',
        'type': 'absence',
        'severite': 'elevee',
        'description': 'Absentéisme individuel excessif.',
        'valeur_observee': 0.42,
        'valeur_attendue': 0.30,
        'statut': 'ouverte',
        'detectee_le': '2026-03-01T00:00:00Z',
      });

      expect(anomalie.severite, 'elevee');
      expect(anomalie.statut, StatutAnomalie.ouverte);
    });
  });

  group('RecommandationStrategique', () {
    test('depuisJson lit les colonnes réelles', () {
      final recommandation = RecommandationStrategique.depuisJson({
        'id': 'rec1',
        'etablissement_id': 'et1',
        'annee_scolaire_id': 'a1',
        'classe_id': 'c1',
        'type': 'tutorat',
        'titre': 'Plan de tutorat',
        'description': 'Score de risque élevé.',
        'priorite': 'haute',
        'statut': 'proposee',
        'cree_le': '2026-03-01T00:00:00Z',
      });

      expect(recommandation.priorite, 'haute');
      expect(recommandation.statut, StatutRecommandation.proposee);
    });
  });
}
