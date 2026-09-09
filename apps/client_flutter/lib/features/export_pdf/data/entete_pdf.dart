import 'package:pdf/widgets.dart' as pw;

import '../../etablissement/domain/etablissement.dart';
import '../application/pdf_palette.dart';

// Convention pour tout texte rendu dans ce module (ici et dans les
// constructeurs de bulletin.dart PDF/recu.dart PDF) : tiret simple « - »,
// jamais de tiret cadratin « — ». La police de base intégrée (Helvetica, non
// embarquée pour rester hors-ligne et léger) ne dessine pas ce glyphe et
// laisse un caractère manquant dans le document imprimé.

/// En-tête commun (nom de l'établissement + titre du document) et pied de
/// page (date de génération + numéro de page), partagés par les bulletins
/// (M6) et les reçus (M13/M14) — un seul endroit à faire évoluer si la charte
/// documentaire change.
pw.Widget enteteDocument({
  required Etablissement etablissement,
  required String titre,
  required PdfPaletteX palette,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                etablissement.nom,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: palette.primaire),
              ),
              if (etablissement.localisation.isNotEmpty)
                pw.Text(etablissement.localisation, style: pw.TextStyle(fontSize: 9, color: palette.encreSecondaire)),
            ],
          ),
          pw.Text(
            titre,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: palette.encre),
          ),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Divider(color: palette.bordure, thickness: 1),
      pw.SizedBox(height: 8),
    ],
  );
}

pw.Widget piedDePage({required PdfPaletteX palette, required DateTime genereLe}) {
  final horodatage = '${genereLe.day.toString().padLeft(2, '0')}/'
      '${genereLe.month.toString().padLeft(2, '0')}/${genereLe.year} à '
      '${genereLe.hour.toString().padLeft(2, '0')}:${genereLe.minute.toString().padLeft(2, '0')}';
  return pw.Column(
    children: [
      pw.Divider(color: palette.bordure, thickness: 0.5),
      pw.Text(
        'Document généré le $horodatage - EcoShop',
        style: pw.TextStyle(fontSize: 7, color: palette.encreSecondaire),
      ),
    ],
  );
}
