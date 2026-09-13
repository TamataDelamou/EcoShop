import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/export_pdf/data/bulletin_pdf_builder.dart';
import 'package:ecoshop_client/features/notes/domain/bulletin.dart';
import 'package:ecoshop_client/features/notes/domain/detail_matiere_bulletin.dart';
import 'package:ecoshop_client/features/notes/domain/enums_notes.dart';
import 'package:ecoshop_client/features/referentiel/domain/pays_pedagogique.dart';
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

  group('construireBulletinsClassePdf (D5, export groupé)', () {
    final fiche2 = FicheEleve(
      id: 'f2',
      etablissementId: 'e1',
      matricule: 'GN-0002',
      nom: 'DIALLO',
      prenom: 'Ibrahima',
      dateNaissance: DateTime(2011, 7, 30),
    );

    test('génère un seul PDF valide pour toute la classe (un élève)', () async {
      final octets = await construireBulletinsClassePdf(
        paires: [
          (bulletin: bulletinAvec({'moyenne_generale': 18, 'rang': 1, 'effectif_classe': 2}), fiche: fiche, detailMatieres: const []),
        ],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
      );

      expect(octets, isNotEmpty);
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });

    test('reste un document valide avec plusieurs élèves (page par élève)', () async {
      final octets = await construireBulletinsClassePdf(
        paires: [
          (bulletin: bulletinAvec({'moyenne_generale': 18, 'rang': 1, 'effectif_classe': 2}), fiche: fiche, detailMatieres: const []),
          (bulletin: bulletinAvec({'moyenne_generale': 10, 'rang': 2, 'effectif_classe': 2}), fiche: fiche2, detailMatieres: const []),
        ],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
      );

      expect(octets, isNotEmpty);
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
      // Un document multi-pages produit davantage d'octets qu'un document à
      // un seul élève avec un contenu comparable — vérifie empiriquement que
      // le second élève a bien été rendu, pas seulement accepté sans erreur.
      final octetsUnSeul = await construireBulletinsClassePdf(
        paires: [
          (bulletin: bulletinAvec({'moyenne_generale': 18, 'rang': 1, 'effectif_classe': 2}), fiche: fiche, detailMatieres: const []),
        ],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
      );
      expect(octets.length, greaterThan(octetsUnSeul.length));
    });

    test('ne plante pas avec une liste vide (aucun élève classé)', () async {
      final octets = await construireBulletinsClassePdf(
        paires: const [],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
      );

      expect(octets, isNotEmpty);
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });

    test('un tableau par matière non vide (secondaire) produit un document plus volumineux', () async {
      final sansMatieres = await construireBulletinsClassePdf(
        paires: [
          (bulletin: bulletinAvec({'moyenne_generale': 18, 'rang': 1, 'effectif_classe': 2}), fiche: fiche, detailMatieres: const []),
        ],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
        isced: 2,
      );

      final avecMatieres = await construireBulletinsClassePdf(
        paires: [
          (
            bulletin: bulletinAvec({'moyenne_generale': 18, 'rang': 1, 'effectif_classe': 2}),
            fiche: fiche,
            detailMatieres: const [
              DetailMatiereBulletin(
                matiere: 'Mathématiques',
                coefficient: 4,
                moyenne: 16.5,
                enseignantNom: 'Mory CAMARA',
                enseignantEmail: 'mory.camara@ecole-test.gn',
              ),
            ],
          ),
        ],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
        isced: 2,
      );

      expect(String.fromCharCodes(avecMatieres.take(5)), '%PDF-');
      expect(avecMatieres.length, greaterThan(sansMatieres.length));
    });

    test('pays + Ministère de tutelle en en-tête ne plante pas et grossit le document', () async {
      const pays = PaysPedagogique(
        codeIso: 'GN',
        nom: 'Guinée',
        typeSysteme: 'francophone_cfa',
        langueEnseignementPrincipale: 'français',
        ministereTutelle: "Ministère de l'Enseignement Pré-Universitaire",
      );

      final sansPays = await construireBulletinsClassePdf(
        paires: [(bulletin: bulletinAvec({'moyenne_generale': 18}), fiche: fiche, detailMatieres: const [])],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
      );
      final avecPays = await construireBulletinsClassePdf(
        paires: [(bulletin: bulletinAvec({'moyenne_generale': 18}), fiche: fiche, detailMatieres: const [])],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
        pays: pays,
      );

      expect(String.fromCharCodes(avecPays.take(5)), '%PDF-');
      expect(avecPays.length, greaterThan(sansPays.length));
    });

    test('Ministère de tutelle absent (résilience) : rend quand même un PDF valide', () async {
      const paysSansMinistere = PaysPedagogique(
        codeIso: 'GN',
        nom: 'Guinée',
        typeSysteme: 'francophone_cfa',
        langueEnseignementPrincipale: 'français',
      );

      final octets = await construireBulletinsClassePdf(
        paires: [(bulletin: bulletinAvec({'moyenne_generale': 18}), fiche: fiche, detailMatieres: const [])],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
        pays: paysSansMinistere,
      );

      expect(octets, isNotEmpty);
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });

    test('bloc signatures par cycle (collège) : présent et n\'empêche pas un PDF valide', () async {
      const pays = PaysPedagogique(
        codeIso: 'GN',
        nom: 'Guinée',
        typeSysteme: 'francophone_cfa',
        langueEnseignementPrincipale: 'français',
        signaturesBulletin: {
          'college': {'signataire1': 'Proviseur', 'signataire2': 'Directeur des Études'},
        },
      );

      final sansSignatures = await construireBulletinsClassePdf(
        paires: [(bulletin: bulletinAvec({'moyenne_generale': 18}), fiche: fiche, detailMatieres: const [])],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
      );
      final avecSignatures = await construireBulletinsClassePdf(
        paires: [(bulletin: bulletinAvec({'moyenne_generale': 18}), fiche: fiche, detailMatieres: const [])],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
        pays: pays,
        isced: 2,
      );

      expect(String.fromCharCodes(avecSignatures.take(5)), '%PDF-');
      expect(avecSignatures.length, greaterThan(sansSignatures.length));
    });

    test('isced sans libellés de signature pour ce cycle : omet le bloc sans planter', () async {
      const pays = PaysPedagogique(
        codeIso: 'GN',
        nom: 'Guinée',
        typeSysteme: 'francophone_cfa',
        langueEnseignementPrincipale: 'français',
        signaturesBulletin: {
          'college': {'signataire1': 'Proviseur', 'signataire2': 'Directeur des Études'},
        },
      );

      // isced 3 (lycée) demandé, mais seule la clé "college" est renseignée.
      final octets = await construireBulletinsClassePdf(
        paires: [(bulletin: bulletinAvec({'moyenne_generale': 18}), fiche: fiche, detailMatieres: const [])],
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
        titreClasse: 'Bulletins - 5e A',
        pays: pays,
        isced: 3,
      );

      expect(octets, isNotEmpty);
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });
  });
}
