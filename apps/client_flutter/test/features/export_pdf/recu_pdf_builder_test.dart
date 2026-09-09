import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/export_pdf/data/recu_pdf_builder.dart';
import 'package:ecoshop_client/features/scolarite/domain/encaissement_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/enums_financier_scolaire.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';

/// Vérifie que le reçu PDF (M15quater) est bien adossé à `EncaissementScolarite`
/// — l'entité dédiée qui lie explicitement `ficheEleveId`/`inscriptionId` —
/// et non plus à `EcritureComptable` (version initiale de M15ter, retirée ;
/// voir `docs/contrats/M15ter_export_pdf.md` §7).
void main() {
  final etablissement = const Etablissement(
    id: 'e1',
    nom: 'Groupe Scolaire Test',
    slug: 'gs-test',
    ville: 'Conakry',
    deviseCode: 'GNF',
  );

  final fiche = FicheEleve(
    id: 'f1',
    etablissementId: 'e1',
    matricule: 'GS-00012',
    nom: 'CAMARA',
    prenom: 'Mory',
    dateNaissance: DateTime(2013, 4, 12),
  );

  EncaissementScolarite encaissementTest({StatutEncaissement statut = StatutEncaissement.valide}) =>
      EncaissementScolarite(
        id: 'enc1',
        etablissementId: 'e1',
        ficheEleveId: fiche.id,
        inscriptionId: 'i1',
        montant: 250000,
        datePaiement: DateTime(2026, 10, 6),
        saisiPar: 'p-direction',
        typeFrais: TypeFraisScolaire.scolarite,
        moyenPaiement: MoyenPaiement.mobileMoney,
        referencePaiement: 'TXN-42',
        statut: statut,
      );

  for (final variante in AppThemeVariant.values) {
    test('génère un PDF valide (magic bytes %PDF) pour $variante, lié à l\'élève et à l\'encaissement', () async {
      final octets = await construireRecuPdf(
        encaissement: encaissementTest(),
        fiche: fiche,
        etablissement: etablissement,
        variante: variante,
      );

      expect(octets, isNotEmpty);
      expect(octets.length, greaterThan(500));
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });
  }

  test(
      'chaîne complète : ligne "serveur" (JSON snake_case identique à une '
      'réponse Postgres réelle) -> depuisJson -> construireRecuPdf, sans '
      'objet Dart construit à la main dans le chemin testé', () async {
    // Simule exactement ce que renverrait `encaissements_scolarite` (colonnes
    // de la migration 20260906001501) et `fiches_eleves` après un INSERT
    // réel côté serveur — reproduit la forme des données, pas un objet Dart
    // pré-fabriqué, pour vérifier le chemin réellement emprunté par
    // `_exporterRecu()` (dépendance : depuisJson, pas un constructeur direct).
    final ligneServeurEncaissement = <String, dynamic>{
      'id': 'enc-server-1',
      'etablissement_id': 'e1',
      'fiche_eleve_id': 'f1',
      'inscription_id': 'i1',
      'type_frais': 'scolarite',
      'montant': 400000,
      'moyen_paiement': 'mobile_money',
      'reference_paiement': 'TXN-SERVEUR-77',
      'date_paiement': '2026-10-06',
      'saisi_par': 'p-direction-server',
      'statut': 'valide',
      'motif_annulation': null,
      'annule_par': null,
      'annule_le': null,
      'created_at': '2026-10-06T09:00:00.000Z',
    };
    final ligneServeurFiche = <String, dynamic>{
      'id': 'f1',
      'etablissement_id': 'e1',
      'matricule': 'GS-00099',
      'nom': 'DIALLO',
      'prenom': 'Fatoumata',
      'date_naissance': '2012-06-01',
    };

    final encaissement = EncaissementScolarite.depuisJson(ligneServeurEncaissement);
    final ficheServeur = FicheEleve.depuisJson(ligneServeurFiche);

    // La donnée qui a traversé le JSON n'a pas été altérée en chemin.
    expect(encaissement.referencePaiement, 'TXN-SERVEUR-77');
    expect(encaissement.saisiPar, 'p-direction-server');
    expect(ficheServeur.matricule, 'GS-00099');

    final octets = await construireRecuPdf(
      encaissement: encaissement,
      fiche: ficheServeur,
      etablissement: etablissement,
      variante: AppThemeVariant.francophoneCfa,
    );

    expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    expect(octets.length, greaterThan(500));
  });

  test('fonctionne aussi pour un encaissement sans référence de paiement', () async {
    final encaissement = EncaissementScolarite(
      id: 'enc2',
      etablissementId: 'e1',
      ficheEleveId: fiche.id,
      inscriptionId: 'i1',
      montant: 50000,
      datePaiement: DateTime(2026, 10, 7),
      saisiPar: 'p-direction',
      moyenPaiement: MoyenPaiement.especes,
    );

    final octets = await construireRecuPdf(
      encaissement: encaissement,
      fiche: fiche,
      etablissement: etablissement,
      variante: AppThemeVariant.francophoneCfa,
    );

    expect(octets, isNotEmpty);
    expect(String.fromCharCodes(octets.take(5)), '%PDF-');
  });
}
