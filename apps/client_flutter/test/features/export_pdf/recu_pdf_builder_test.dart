import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/comptabilite/domain/ecriture_comptable.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/export_pdf/data/recu_pdf_builder.dart';

void main() {
  final etablissement = const Etablissement(
    id: 'e1',
    nom: 'Groupe Scolaire Test',
    slug: 'gs-test',
    ville: 'Conakry',
    deviseCode: 'GNF',
  );

  final ecriture = EcritureComptable(
    id: 'ec1',
    etablissementId: 'e1',
    journalId: 'j1',
    dateEcriture: DateTime(2026, 10, 6),
    libelle: 'Encaissement scolarité - Mory CAMARA',
    compteDebitId: 'compte-caisse',
    compteCreditId: 'compte-produits',
    montant: 250000,
  );

  for (final variante in AppThemeVariant.values) {
    test('génère un PDF valide (magic bytes %PDF) pour $variante', () async {
      final octets = await construireRecuPdf(
        ecriture: ecriture,
        libelleCompteDebit: 'Caisse',
        libelleCompteCredit: 'Produits scolarité',
        libelleJournal: 'Journal de caisse',
        etablissement: etablissement,
        variante: variante,
      );

      expect(octets, isNotEmpty);
      expect(octets.length, greaterThan(500));
      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
    });
  }

  test('signale visuellement une écriture saisie hors ligne sans faire échouer la génération', () async {
    final ecritureHorsLigne = EcritureComptable(
      id: 'ec2',
      etablissementId: 'e1',
      journalId: 'j1',
      dateEcriture: DateTime(2026, 10, 7),
      libelle: 'Encaissement (hors ligne)',
      compteDebitId: 'compte-caisse',
      compteCreditId: 'compte-produits',
      montant: 50000,
      saisiHorsLigne: true,
      deviceId: 'device-1',
      clientTs: DateTime(2026, 10, 7, 9, 30),
    );

    final octets = await construireRecuPdf(
      ecriture: ecritureHorsLigne,
      libelleCompteDebit: 'Caisse',
      libelleCompteCredit: 'Produits scolarité',
      libelleJournal: 'Journal de caisse',
      etablissement: etablissement,
      variante: AppThemeVariant.francophoneCfa,
    );

    expect(octets, isNotEmpty);
    expect(String.fromCharCodes(octets.take(5)), '%PDF-');
  });
}
