import 'package:ecoshop_client/features/premium_eleve/data/premium_eleve_repository.dart';
import 'package:ecoshop_client/features/premium_eleve/domain/premium_eleve.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final maintenant = DateTime(2026, 10, 30, 10);

  group('Premium élève (REG-36)', () {
    test('lecture de l’état et des tarifs', () {
      final e = PremiumEleveRepository.decoder({
        'abonnement': {'formule': 'mensuel', 'expire_le': '2026-11-03T10:00:00Z'},
        'tarifs': [
          {'cle': 'tarif_abonnement_premium_eleve_mensuel', 'valeur': {'valeur': 10000}},
          {'cle': 'tarif_abonnement_premium_eleve_annuel', 'valeur': {'valeur': 96000}},
          {'cle': 'devise_defaut', 'valeur': {'valeur': 'GNF'}},
          {'cle': 'quota_tuteur_ia_free_mensuel', 'valeur': {'valeur': 20}},
        ],
      });
      expect(e.formule, FormulePremium.mensuel);
      expect(e.actifLe(maintenant), isTrue);
      expect(e.aRappeler(maintenant), isTrue, reason: 'moins de 7 jours restants');
      expect(e.economieAnnuelle(), 20);
      expect(e.quotaGratuit, 20);
    });

    test('jamais abonné, tarifs absents : rien à payer', () {
      final e = PremiumEleveRepository.decoder({'abonnement': null, 'tarifs': const []});
      expect(e.actifLe(maintenant), isFalse);
      expect(e.joursRestants(maintenant), isNull);
      expect(e.tarif(FormulePremium.annuel), isNull);
      expect(e.devise, 'GNF');
    });

    test('prolonger avant la fin garde les jours restants', () {
      final e = EtatPremium(expireLe: DateTime(2026, 11, 10), tarifMensuel: 1, tarifAnnuel: 10);
      expect(e.finSiPaye(FormulePremium.mensuel, maintenant), DateTime(2026, 12, 10));
      expect(e.aRappeler(maintenant), isFalse);
    });

    test('après la fin : la période repart d’aujourd’hui', () {
      final e = EtatPremium(expireLe: DateTime(2026, 9, 1), tarifMensuel: 1, tarifAnnuel: 10);
      expect(e.actifLe(maintenant), isFalse);
      expect(e.finSiPaye(FormulePremium.annuel, maintenant), DateTime(2027, 10, 30, 10));
    });

    test('messages d’erreur', () {
      expect(const ErreurPremium('HORS_LIGNE').message, contains('réseau'));
      expect(const ErreurPremium('PARAMETRES_ABONNEMENT_MANQUANTS').message, contains('prix'));
    });
  });
}
