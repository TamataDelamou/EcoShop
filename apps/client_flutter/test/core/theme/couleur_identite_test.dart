import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/ambiance_visuelle.dart';
import 'package:ecoshop_client/core/theme/app_palettes.dart';
import 'package:ecoshop_client/core/theme/app_theme.dart';
import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/core/theme/couleur_identite.dart';

/// REG-07 B/C : couleur d'identité d'établissement et ambiances.
void main() {
  const fondClair = Color(0xFFF8FAFC);
  const fondSombre = Color(0xFF0F172A);
  const surfaceSombre = Color(0xFF1E293B);

  group('CouleurIdentite — ajustement de lisibilité', () {
    test('une couleur déjà lisible est conservée telle quelle', () {
      const bleu = Color(0xFF1E3A8A);
      expect(CouleurIdentite.pourModeClair(bleu, fondClair), bleu);
    });

    test('un jaune vif est foncé en mode clair jusqu\'à rester lisible (texte blanc dessus)', () {
      const jaune = Color(0xFFFFE600);
      final ajustee = CouleurIdentite.pourModeClair(jaune, fondClair);
      expect(ajustee, isNot(jaune));
      expect(CouleurIdentite.contraste(Colors.white, ajustee), greaterThanOrEqualTo(4.5));
      expect(CouleurIdentite.contraste(ajustee, fondClair), greaterThanOrEqualTo(4.5));
      // Même teinte : seule la luminosité change.
      expect(HSLColor.fromColor(ajustee).hue, closeTo(HSLColor.fromColor(jaune).hue, 1));
    });

    test('un bleu nuit est éclairci en mode sombre jusqu\'à rester lisible', () {
      const nuit = Color(0xFF0A1A3F);
      final ajustee = CouleurIdentite.pourModeSombre(nuit, fondSombre, surfaceSombre);
      expect(CouleurIdentite.contraste(fondSombre, ajustee), greaterThanOrEqualTo(4.5));
      expect(CouleurIdentite.contraste(ajustee, surfaceSombre), greaterThanOrEqualTo(4.5));
    });

    test('tout le nuancier proposé devient lisible dans les deux modes', () {
      for (final valeur in [0xFFFFFFFF, 0xFF000000, 0xFF00FF00, 0xFFFF00FF, 0xFF808080, 0xFF00FFFF]) {
        final c = Color(valeur);
        final clair = CouleurIdentite.pourModeClair(c, fondClair);
        final sombre = CouleurIdentite.pourModeSombre(c, fondSombre, surfaceSombre);
        expect(CouleurIdentite.contraste(Colors.white, clair), greaterThanOrEqualTo(4.5), reason: '$c clair');
        expect(CouleurIdentite.contraste(fondSombre, sombre), greaterThanOrEqualTo(4.5), reason: '$c sombre');
      }
    });

    test('hexadécimal : lecture, écriture, refus des formats invalides', () {
      expect(CouleurIdentite.depuisHex('#1a7f5a'), const Color(0xFF1A7F5A));
      expect(CouleurIdentite.depuisHex('1A7F5A'), const Color(0xFF1A7F5A));
      expect(CouleurIdentite.versHex(const Color(0xFF1A7F5A)), '#1A7F5A');
      expect(CouleurIdentite.depuisHex('vert'), isNull);
      expect(CouleurIdentite.depuisHex('#12345'), isNull);
      expect(CouleurIdentite.depuisHex(null), isNull);
    });
  });

  group('AppPalettes.resoudre — ordre de priorité', () {
    const couleur = Color(0xFFC2410C);

    test('sans réglage : charte du pays', () {
      expect(AppPalettes.resoudre(AppThemeVariant.lusophone, Brightness.light), AppPalettes.lusophoneLight);
    });

    test("couleur d'établissement : seule la couleur principale change", () {
      final p = AppPalettes.resoudre(AppThemeVariant.francophoneCfa, Brightness.light, couleurEtablissement: couleur);
      expect(p.primaire, CouleurIdentite.pourModeClair(couleur, AppPalettes.francophoneCfaLight.fond));
      expect(p.fond, AppPalettes.francophoneCfaLight.fond);
      expect(p.encre, AppPalettes.francophoneCfaLight.encre);
    });

    test("l'ambiance personnelle l'emporte sur la charte et la couleur d'établissement", () {
      final p = AppPalettes.resoudre(
        AppThemeVariant.francophoneCfa,
        Brightness.dark,
        ambiance: AmbianceVisuelle.savane,
        couleurEtablissement: couleur,
      );
      expect(p, AppPalettes.savaneDark);
    });

    test("le contraste élevé l'emporte sur tout", () {
      final p = AppPalettes.resoudre(
        AppThemeVariant.francophoneCfa,
        Brightness.light,
        contrasteEleve: true,
        ambiance: AmbianceVisuelle.ocean,
        couleurEtablissement: couleur,
      );
      expect(p, AppPalettes.hauteVisibiliteLight);
    });

    test('construireThemeData applique la couleur ajustée au bouton principal', () {
      final theme = construireThemeData(
        AppThemeVariant.francophoneCfa,
        Brightness.dark,
        couleurEtablissement: const Color(0xFF0A1A3F),
      );
      expect(theme.colorScheme.primary,
          CouleurIdentite.pourModeSombre(const Color(0xFF0A1A3F), AppPalettes.francophoneCfaDark.fond,
              AppPalettes.francophoneCfaDark.surface));
    });
  });

  test('AmbianceVisuelle.depuisCode : repli sur la charte de l\'établissement', () {
    expect(AmbianceVisuelle.depuisCode('savane'), AmbianceVisuelle.savane);
    expect(AmbianceVisuelle.depuisCode(null), AmbianceVisuelle.etablissement);
    expect(AmbianceVisuelle.depuisCode('inconnue'), AmbianceVisuelle.etablissement);
  });
}
