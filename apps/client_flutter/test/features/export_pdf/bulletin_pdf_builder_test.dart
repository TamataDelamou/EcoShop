import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/export_pdf/data/bulletin_pdf_builder.dart';
import 'package:ecoshop_client/features/notes/domain/bulletin.dart';
import 'package:ecoshop_client/features/notes/domain/enums_notes.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';

void main() {
  final etablissement = const Etablissement(
    id: 'e1',
    nom: 'Groupe Scolaire Test',
    slug: 'gs-test',
    ville: 'Conakry',
    paysCode: 'GN',
  );

  final fiche = FicheEleve(
    id: 'f1',
    etablissementId: 'e1',
    matricule: 'GN-0001',
    nom: 'CAMARA',
    prenom: 'Mory',
    dateNaissance: DateTime(2011, 4, 12),
  );

  Bulletin bulletinAvec(Map<String, dynamic> contenu) => Bulletin(
        id: 'b1',
        etablissementId: 'e1',
        anneeScolaireId: 'a1',
        classeId: 'c1',
        ficheEleveId: 'f1',
        type: TypeBulletin.trimestriel,
        statut: StatutBulletin.publie,
        contenu: contenu,
        signatureSha256: 'abcd1234efgh5678',
        publieLe: DateTime(2026, 12, 20),
      );

  for (final variante in AppThemeVariant.values) {
    test('génère un PDF valide (magic bytes %PDF) pour $variante avec contenu', () async {
      final octets = await construireBulletinPdf(
        bulletin: bulletinAvec({'moyenne_generale': 14.5, 'rang': '3/28', 'appreciation': 'Bon trimestre'}),
        fiche: fiche,
        etablissement: etablissement,
        variante: variante,
      );

      expect(octets, isNotEmpty);
      expect(octets.length, greaterThan(500));
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });
  }

  test('ne plante pas quand le contenu du bulletin est vide (repli affiché plutôt qu\'une exception)', () async {
    final octets = await construireBulletinPdf(
      bulletin: bulletinAvec(const {}),
      fiche: fiche,
      etablissement: etablissement,
      variante: AppThemeVariant.francophoneCfa,
    );

    expect(octets, isNotEmpty);
    expect(String.fromCharCodes(octets.take(5)), '%PDF-');
  });
}
