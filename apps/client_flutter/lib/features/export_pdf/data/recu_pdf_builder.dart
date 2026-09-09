import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_theme_variant.dart';
import '../../comptabilite/domain/ecriture_comptable.dart';
import '../../comptabilite/presentation/widgets/montant.dart';
import '../../etablissement/domain/etablissement.dart';
import '../application/pdf_palette.dart';
import 'entete_pdf.dart';

/// Construit le PDF d'un reçu à partir d'une écriture comptable (M14) —
/// résout l'écart signalé par l'audit (`docs/AUDIT_ECOSHOP_FLUTTER.md` §0.2) :
/// `ecoshop_flutter` générait un reçu thermique/A4 à chaque encaissement ;
/// aucun écran d'encaissement dédié n'existe encore côté cible (écart
/// distinct, différé — cf. audit M13/M15 point 3), ce module rend donc
/// imprimable n'importe quelle écriture déjà saisie, en attendant cet écran.
///
/// Format A4 unique (pas de variante thermique 58 mm séparée) : la cible n'a
/// pas encore de caisse dédiée à ce jour, un seul format suffit tant que ce
/// besoin n'est pas confirmé.
///
/// Limite connue et acceptée : `ecriture.libelle` est un champ libre saisi
/// par un comptable ; un caractère hors police de base (ex. tiret cadratin
/// « — ») s'affichera comme un glyphe manquant plutôt que de faire échouer
/// la génération. Accepté pour ce module (pas de police embarquée, voir
/// `entete_pdf.dart`) — à revoir si ce cas se révèle fréquent en usage réel.
Future<Uint8List> construireRecuPdf({
  required EcritureComptable ecriture,
  required String libelleCompteDebit,
  required String libelleCompteCredit,
  required String libelleJournal,
  required Etablissement etablissement,
  required AppThemeVariant variante,
}) async {
  final palette = PdfPaletteX.pour(variante);
  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          enteteDocument(etablissement: etablissement, titre: 'Reçu', palette: palette),
          pw.SizedBox(height: 12),
          _ligneInfo('Date', _formaterDate(ecriture.dateEcriture), palette),
          _ligneInfo('Libellé', ecriture.libelle, palette),
          _ligneInfo('Journal', libelleJournal, palette),
          if (ecriture.numeroLot != null) _ligneInfo('Référence', ecriture.numeroLot!, palette),
          pw.SizedBox(height: 16),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 14),
            decoration: pw.BoxDecoration(color: palette.primaire, borderRadius: pw.BorderRadius.circular(6)),
            alignment: pw.Alignment.center,
            child: pw.Text(
              '${formaterMontant(ecriture.montant)} ${etablissement.deviseCode}',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: palette.surface),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Débit : $libelleCompteDebit', style: pw.TextStyle(fontSize: 9, color: palette.encreSecondaire)),
          pw.Text('Crédit : $libelleCompteCredit', style: pw.TextStyle(fontSize: 9, color: palette.encreSecondaire)),
          if (ecriture.saisiHorsLigne) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Saisi hors connexion - synchronisation en attente',
              style: pw.TextStyle(fontSize: 8, color: palette.accent, fontStyle: pw.FontStyle.italic),
            ),
          ],
          pw.Spacer(),
          piedDePage(palette: palette, genereLe: DateTime.now()),
        ],
      ),
    ),
  );

  return doc.save();
}

pw.Widget _ligneInfo(String libelle, String valeur, PdfPaletteX palette) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 90,
          child: pw.Text(libelle, style: pw.TextStyle(fontSize: 9, color: palette.encreSecondaire)),
        ),
        pw.Expanded(child: pw.Text(valeur, style: pw.TextStyle(fontSize: 10, color: palette.encre))),
      ],
    ),
  );
}

String _formaterDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
