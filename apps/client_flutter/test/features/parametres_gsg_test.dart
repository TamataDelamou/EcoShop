import 'package:ecoshop_client/features/parametres_gsg/domain/parametre_global.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Paramètres globaux GSG (REG-36)', () {
    ParametreGlobal p(Map<String, dynamic> v, [String cle = 'tarif_abonnement_premium_eleve_mensuel']) =>
        ParametreGlobal(cle: cle, valeur: v);

    test('valeur simple : un nombre reste un nombre', () {
      final tarif = p({'valeur': 5000});
      expect(tarif.estSimple, isTrue);
      expect(tarif.libelle, 'Premium élève — prix par mois');
      expect(tarif.apercu, '5 000');
      expect(tarif.valeurDepuisSaisie('7 500'), {'valeur': 7500});
      expect(tarif.valeurDepuisSaisie('sept mille'), isNull);
    });

    test('oui/non et texte', () {
      expect(p({'valeur': true}, 'controle_sessions').valeurDepuisSaisie(false), {'valeur': false});
      expect(p({'valeur': true}, 'controle_sessions').valeurDepuisSaisie('non'), isNull);
      expect(p({'valeur': 'GNF'}, 'devise_defaut').valeurDepuisSaisie(' XOF '), {'valeur': 'XOF'});
      expect(p({'valeur': 'GNF'}, 'devise_defaut').valeurDepuisSaisie('  '), isNull);
    });

    test('valeur composée : réglée en JSON', () {
      final bareme = p({'paliers': [1, 2]}, 'bareme_licence_pro');
      expect(bareme.estSimple, isFalse);
      expect(ParametreGlobal.objetDepuisJson('{"paliers": [3]}'), {'paliers': [3]});
      expect(ParametreGlobal.objetDepuisJson('[1, 2]'), isNull);
      expect(ParametreGlobal.objetDepuisJson('pas du json'), isNull);
    });

    test('clé inconnue : nom lisible', () {
      expect(p({'valeur': 1}, 'nouveau_seuil_test').libelle, 'Nouveau seuil test');
    });

    test('messages d’erreur', () {
      expect(const ErreurParametre('TYPE_INVALIDE').message, contains('type'));
      expect(const ErreurParametre('HORS_LIGNE').message, contains('en ligne'));
    });
  });
}
