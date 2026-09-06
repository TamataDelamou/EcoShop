import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/auth/role_racine.dart';

void main() {
  group('RoleRacine', () {
    test('seuls élève et parent sont auto-inscriptibles (ch. 5.2)', () {
      expect(RoleRacine.eleve.estAutoInscriptible, isTrue);
      expect(RoleRacine.parent.estAutoInscriptible, isTrue);
      expect(RoleRacine.enseignant.estAutoInscriptible, isFalse);
      expect(RoleRacine.direction.estAutoInscriptible, isFalse);
    });

    test('admin_gsg et admin_contenu sont des rôles plateforme (ch. 4)', () {
      expect(RoleRacine.adminGsg.estPlateforme, isTrue);
      expect(RoleRacine.adminContenu.estPlateforme, isTrue);
      expect(RoleRacine.eleve.estPlateforme, isFalse);
      expect(RoleRacine.fondateurReseau.estPlateforme, isFalse);
    });

    test('depuisCode résout les codes et renvoie null pour l’inconnu', () {
      expect(RoleRacine.depuisCode('direction'), RoleRacine.direction);
      expect(RoleRacine.depuisCode('vendeur'), RoleRacine.vendeur);
      expect(RoleRacine.depuisCode('inconnu'), isNull);
      expect(RoleRacine.depuisCode(null), isNull);
    });
  });
}
