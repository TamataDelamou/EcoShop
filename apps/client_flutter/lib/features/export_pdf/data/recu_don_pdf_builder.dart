import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_theme_variant.dart';
import '../../comptabilite/domain/dons.dart';
import '../../comptabilite/domain/montant_en_lettres.dart';
import '../../etablissement/domain/etablissement.dart';
import '../application/pdf_palette.dart';
import 'entete_pdf.dart';
import 'etats_financiers_pdf_builder.dart' show textePdf;

String _montant(double v) => textePdf(NumberFormat.decimalPattern('fr').format(v.round()));

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _enLettres(double montant, String devise) {
  final t = montantEnLettres(montant);
  return '${t[0].toUpperCase()}${t.substring(1)} ${deviseEnLettres(devise, montant)}';
}

/// Reçu de don (REG-03 C5) : numéro continu attribué par le serveur,
/// montant en chiffres et en lettres, mention « ANNULÉ » le cas échéant.
Future<Uint8List> construireRecuDonPdf({
  required RecuDon recu,
  required Etablissement etablissement,
  required AppThemeVariant variante,
  IdentitePdf identite = IdentitePdf.vide,
}) async {
  final palette = PdfPaletteX.pour(variante, identite: identite);
  final doc = pw.Document(title: textePdf('Reçu de don ${recu.numeroRecu} - ${etablissement.nom}'));
  final devise = etablissement.deviseCode;

  pw.Widget ligne(String libelle, String valeur) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 130, child: pw.Text(textePdf(libelle), style: pw.TextStyle(fontSize: 10, color: palette.encreSecondaire))),
          pw.Expanded(child: pw.Text(textePdf(valeur), style: const pw.TextStyle(fontSize: 10))),
        ]),
      );

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin: const pw.EdgeInsets.all(24),
    build: (context) => pw.Stack(children: [
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        enteteDocument(
          etablissement: etablissement,
          titre: textePdf(recu.provisoire
              ? 'Reçu de don PROVISOIRE N° ${recu.numeroRecu}'
              : 'Reçu de don N° ${recu.numeroRecu}'),
          palette: palette,
        ),
        if (recu.provisoire)
          pw.Text(
            textePdf('Saisi sans réseau. Le numéro définitif est attribué à l\'envoi au serveur ; '
                'le reçu définitif pourra alors être remis.'),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.orange800),
          )
        else if (recu.numeroProvisoire != null)
          pw.Text(textePdf('Remplace le reçu provisoire ${recu.numeroProvisoire}.'),
              style: pw.TextStyle(fontSize: 8, color: palette.encreSecondaire)),
        pw.SizedBox(height: 8),
        ligne('Date du don', _date(recu.dateDon)),
        ligne('Reçu de', recu.donateurNom ?? (recu.nature == NatureDon.quete ? 'Quête' : 'Donateur anonyme')),
        if (recu.donateurAdresse != null) ligne('Adresse', recu.donateurAdresse!),
        ligne('Nature', recu.nature.libelle),
        ligne('Moyen de paiement', '${recu.moyen.libelle}${recu.reference != null ? ' - réf. ${recu.reference}' : ''}'),
        if (recu.affectation != null) ligne('Affecté à', recu.affectation!),
        if (recu.eleve != null) ligne('Élève parrainé', recu.eleve!),
        pw.SizedBox(height: 10),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: palette.primaire, width: 1)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('${_montant(recu.montant)} $devise',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: palette.primaire)),
            pw.SizedBox(height: 2),
            pw.Text(textePdf(_enLettres(recu.montant, devise)), style: const pw.TextStyle(fontSize: 10)),
          ]),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          textePdf('${etablissement.nom} atteste avoir reçu ce don et remercie chaleureusement son auteur.'),
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 28),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(textePdf(recu.saisiPar == null ? '' : 'Établi par ${recu.saisiPar}'),
              style: pw.TextStyle(fontSize: 8, color: palette.encreSecondaire)),
          pw.Column(children: [
            pw.Container(width: 150, height: 0.5, color: palette.bordure),
            pw.SizedBox(height: 2),
            pw.Text(textePdf('Signature et cachet'), style: pw.TextStyle(fontSize: 8, color: palette.encreSecondaire)),
          ]),
        ]),
      ]),
      if (recu.annule)
        pw.Center(
          child: pw.Transform.rotateBox(
            angle: 0.35,
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.red700, width: 2)),
              child: pw.Column(children: [
                pw.Text(textePdf('ANNULÉ'),
                    style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
                if (recu.motifAnnulation != null)
                  pw.Text(textePdf(recu.motifAnnulation!), style: const pw.TextStyle(fontSize: 9, color: PdfColors.red700)),
              ]),
            ),
          ),
        ),
    ]),
  ));
  return doc.save();
}

/// Relevé annuel d'un donateur : tous ses dons de l'année, total en
/// chiffres et en lettres.
Future<Uint8List> construireReleveDonateurPdf({
  required ReleveDonateur releve,
  required Etablissement etablissement,
  required AppThemeVariant variante,
  IdentitePdf identite = IdentitePdf.vide,
}) async {
  final palette = PdfPaletteX.pour(variante, identite: identite);
  final devise = etablissement.deviseCode;
  final doc = pw.Document(title: textePdf('Relevé des dons ${releve.annee} - ${releve.donateurNom}'));

  pw.Widget cellule(String t, {bool gras = false, bool droite = false, PdfColor? couleur}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(textePdf(t),
            textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontSize: 9, fontWeight: gras ? pw.FontWeight.bold : null, color: couleur)),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    header: (context) => context.pageNumber == 1
        ? enteteDocument(etablissement: etablissement, titre: textePdf('Relevé des dons ${releve.annee}'), palette: palette)
        : pw.SizedBox(),
    footer: (context) => piedDePage(palette: palette, genereLe: DateTime.now()),
    build: (context) => [
      pw.Text(textePdf(releve.donateurNom), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      if (releve.adresse != null) pw.Text(textePdf(releve.adresse!), style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 12),
      pw.Table(
        border: pw.TableBorder.all(color: palette.bordure, width: 0.4),
        columnWidths: const {
          0: pw.FixedColumnWidth(95),
          1: pw.FixedColumnWidth(60),
          2: pw.FlexColumnWidth(3),
          3: pw.FlexColumnWidth(1.4),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: palette.primaire),
            children: [
              cellule('Reçu', gras: true, couleur: palette.surface),
              cellule('Date', gras: true, couleur: palette.surface),
              cellule('Nature / affectation', gras: true, couleur: palette.surface),
              cellule('Montant ($devise)', gras: true, droite: true, couleur: palette.surface),
            ],
          ),
          for (final d in releve.dons)
            pw.TableRow(children: [
              cellule(d.numeroRecu),
              cellule(_date(d.date)),
              cellule('${d.nature.libelle}${d.affectation != null ? ' - ${d.affectation}' : ''}'),
              cellule(_montant(d.montant), droite: true),
            ]),
          pw.TableRow(decoration: pw.BoxDecoration(color: palette.bordure), children: [
            cellule('TOTAL', gras: true),
            cellule(''),
            cellule('${releve.dons.length} don(s)'),
            cellule(_montant(releve.total), gras: true, droite: true),
          ]),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Text(textePdf('Soit ${_enLettres(releve.total, devise)}.'), style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 14),
      pw.Text(
        textePdf('${etablissement.nom} atteste avoir reçu les dons ci-dessus au cours de l\'année ${releve.annee} '
            'et remercie leur auteur de sa fidélité.'),
        style: const pw.TextStyle(fontSize: 9),
      ),
    ],
  ));
  return doc.save();
}
