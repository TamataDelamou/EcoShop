import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/app_palettes.dart';
import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/export_pdf/application/pdf_palette.dart';

void main() {
  group('PdfPaletteX.pour', () {
    for (final variante in AppThemeVariant.values) {
      test('$variante — reprend la palette CLAIRE, jamais la sombre', () {
        final attendu = AppPalettes.pour(variante, Brightness.light);
        final pdf = PdfPaletteX.pour(variante);

        expect(pdf.primaire.red, closeTo(attendu.primaire.r, 0.001));
        expect(pdf.primaire.green, closeTo(attendu.primaire.g, 0.001));
        expect(pdf.primaire.blue, closeTo(attendu.primaire.b, 0.001));

        expect(pdf.encre.red, closeTo(attendu.encre.r, 0.001));
        expect(pdf.encre.green, closeTo(attendu.encre.g, 0.001));
        expect(pdf.encre.blue, closeTo(attendu.encre.b, 0.001));

        // Vérifie explicitement que la variante sombre n'a pas été utilisée
        // par erreur (les deux luminosités ont des `encre` très différentes).
        final sombre = AppPalettes.pour(variante, Brightness.dark);
        final memeEncreQueSombre = (pdf.encre.red - sombre.encre.r).abs() < 0.001 &&
            (pdf.encre.green - sombre.encre.g).abs() < 0.001 &&
            (pdf.encre.blue - sombre.encre.b).abs() < 0.001;
        expect(memeEncreQueSombre, isFalse);
      });
    }
  });
}
