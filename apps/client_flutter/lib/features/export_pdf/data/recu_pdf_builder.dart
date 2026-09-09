import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_theme_variant.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../scolarite/domain/encaissement_scolarite.dart';
import '../../scolarite/domain/fiche_eleve.dart';
import '../application/pdf_palette.dart';
import 'entete_pdf.dart';

String _formaterMontant(double montant) => NumberFormat.decimalPattern('fr').format(montant);

/// Construit le PDF d'un reçu à partir d'un **encaissement de scolarité**
/// dédié (`EncaissementScolarite`, M15quater) — résout l'écart signalé par
/// l'audit (`docs/AUDIT_ECOSHOP_FLUTTER.md` §0.2).
///
/// Une première version de ce module s'appuyait sur `EcritureComptable`
/// (écriture comptable générale de M14) et a été **retirée** avant tout push
/// vers `origin/main` : cette entité n'avait aucun lien structurel avec un
/// élève, une inscription ou un solde dû, si bien que le document imprimé
/// avait l'apparence d'un reçu de scolarité sans qu'aucune donnée ne le
/// garantisse (voir `docs/contrats/M15ter_export_pdf.md` §7 pour
/// l'historique complet du retrait). `EncaissementScolarite` porte
/// explicitement `ficheEleveId`/`inscriptionId` : un reçu généré ici
/// correspond toujours à un encaissement réellement lié à un élève inscrit.
Future<Uint8List> construireRecuPdf({
  required EncaissementScolarite encaissement,
  required FicheEleve fiche,
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
          enteteDocument(etablissement: etablissement, titre: 'Reçu de scolarité', palette: palette),
          pw.SizedBox(height: 12),
          _ligneInfo('Élève', fiche.nomComplet, palette),
          _ligneInfo('Matricule', fiche.matricule, palette),
          pw.SizedBox(height: 8),
          _ligneInfo('Date', _formaterDate(encaissement.datePaiement), palette),
          _ligneInfo('Type de frais', encaissement.typeFrais.libelle, palette),
          _ligneInfo('Moyen de paiement', encaissement.moyenPaiement.libelle, palette),
          if (encaissement.referencePaiement != null)
            _ligneInfo('Référence', encaissement.referencePaiement!, palette),
          pw.SizedBox(height: 16),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 14),
            decoration: pw.BoxDecoration(color: palette.primaire, borderRadius: pw.BorderRadius.circular(6)),
            alignment: pw.Alignment.center,
            child: pw.Text(
              '${_formaterMontant(encaissement.montant)} ${etablissement.deviseCode}',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: palette.surface),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Ce document atteste un encaissement enregistré pour cet élève. '
            'Identifiant de l\'encaissement : ${encaissement.id}.',
            style: pw.TextStyle(fontSize: 7, color: palette.encreSecondaire),
          ),
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
          width: 110,
          child: pw.Text(libelle, style: pw.TextStyle(fontSize: 9, color: palette.encreSecondaire)),
        ),
        pw.Expanded(child: pw.Text(valeur, style: pw.TextStyle(fontSize: 10, color: palette.encre))),
      ],
    ),
  );
}

String _formaterDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
