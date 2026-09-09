import 'package:flutter/material.dart' show Brightness, Color;
import 'package:pdf/pdf.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_palettes.dart';
import '../../../core/theme/app_theme_variant.dart';

/// Palette PDF dérivée de la charte graphique d'un établissement (M15bis).
///
/// Un document imprimé (bulletin, reçu) reste toujours dans sa variante
/// **claire** — jamais la variante sombre de l'application : le papier n'a
/// pas de « mode sombre », et un bulletin remis à un parent doit rester
/// lisible et imprimable sans consommer d'encre inutile. Seul l'écran de
/// prévisualisation autour du document (barre d'application, fond) suit le
/// thème actif de l'application via `context.palette` comme n'importe quel
/// autre écran — voir `EcranApercuPdf`.
class PdfPaletteX {
  const PdfPaletteX._(this._palette);

  factory PdfPaletteX.pour(AppThemeVariant variante) =>
      PdfPaletteX._(AppPalettes.pour(variante, Brightness.light));

  final AppPalette _palette;

  PdfColor get primaire => _pdf(_palette.primaire);
  PdfColor get accent => _pdf(_palette.accent);
  PdfColor get succes => _pdf(_palette.succes);
  PdfColor get erreur => _pdf(_palette.erreur);
  PdfColor get encre => _pdf(_palette.encre);
  PdfColor get encreSecondaire => _pdf(_palette.encreSecondaire);
  PdfColor get bordure => _pdf(_palette.bordure);
  PdfColor get surface => _pdf(_palette.surface);

  static PdfColor _pdf(Color couleur) => PdfColor(couleur.r, couleur.g, couleur.b);
}
