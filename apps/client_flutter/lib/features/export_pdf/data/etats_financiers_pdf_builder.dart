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

pw.Widget _cellule(String t, {bool gras = false, bool droite = false, PdfColor? couleur}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        textePdf(t),
        textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(fontSize: 8, fontWeight: gras ? pw.FontWeight.bold : null, color: couleur),
      ),
    );

String _valeurNote(Object? v, String colonne) {
  if (v == null) return '-';
  if (v is num) {
    return colonne.contains('%') ? '${v.toStringAsFixed(1).replaceAll('.', ',')} %' : _montant(v.toDouble());
  }
  return '$v';
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// États financiers annuels (REG-03 C4, C5) : bilan actif, bilan passif,
/// compte de résultat, tableau des flux de trésorerie et notes annexes,
/// colonnes N et N-1, au format du référentiel de l'établissement.
Future<Uint8List> construireEtatsFinanciersPdf({
  required EtatFinancier etat,
  required Etablissement etablissement,
  TableauFlux? flux,
  NotesAnnexes? notes,
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
            children: [for (final e in entetes) _cellule(e, gras: true, droite: e != 'Rubrique' && e != 'Réf.', couleur: palette.surface)],
          ),
          for (final l in lignes)
            pw.TableRow(
              decoration: l.total ? pw.BoxDecoration(color: palette.bordure) : null,
              children: [
                _cellule(l.reference, gras: l.total),
                _cellule(l.libelle, gras: l.total),
                if (actif) _cellule(_montant(l.brut), droite: true),
                if (actif) _cellule(_montant(l.amortissements), droite: true),
                _cellule(_montant(l.montant), gras: l.total, droite: true),
                if (n1) _cellule(_montant(l.montantN1), gras: l.total, droite: true),
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
      if (flux == null) ...[
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
      ] else ...[
        pw.NewPage(),
        pw.Text(textePdf('Tableau des flux de trésorerie (méthode ${flux.methode})'),
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: palette.primaire)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: palette.bordure, width: 0.4),
          columnWidths: {
            0: const pw.FixedColumnWidth(30),
            1: const pw.FlexColumnWidth(5),
            2: const pw.FlexColumnWidth(1.4),
            if (n1) 3: const pw.FlexColumnWidth(1.4),
          },
          children: [
            pw.TableRow(decoration: pw.BoxDecoration(color: palette.primaire), children: [
              for (final e in ['Réf.', 'Libellé', 'Exercice N', if (n1) 'Exercice N-1'])
                _cellule(e, gras: true, droite: e.startsWith('Exercice'), couleur: palette.surface),
            ]),
            for (final l in flux.visibles)
              pw.TableRow(decoration: l.total ? pw.BoxDecoration(color: palette.bordure) : null, children: [
                _cellule(l.reference, gras: l.total),
                _cellule(l.libelle, gras: l.total),
                _cellule(_montant(l.montant), gras: l.total, droite: true),
                if (n1) _cellule(_montant(l.montantN1), gras: l.total, droite: true),
              ]),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          textePdf(flux.concordant
              ? 'Contrôle : trésorerie de clôture = trésorerie du bilan (${_montant(flux.tresorerieBilan)}).'
              : 'ATTENTION : écart de ${_montant(flux.ecartCloture)} avec la trésorerie du bilan.'),
          style: pw.TextStyle(fontSize: 8, color: flux.concordant ? palette.encreSecondaire : PdfColors.red700),
        ),
      ],
      if (notes != null && notes.notes.any((n) => !n.vide)) ...[
        pw.NewPage(),
        pw.Text(textePdf('Notes annexes'),
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: palette.primaire)),
        pw.SizedBox(height: 6),
        for (final note in notes.notes)
          if (!note.vide) ...[
            pw.Text(textePdf('Note ${note.code} - ${note.titre}'),
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: palette.primaire)),
            pw.SizedBox(height: 3),
            if (note.estTableau)
              pw.Table(
                border: pw.TableBorder.all(color: palette.bordure, width: 0.4),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  for (var i = 1; i < note.colonnes.length; i++) i: const pw.FlexColumnWidth(1.3),
                },
                children: [
                  pw.TableRow(decoration: pw.BoxDecoration(color: palette.primaire), children: [
                    for (var i = 0; i < note.colonnes.length; i++)
                      _cellule(note.colonnes[i], gras: true, droite: i > 0, couleur: palette.surface),
                  ]),
                  for (final l in note.lignes)
                    pw.TableRow(children: [
                      for (var i = 0; i < note.colonnes.length; i++)
                        _cellule(i < l.length ? _valeurNote(l[i], note.colonnes[i]) : '', droite: i > 0),
                    ]),
                ],
              )
            else
              pw.Text(textePdf(note.texte!), style: const pw.TextStyle(fontSize: 8.5)),
            pw.SizedBox(height: 10),
          ],
      ],
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
