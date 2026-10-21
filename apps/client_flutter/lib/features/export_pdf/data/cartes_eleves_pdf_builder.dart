import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_theme_variant.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../pointage/domain/pointage.dart';
import '../application/pdf_palette.dart';
import 'etats_financiers_pdf_builder.dart' show textePdf;

/// Cartes d'élève à QR code (REG-09) : format carte bancaire (85,6 × 54 mm),
/// 10 par page A4, à découper et plastifier. Le QR code porte un jeton
/// secret : une carte ne se fabrique pas à partir du matricule.
Future<Uint8List> construireCartesElevesPdf({
  required List<CartePortail> cartes,
  required Etablissement etablissement,
  required String annee,
  required AppThemeVariant variante,
  IdentitePdf identite = IdentitePdf.vide,
}) async {
  final palette = PdfPaletteX.pour(variante, identite: identite);
  final doc = pw.Document(title: textePdf('Cartes élèves - ${etablissement.nom}'));
  const largeur = 85.6 * PdfPageFormat.mm;
  const hauteur = 54 * PdfPageFormat.mm;

  pw.Widget carte(CartePortail c) => pw.Container(
        width: largeur,
        height: hauteur,
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: palette.bordure, width: 0.6),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(children: [
              if (palette.logo != null) ...[
                pw.SizedBox(width: 16, height: 16, child: pw.Image(pw.MemoryImage(palette.logo!), fit: pw.BoxFit.contain)),
                pw.SizedBox(width: 4),
              ],
              pw.Expanded(
                child: pw.Text(
                  textePdf(etablissement.nom),
                  maxLines: 1,
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: palette.primaire),
                ),
              ),
              pw.Text(textePdf(annee), style: pw.TextStyle(fontSize: 7, color: palette.encreSecondaire)),
            ]),
            pw.Container(height: 1, color: palette.primaire, margin: const pw.EdgeInsets.symmetric(vertical: 3)),
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(textePdf(c.nom.toUpperCase()),
                            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: palette.encre)),
                        pw.Text(textePdf(c.prenom), style: pw.TextStyle(fontSize: 10, color: palette.encre)),
                        pw.SizedBox(height: 4),
                        if (c.classe != null)
                          pw.Text(textePdf('Classe : ${c.classe}'), style: pw.TextStyle(fontSize: 8, color: palette.encreSecondaire)),
                        if (c.matricule != null)
                          pw.Text(textePdf('Matricule : ${c.matricule}'),
                              style: pw.TextStyle(fontSize: 8, color: palette.encreSecondaire)),
                        pw.Spacer(),
                        pw.Text(textePdf('Carte à présenter au portail'),
                            style: pw.TextStyle(fontSize: 6, color: palette.encreSecondaire)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 4),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: c.contenuQr,
                    width: 30 * PdfPageFormat.mm,
                    height: 30 * PdfPageFormat.mm,
                    drawText: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  const parPage = 10;
  for (var i = 0; i < cartes.length; i += parPage) {
    final page = cartes.sublist(i, (i + parPage) > cartes.length ? cartes.length : i + parPage);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 12 * PdfPageFormat.mm, vertical: 10 * PdfPageFormat.mm),
      build: (_) => pw.Wrap(
        spacing: 4 * PdfPageFormat.mm,
        runSpacing: 2 * PdfPageFormat.mm,
        children: [for (final c in page) carte(c)],
      ),
    ));
  }
  if (cartes.isEmpty) {
    doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text(textePdf('Aucun élève dans cette classe.')))));
  }
  return doc.save();
}
