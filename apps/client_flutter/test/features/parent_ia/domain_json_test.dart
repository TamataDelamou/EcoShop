import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/parent_ia/domain/parent_ia_config.dart';
import 'package:ecoshop_client/features/parent_ia/domain/restriction_parent_ia.dart';

void main() {
  group('ParentIaConfig', () {
    test('inactif() est le repli par défaut', () {
      final config = ParentIaConfig.inactif();
      expect(config.actif, isFalse);
      expect(config.estVerrouille, isFalse);
      expect(config.joursRestantsAvantDeverrouillage, 0);
    });

    test('depuisJson lit les colonnes réelles de parent_ia_config', () {
      final verrou = DateTime.now().add(const Duration(days: 10));
      final config = ParentIaConfig.depuisJson({
        'actif': true,
        'date_activation': DateTime.now().toIso8601String(),
        'verrouille_jusquau': verrou.toIso8601String(),
        'consentement_eleve': true,
      });

      expect(config.actif, isTrue);
      expect(config.consentementEleve, isTrue);
      expect(config.estVerrouille, isTrue);
      expect(config.joursRestantsAvantDeverrouillage, greaterThan(0));
    });

    test('estVerrouille est faux une fois le verrou expiré, même si actif', () {
      final config = ParentIaConfig.depuisJson({
        'actif': true,
        'verrouille_jusquau': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
        'consentement_eleve': true,
      });

      expect(config.estVerrouille, isFalse);
      expect(config.joursRestantsAvantDeverrouillage, 0);
    });
  });

  group('RestrictionParentIa', () {
    test('depuisJson lit les colonnes réelles de parent_ia_historique', () {
      final restriction = RestrictionParentIa.depuisJson({
        'id': 'r1',
        'app_concernee': 'TikTok',
        'temps_usage_minutes': 180,
        'niveau_risque_echec': 80,
        'matiere_a_risque': 'Mathématiques',
        'source_donnee': 'declaration_manuelle',
        'created_at': '2026-03-01T00:00:00Z',
      });

      expect(restriction.appConcernee, 'TikTok');
      expect(restriction.tempsUsageMinutes, 180);
      expect(restriction.niveauRisqueEchec, 80);
      expect(restriction.matiereARisque, 'Mathématiques');
      expect(restriction.sourceDonnee, 'declaration_manuelle');
    });

    test('depuisJson accepte matiere_a_risque absente', () {
      final restriction = RestrictionParentIa.depuisJson({
        'id': 'r2',
        'app_concernee': 'YouTube',
        'temps_usage_minutes': 90,
        'niveau_risque_echec': 30,
        'matiere_a_risque': null,
        'source_donnee': 'declaration_manuelle',
        'created_at': '2026-03-01T00:00:00Z',
      });

      expect(restriction.matiereARisque, isNull);
    });
  });
}
