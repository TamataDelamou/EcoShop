import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_theme_variant.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../notes/domain/bulletin.dart';
import '../../scolarite/domain/fiche_eleve.dart';
import '../application/pdf_palette.dart';
import 'entete_pdf.dart';

/// Construit le PDF d'un bulletin publié (M6) — résout l'écart signalé par
/// l'audit (`docs/AUDIT_ECOSHOP_FLUTTER.md` §0.2) : `ecoshop_flutter`
/// générait un bulletin PDF codé en dur (pas un système de gabarits) ; ce
/// module fait de même mais aligné sur la charte graphique et les 3 variantes
/// d'établissement de M15bis, plutôt que la mise en page unique de la source.
///
/// Le contenu détaillé (`bulletin.contenu`, jsonb libre côté serveur — voir
/// contrat M06 §2) est rendu tel quel, clé par clé : ce module ne réinvente
/// pas le format du bulletin, il l'imprime.
Future<Uint8List> construireBulletinPdf({
  required Bulletin bulletin,
  required FicheEleve fiche,
  required Etablissement etablissement,
  required AppThemeVariant variante,
}) async {
  final palette = PdfPaletteX.pour(variante);
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => enteteDocument(
        etablissement: etablissement,
        titre: bulletin.type.libelle,
        palette: palette,
      ),
      footer: (context) => piedDePage(palette: palette, genereLe: DateTime.now()),
      build: (context) => [
        _identiteEleve(fiche: fiche, palette: palette),
        pw.SizedBox(height: 16),
        _tableauContenu(bulletin: bulletin, palette: palette),
        if (bulletin.signatureSha256 != null) ...[
          pw.SizedBox(height: 20),
          pw.Text(
            'Intégrité vérifiable - empreinte ${bulletin.signatureSha256}',
            style: pw.TextStyle(fontSize: 7, color: palette.encreSecondaire),
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _identiteEleve({required FicheEleve fiche, required PdfPaletteX palette}) {
  final naissance = fiche.dateNaissance;
  final dateAffichee = '${naissance.day.toString().padLeft(2, '0')}/'
      '${naissance.month.toString().padLeft(2, '0')}/${naissance.year}';

  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: palette.bordure),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('${fiche.prenom} ${fiche.nom}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: palette.encre)),
            pw.Text('Matricule : ${fiche.matricule}', style: pw.TextStyle(fontSize: 9, color: palette.encreSecondaire)),
          ],
        ),
        pw.Text('Né(e) le $dateAffichee', style: pw.TextStyle(fontSize: 9, color: palette.encreSecondaire)),
      ],
    ),
  );
}

pw.Widget _tableauContenu({required Bulletin bulletin, required PdfPaletteX palette}) {
  if (bulletin.contenu.isEmpty) {
    return pw.Text('Contenu détaillé indisponible pour le moment.',
        style: pw.TextStyle(color: palette.encreSecondaire));
  }

  return pw.TableHelper.fromTextArray(
    headers: const ['Rubrique', 'Valeur'],
    data: [
      for (final entree in bulletin.contenu.entries) [_libelleRubrique(entree.key), '${entree.value}'],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: palette.surface, fontSize: 10),
    headerDecoration: pw.BoxDecoration(color: palette.primaire),
    cellStyle: pw.TextStyle(fontSize: 10, color: palette.encre),
    cellHeight: 24,
    border: pw.TableBorder.all(color: palette.bordure, width: 0.5),
    cellAlignments: const {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft},
  );
}

/// Les clés de `bulletin.contenu` sont libres côté serveur (snake_case) —
/// mise en forme superficielle pour l'affichage imprimé, pas une traduction
/// exhaustive : une clé inconnue s'affiche telle quelle plutôt que de faire
/// échouer la génération du document.
String _libelleRubrique(String cle) {
  final mots = cle.split('_');
  return mots.map((m) => m.isEmpty ? m : '${m[0].toUpperCase()}${m.substring(1)}').join(' ');
}
