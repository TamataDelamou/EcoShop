import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/theme/app_theme_variant.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../notes/domain/bulletin.dart';
import '../../notes/domain/detail_matiere_bulletin.dart';
import '../../referentiel/domain/pays_pedagogique.dart';
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

/// Export groupé (D5, cahier §12.4) — UN SEUL PDF multi-pages pour toute une
/// classe, une page par élève (même mise en page que l'export individuel),
/// comme `PdfService.genererBulletinsClasseA4()` côté `ecoshop_flutter` : un
/// seul fichier concaténé plutôt qu'une série de fichiers séparés, cohérent
/// avec la seule action `PdfPreview`/impression déjà utilisée partout
/// ailleurs (pas de zip à construire).
///
/// [pw.NewPage] force un saut de page entre deux élèves plutôt qu'un
/// [pw.Page] par élève (choix de la source) : si le contenu d'un élève
/// déborde exceptionnellement d'une page, il continue sur la suivante au
/// lieu d'être tronqué — un bulletin par élève dans le cas normal, jamais de
/// perte de données dans le cas limite.
///
/// Contenu réglementaire (complément demandé après f8968e1, pas dans la
/// version initiale de D5) :
/// - [pays] : nom du pays et Ministère de tutelle en en-tête, résilient
///   (donnée absente -> ligne omise, jamais une erreur) — voir docstring de
///   [PaysPedagogique.ministereTutelle].
/// - `detailMatieres` de chaque paire : tableau par matière (secondaire
///   uniquement — vide pour le primaire, cf. `classe_isced`/
///   `detail_bulletin_matieres` côté serveur), nom + EMAIL du professeur
///   (jamais le téléphone, réservé à l'usage interne des responsables
///   scolaires).
/// - [isced] : palier de la classe (constant pour tout l'export, une seule
///   classe à la fois), utilisé pour choisir les libellés de signature.
/// - Mention "Non duplicata." après les signatures.
Future<Uint8List> construireBulletinsClassePdf({
  required List<({Bulletin bulletin, FicheEleve fiche, List<DetailMatiereBulletin> detailMatieres})> paires,
  required Etablissement etablissement,
  required AppThemeVariant variante,
  required String titreClasse,
  PaysPedagogique? pays,
  int? isced,
}) async {
  final palette = PdfPaletteX.pour(variante);
  final doc = pw.Document();
  final signatures = pays?.signaturesPourIsced(isced);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _entetePays(pays: pays, palette: palette),
          enteteDocument(
            etablissement: etablissement,
            titre: titreClasse,
            palette: palette,
          ),
        ],
      ),
      footer: (context) => piedDePage(palette: palette, genereLe: DateTime.now()),
      build: (context) => [
        for (var i = 0; i < paires.length; i++) ...[
          if (i > 0) pw.NewPage(),
          _identiteEleve(fiche: paires[i].fiche, palette: palette),
          pw.SizedBox(height: 16),
          _tableauMatieres(details: paires[i].detailMatieres, palette: palette),
          _tableauContenu(bulletin: paires[i].bulletin, palette: palette),
          _blocSignatures(libelles: signatures, palette: palette),
          _mentionNonDuplicata(palette: palette),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _entetePays({required PaysPedagogique? pays, required PdfPaletteX palette}) {
  if (pays == null) return pw.SizedBox.shrink();
  final ministere = pays.ministereTutelle;
  final texte = (ministere == null || ministere.isEmpty) ? pays.nom : '${pays.nom} - $ministere';
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Text(texte, style: pw.TextStyle(fontSize: 8, color: palette.encreSecondaire)),
  );
}

pw.Widget _tableauMatieres({required List<DetailMatiereBulletin> details, required PdfPaletteX palette}) {
  if (details.isEmpty) return pw.SizedBox.shrink();

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.TableHelper.fromTextArray(
        headers: const ['Matière', 'Coef.', 'Moyenne', 'Professeur'],
        data: [
          for (final d in details)
            [
              d.matiere,
              d.coefficient?.toString() ?? '-',
              d.moyenne == null ? '-' : '${d.moyenne!.toStringAsFixed(2)}/20',
              [d.enseignantNom, d.enseignantEmail]
                  .where((s) => s != null && s.isNotEmpty)
                  .join(' - '),
            ],
        ],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: palette.surface, fontSize: 9),
        headerDecoration: pw.BoxDecoration(color: palette.primaire),
        cellStyle: pw.TextStyle(fontSize: 9, color: palette.encre),
        cellHeight: 22,
        border: pw.TableBorder.all(color: palette.bordure, width: 0.5),
        cellAlignments: const {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
          2: pw.Alignment.center,
          3: pw.Alignment.centerLeft,
        },
      ),
      pw.SizedBox(height: 16),
    ],
  );
}

pw.Widget _blocSignatures({required LibellesSignatureCycle? libelles, required PdfPaletteX palette}) {
  if (libelles == null) return pw.SizedBox.shrink();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 28),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _signature(libelles.signataire1, palette),
        _signature(libelles.signataire2, palette),
      ],
    ),
  );
}

pw.Widget _signature(String role, PdfPaletteX palette) {
  return pw.Column(
    children: [
      pw.SizedBox(width: 140, child: pw.Divider(color: palette.bordure)),
      pw.Text(role, style: pw.TextStyle(fontSize: 9, color: palette.encreSecondaire)),
    ],
  );
}

pw.Widget _mentionNonDuplicata({required PdfPaletteX palette}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 10),
    child: pw.Center(
      child: pw.Text(
        'Non duplicata.',
        style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: palette.encreSecondaire),
      ),
    ),
  );
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
