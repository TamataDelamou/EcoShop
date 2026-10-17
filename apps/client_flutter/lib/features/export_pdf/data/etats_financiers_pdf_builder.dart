import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_theme_variant.dart';
import '../../comptabilite/domain/etats_financiers.dart';
import '../../etablissement/domain/etablissement.dart';
import '../application/pdf_palette.dart';
import 'entete_pdf.dart';

/// La police de base du PDF (Helvetica, non embarquée) ne dessine que le
/// jeu Latin-1 : tirets longs, signe moins typographique, espaces fines et
/// points de suspension sont remplacés (convention de `entete_pdf.dart`).
String textePdf(String s) => s
    .replaceAll('—', '-')
    .replaceAll('–', '-')
    .replaceAll('−', '-')
    .replaceAll('…', '...')
    .replaceAll('’', "'")
    .replaceAll(' ', ' ')
    .replaceAll(' ', ' ');

String _montant(double? v) => v == null ? '' : textePdf(NumberFormat.decimalPattern('fr').format(v.round()));

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// États financiers annuels (REG-03 C4) : bilan actif, bilan passif, compte
/// de résultat et trésorerie, colonnes N et N-1, au format du référentiel de
/// l'établissement.
Future<Uint8List> construireEtatsFinanciersPdf({
  required EtatFinancier etat,
  required Etablissement etablissement,
  required AppThemeVariant variante,
  IdentitePdf identite = IdentitePdf.vide,
}) async {
  final palette = PdfPaletteX.pour(variante, identite: identite);
  final doc = pw.Document(title: textePdf('États financiers ${etat.exerciceLibelle} - ${etablissement.nom}'));
  final n1 = etat.exercicePrecedent != null;

  pw.Widget bandeau() => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        enteteDocument(
          etablissement: etablissement,
          titre: textePdf('États financiers - ${etat.exerciceLibelle}'),
          palette: palette,
        ),
        pw.Text(textePdf(etat.titreReferentiel), style: pw.TextStyle(fontSize: 9, color: palette.encreSecondaire)),
        pw.Text(
          textePdf('Exercice du ${_date(etat.dateDebut)} au ${_date(etat.dateFin)} - montants en ${etablissement.deviseCode}'
              '${etat.provisoire ? ' - DOCUMENT PROVISOIRE' : ''}'),
          style: pw.TextStyle(fontSize: 9, color: etat.provisoire ? PdfColors.red700 : palette.encreSecondaire),
        ),
        pw.SizedBox(height: 10),
      ]);

  pw.Widget tableau(PartieEtat partie) {
    final lignes = etat.partie(partie);
    final actif = partie == PartieEtat.actif;
    final entetes = [
      'Réf.',
      'Rubrique',
      if (actif) 'Brut',
      if (actif) 'Amort./Dépréc.',
      actif ? 'Net N' : 'Exercice N',
      if (n1) actif ? 'Net N-1' : 'Exercice N-1',
    ];
    final largeurs = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(30),
      1: const pw.FlexColumnWidth(4),
    };
    for (var i = 2; i < entetes.length; i++) {
      largeurs[i] = const pw.FlexColumnWidth(1.4);
    }
    pw.Widget cellule(String t, {bool gras = false, bool droite = false, PdfColor? couleur}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(
            textePdf(t),
            textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontSize: 8, fontWeight: gras ? pw.FontWeight.bold : null, color: couleur),
          ),
        );
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(textePdf(partie.titre),
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: palette.primaire)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: palette.bordure, width: 0.4),
        columnWidths: largeurs,
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: palette.primaire),
            children: [for (final e in entetes) cellule(e, gras: true, droite: e != 'Rubrique' && e != 'Réf.', couleur: palette.surface)],
          ),
          for (final l in lignes)
            pw.TableRow(
              decoration: l.total ? pw.BoxDecoration(color: palette.bordure) : null,
              children: [
                cellule(l.reference, gras: l.total),
                cellule(l.libelle, gras: l.total),
                if (actif) cellule(_montant(l.brut), droite: true),
                if (actif) cellule(_montant(l.amortissements), droite: true),
                cellule(_montant(l.montant), gras: l.total, droite: true),
                if (n1) cellule(_montant(l.montantN1), gras: l.total, droite: true),
              ],
            ),
        ],
      ),
      pw.SizedBox(height: 14),
    ]);
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    header: (context) => context.pageNumber == 1 ? bandeau() : pw.SizedBox(),
    footer: (context) => piedDePage(palette: palette, genereLe: DateTime.now()),
    build: (context) => [
      tableau(PartieEtat.actif),
      tableau(PartieEtat.passif),
      pw.Text(
        textePdf(etat.equilibre ? 'Contrôle : total actif = total passif.' : 'ATTENTION : le bilan n\'est pas équilibré.'),
        style: pw.TextStyle(fontSize: 8, color: etat.equilibre ? palette.encreSecondaire : PdfColors.red700),
      ),
      pw.NewPage(),
      tableau(PartieEtat.resultat),
      pw.Text(textePdf('Trésorerie de l\'exercice'),
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: palette.primaire)),
      pw.SizedBox(height: 4),
      for (final (libelle, valeur) in [
        ('Solde au début de l\'exercice', etat.tresorerie.soldeDebut),
        ('Encaissements', etat.tresorerie.encaissements),
        ('Décaissements', etat.tresorerie.decaissements),
        ('Solde à la fin de l\'exercice', etat.tresorerie.soldeFin),
      ])
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(textePdf(libelle), style: const pw.TextStyle(fontSize: 9)),
          pw.Text(_montant(valeur), style: const pw.TextStyle(fontSize: 9)),
        ]),
      if (etat.nonClasses.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Text(textePdf('Comptes non repris dans les rubriques (à vérifier) : ${etat.nonClasses.join(', ')}'),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.red700)),
      ],
      pw.SizedBox(height: 16),
      pw.Text(
        textePdf('États établis par EcoShop à partir des écritures validées. Ils doivent être revus et arrêtés '
            'sous la responsabilité de l\'établissement et de son expert-comptable.'),
        style: pw.TextStyle(fontSize: 7, color: palette.encreSecondaire),
      ),
    ],
  ));

  return doc.save();
}
