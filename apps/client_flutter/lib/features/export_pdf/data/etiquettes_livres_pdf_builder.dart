import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_theme_variant.dart';
import '../../bibliotheque/domain/bibliotheque.dart';
import '../../etablissement/domain/etablissement.dart';
import '../application/pdf_palette.dart';
import 'etats_financiers_pdf_builder.dart' show textePdf;

/// Étiquettes d'exemplaires (M17) : 24 par page A4 (3 × 8, format des
/// planches d'étiquettes adhésives 70 × 37 mm), QR code lu par la caméra ou
/// la douchette au guichet, code lisible, titre et cote.
Future<Uint8List> construireEtiquettesLivresPdf({
  required List<ExemplaireGuichet> exemplaires,
  required Etablissement etablissement,
  required AppThemeVariant variante,
  IdentitePdf identite = IdentitePdf.vide,
}) async {
  final palette = PdfPaletteX.pour(variante, identite: identite);
  final doc = pw.Document(title: textePdf('Étiquettes bibliothèque - ${etablissement.nom}'));
  const largeur = 70 * PdfPageFormat.mm;
  const hauteur = 37 * PdfPageFormat.mm;

  pw.Widget etiquette(ExemplaireGuichet e) => pw.Container(
        width: largeur,
        height: hauteur,
        padding: const pw.EdgeInsets.all(5),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: palette.bordure, width: 0.3)),
        child: pw.Row(
          children: [
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: '$prefixeQrLivre${e.code}',
              width: 26 * PdfPageFormat.mm,
              height: 26 * PdfPageFormat.mm,
            ),
            pw.SizedBox(width: 5),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(textePdf(etablissement.nom),
                      maxLines: 1, style: pw.TextStyle(fontSize: 6, color: palette.encreSecondaire)),
                  pw.SizedBox(height: 2),
                  pw.Text(e.code, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: palette.primaire)),
                  pw.SizedBox(height: 2),
                  pw.Text(textePdf(e.titre), maxLines: 2, style: pw.TextStyle(fontSize: 7, color: palette.encre)),
                  if (e.cote != null)
                    pw.Text(textePdf('Cote : ${e.cote}'), style: pw.TextStyle(fontSize: 7, color: palette.encreSecondaire)),
                ],
              ),
            ),
          ],
        ),
      );

  const parPage = 24;
  for (var debut = 0; debut < exemplaires.length; debut += parPage) {
    final fin = debut + parPage > exemplaires.length ? exemplaires.length : debut + parPage;
    final lot = exemplaires.sublist(debut, fin);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Wrap(children: [for (final e in lot) etiquette(e)]),
    ));
  }
  if (exemplaires.isEmpty) {
    doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text(textePdf('Aucun exemplaire')))));
  }
  return doc.save();
}
