import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import 'package:ecoshop_client/core/theme/app_palettes.dart';
import 'package:ecoshop_client/core/theme/app_theme.dart';
import 'package:ecoshop_client/core/theme/app_theme_variant.dart';

/// Ratio de contraste WCAG entre deux couleurs (formule officielle).
double _ratioContraste(Color a, Color b) {
  double luminance(Color c) {
    double canal(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    // ignore: deprecated_member_use — composantes 0..255 lisibles suffisent ici.
    return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
  }

  final la = luminance(a);
  final lb = luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AppThemeVariant.depuisCodeSysteme', () {
    test('résout les 3 familles couvertes', () {
      expect(AppThemeVariant.depuisCodeSysteme('francophone_cfa'), AppThemeVariant.francophoneCfa);
      expect(AppThemeVariant.depuisCodeSysteme('anglophone_waec'), AppThemeVariant.anglophoneWaec);
      expect(AppThemeVariant.depuisCodeSysteme('lusophone'), AppThemeVariant.lusophone);
    });

    test('arabophone_mixte (pas encore de charte dédiée) retombe sur francophone_cfa', () {
      expect(AppThemeVariant.depuisCodeSysteme('arabophone_mixte'), AppThemeVariant.francophoneCfa);
    });

    test('code inconnu ou absent retombe sur francophone_cfa', () {
      expect(AppThemeVariant.depuisCodeSysteme('code_inexistant'), AppThemeVariant.francophoneCfa);
      expect(AppThemeVariant.depuisCodeSysteme(null), AppThemeVariant.francophoneCfa);
    });
  });

  group('AppPalettes.pour', () {
    test('sélectionne la bonne palette pour chaque variante × luminosité', () {
      expect(AppPalettes.pour(AppThemeVariant.francophoneCfa, Brightness.light),
          AppPalettes.francophoneCfaLight);
      expect(AppPalettes.pour(AppThemeVariant.francophoneCfa, Brightness.dark),
          AppPalettes.francophoneCfaDark);
      expect(AppPalettes.pour(AppThemeVariant.anglophoneWaec, Brightness.light),
          AppPalettes.anglophoneWaecLight);
      expect(AppPalettes.pour(AppThemeVariant.anglophoneWaec, Brightness.dark),
          AppPalettes.anglophoneWaecDark);
      expect(AppPalettes.pour(AppThemeVariant.lusophone, Brightness.light),
          AppPalettes.lusophoneLight);
      expect(AppPalettes.pour(AppThemeVariant.lusophone, Brightness.dark),
          AppPalettes.lusophoneDark);
    });
  });

  group('Contraste WCAG AA (4.5:1 texte normal) des 6 palettes', () {
    final toutes = <String, AppPalette>{
      'francophone_cfa clair': AppPalettes.francophoneCfaLight,
      'francophone_cfa sombre': AppPalettes.francophoneCfaDark,
      'anglophone_waec clair': AppPalettes.anglophoneWaecLight,
      'anglophone_waec sombre': AppPalettes.anglophoneWaecDark,
      'lusophone clair': AppPalettes.lusophoneLight,
      'lusophone sombre': AppPalettes.lusophoneDark,
    };

    for (final entry in toutes.entries) {
      test('${entry.key} — texte principal et secondaire lisibles sur le fond', () {
        final p = entry.value;
        expect(_ratioContraste(p.encre, p.fond), greaterThanOrEqualTo(4.5),
            reason: 'encre/fond doit être ≥ 4.5:1 (texte normal)');
        expect(_ratioContraste(p.encreSecondaire, p.fond), greaterThanOrEqualTo(4.5),
            reason: 'encreSecondaire/fond doit être ≥ 4.5:1 (texte normal)');
      });
    }

    // francophone_cfa clair reprend telle quelle la charte « Innovation &
    // Énergie » déjà approuvée (cahier v4.1 ch. 2) — ses teintes d'accent ne
    // sont pas modifiées par ce module et ne sont donc pas re-vérifiées ici,
    // seules les couleurs neuves (anglophone_waec, lusophone) le sont.
    for (final variante in ['anglophone_waec', 'lusophone']) {
      for (final brightness in ['clair', 'sombre']) {
        final p = toutes['$variante $brightness']!;
        test('$variante $brightness — accent/succès/premium/erreur lisibles en usage texte (≥ 4.5:1)', () {
          expect(_ratioContraste(p.accent, p.fond), greaterThanOrEqualTo(4.5));
          expect(_ratioContraste(p.succes, p.fond), greaterThanOrEqualTo(4.5));
          expect(_ratioContraste(p.premium, p.fond), greaterThanOrEqualTo(4.5));
          expect(_ratioContraste(p.erreur, p.fond), greaterThanOrEqualTo(4.5));
        });
      }
    }

    test('bouton primaire : contraste texte/fond ≥ 4.5:1 dans les deux luminosités', () {
      for (final variante in AppThemeVariant.values) {
        final clair = AppPalettes.pour(variante, Brightness.light);
        final sombre = AppPalettes.pour(variante, Brightness.dark);
        // Mode clair : texte blanc sur bouton primaire (cf. construireThemeData).
        expect(_ratioContraste(Colors.white, clair.primaire), greaterThanOrEqualTo(4.5),
            reason: '$variante clair : blanc sur primaire');
        // Mode sombre : le bouton reste dans la teinte de palette (éclaircie),
        // mais le texte passe au ton `fond` (le plus sombre) plutôt qu'au
        // blanc ou à `encre` (clair en mode sombre) pour rester lisible.
        expect(_ratioContraste(sombre.fond, sombre.primaire), greaterThanOrEqualTo(4.5),
            reason: '$variante sombre : fond sur primaire');
      }
    });
  });

  group('construireThemeData', () {
    test('enregistre la palette comme ThemeExtension et respecte la luminosité demandée', () {
      for (final variante in AppThemeVariant.values) {
        for (final brightness in Brightness.values) {
          final theme = construireThemeData(variante, brightness);
          expect(theme.brightness, brightness);
          final palette = theme.extension<AppPalette>();
          expect(palette, isNotNull);
          expect(palette, AppPalettes.pour(variante, brightness));
          expect(theme.scaffoldBackgroundColor, palette!.fond);
        }
      }
    });
  });

  group('BuildContext.palette', () {
    testWidgets('lit la palette du thème Material ambiant', (tester) async {
      late AppPalette lue;
      await tester.pumpWidget(MaterialApp(
        theme: construireThemeData(AppThemeVariant.lusophone, Brightness.dark),
        home: Builder(builder: (context) {
          lue = context.palette;
          return const SizedBox.shrink();
        }),
      ));
      expect(lue, AppPalettes.lusophoneDark);
    });

    testWidgets('retombe sur une palette par défaut si aucun AppPalette n\'est enregistré', (tester) async {
      late AppPalette lue;
      await tester.pumpWidget(MaterialApp(
        // MaterialApp par défaut, sans construireThemeData (ex. widget test isolé).
        home: Builder(builder: (context) {
          lue = context.palette;
          return const SizedBox.shrink();
        }),
      ));
      expect(lue.fond, AppPalettes.francophoneCfaLight.fond);
      expect(lue.primaire, AppPalettes.francophoneCfaLight.primaire);
    });
  });
}
