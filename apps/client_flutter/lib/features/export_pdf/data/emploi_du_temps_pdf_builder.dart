import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_theme_variant.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../planification/domain/emploi_du_temps.dart';
import '../application/pdf_palette.dart';
import 'entete_pdf.dart';
import 'etats_financiers_pdf_builder.dart' show textePdf;

const _jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

/// Emploi du temps d'une classe ou d'un enseignant (REG-41), A4 paysage, à
/// l'identité visuelle de l'école : jours en colonnes, créneaux en lignes ;
/// les séances des semaines A et B sont signalées.
Future<Uint8List> construireEmploiDuTempsPdf({
  required List<EmploiDuTemps> seances,
  required Etablissement etablissement,
  required String titre,
  required AppThemeVariant variante,
  IdentitePdf identite = IdentitePdf.vide,
  bool parEnseignant = false,
}) async {
  final palette = PdfPaletteX.pour(variante, identite: identite);
  final doc = pw.Document(title: textePdf('$titre - ${etablissement.nom}'));

  final jours = ({for (final s in seances) s.jourSemaine}.toList()..sort());
  if (jours.isEmpty) jours.addAll([1, 2, 3, 4, 5]);
  final creneaux = <(String, String)>{for (final s in seances) (s.heureDebut, s.heureFin)}.toList()
    ..sort((a, b) => a.$1.compareTo(b.$1) != 0 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));

  pw.Widget cellule(int jour, (String, String) c) {
    final ici = [
      for (final s in seances)
        if (s.jourSemaine == jour && s.heureDebut == c.$1 && s.heureFin == c.$2) s,
    ];
    if (ici.isEmpty) return pw.SizedBox(height: 26);
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final s in ici) ...[
            pw.Text(
              textePdf('${s.nomMatiere ?? s.type.libelle}${s.semaine == null ? '' : ' (sem. ${s.semaine})'}'),
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: palette.primaire),
            ),
            pw.Text(
              textePdf([
                if (parEnseignant) s.nomClasse ?? '' else s.nomEnseignant ?? '',
                if (s.libelleSalle != null) 'salle ${s.libelleSalle}',
              ].where((t) => t.isNotEmpty).join(' - ')),
              style: pw.TextStyle(fontSize: 7, color: palette.encreSecondaire),
            ),
          ],
        ],
      ),
    );
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(24),
    header: (_) => enteteDocument(etablissement: etablissement, titre: textePdf(titre), palette: palette),
    footer: (_) => piedDePage(palette: palette, genereLe: DateTime.now()),
    build: (_) => [
      if (creneaux.isEmpty)
        pw.Text(textePdf('Emploi du temps vide.'))
      else
        pw.Table(
          border: pw.TableBorder.all(color: palette.bordure, width: 0.5),
          columnWidths: {0: const pw.FixedColumnWidth(58)},
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: palette.surface),
              children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('')),
                for (final j in jours)
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(_jours[j - 1], style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ),
              ],
            ),
            for (final c in creneaux)
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('${c.$1}\n${c.$2}', style: pw.TextStyle(fontSize: 8, color: palette.encre)),
                ),
                for (final j in jours) cellule(j, c),
              ]),
          ],
        ),
      if (seances.any((s) => s.semaine != null))
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(textePdf('(sem. A) / (sem. B) : une semaine sur deux.'),
              style: pw.TextStyle(fontSize: 7, color: palette.encreSecondaire)),
        ),
    ],
  ));
  return doc.save();
}
