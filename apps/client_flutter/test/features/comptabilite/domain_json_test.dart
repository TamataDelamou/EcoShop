import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/comptabilite/domain/ecriture_comptable.dart';
import 'package:ecoshop_client/features/comptabilite/domain/enums_comptabilite.dart';
import 'package:ecoshop_client/features/comptabilite/domain/journal.dart';
import 'package:ecoshop_client/features/comptabilite/domain/ligne_balance.dart';
import 'package:ecoshop_client/features/comptabilite/domain/ligne_journal.dart';
import 'package:ecoshop_client/features/comptabilite/domain/mouvement_grand_livre.dart';
import 'package:ecoshop_client/features/comptabilite/domain/plan_comptable.dart';
import 'package:ecoshop_client/features/comptabilite/domain/signaux_ia_comptables.dart';

void main() {
  group('PlanComptable', () {
    test('versJsonEcriture/depuisJsonCache font un aller-retour fidèle', () {
      final compte = PlanComptable(
        id: 'c1',
        etablissementId: 'et1',
        code: '520',
        intitule: 'Banque',
        type: TypeCompte.banque,
      );

      final relu = PlanComptable.depuisJsonCache(compte.versJsonCache());

      expect(relu.code, '520');
      expect(relu.type, TypeCompte.banque);
      expect(relu.libelle, '520 — Banque');
    });
  });

  group('Journal', () {
    test('versJsonEcriture/depuisJsonCache font un aller-retour fidèle', () {
      final journal = Journal(id: 'j1', etablissementId: 'et1', code: 'BQ', intitule: 'Banque', type: TypeJournal.banque);

      final relu = Journal.depuisJsonCache(journal.versJsonCache());

      expect(relu.code, 'BQ');
      expect(relu.type, TypeJournal.banque);
    });
  });

  group('EcritureComptable', () {
    test('versJsonEcriture/depuisJsonEcriture font un aller-retour fidèle', () {
      final ecriture = EcritureComptable(
        id: 'e1',
        etablissementId: 'et1',
        journalId: 'j1',
        dateEcriture: DateTime(2026, 9, 15),
        libelle: 'Scolarité',
        compteDebitId: 'c1',
        compteCreditId: 'c2',
        montant: 500000,
        pieceJustificative: 'FACT-001',
        deviceId: 'dev1',
      );

      final relue = EcritureComptable.depuisJsonEcriture(ecriture.versJsonEcriture());

      expect(relue.compteDebitId, 'c1');
      expect(relue.compteCreditId, 'c2');
      expect(relue.montant, 500000);
      expect(relue.dateEcriture, DateTime(2026, 9, 15));
    });

    test('versJsonEcriture ne contient aucune clé d\'embed (pas de PostgREST join ambigu)', () {
      final ecriture = EcritureComptable(
        id: 'e1',
        etablissementId: 'et1',
        journalId: 'j1',
        dateEcriture: DateTime(2026, 9, 15),
        libelle: 'Scolarité',
        compteDebitId: 'c1',
        compteCreditId: 'c2',
        montant: 500000,
      );

      final cles = ecriture.versJsonEcriture().keys;
      expect(cles.contains('compte_debit'), isFalse);
      expect(cles.contains('compte_credit'), isFalse);
      expect(cles, contains('compte_debit_id'));
      expect(cles, contains('compte_credit_id'));
    });
  });

  group('RPC wrappers', () {
    test('LigneJournal.depuisJson lit les colonnes de journal_comptable', () {
      final ligne = LigneJournal.depuisJson({
        'date_ecriture': '2026-09-15',
        'libelle': 'Scolarité',
        'compte_debit': '520',
        'compte_credit': '701',
        'montant': 500000,
        'piece_justificative': null,
      });

      expect(ligne.compteDebit, '520');
      expect(ligne.montant, 500000);
    });

    test('MouvementGrandLivre.estDebit distingue le sens du mouvement', () {
      final debit = MouvementGrandLivre.depuisJson(
        {'date_ecriture': '2026-09-15', 'libelle': 'x', 'sens': 'debit', 'montant': 100, 'piece_justificative': null},
      );
      final credit = MouvementGrandLivre.depuisJson(
        {'date_ecriture': '2026-09-15', 'libelle': 'x', 'sens': 'credit', 'montant': 100, 'piece_justificative': null},
      );

      expect(debit.estDebit, isTrue);
      expect(credit.estDebit, isFalse);
    });

    test('LigneBalance.depuisJson lit les colonnes de balance_comptable', () {
      final ligne = LigneBalance.depuisJson({
        'compte_id': 'c1',
        'code': '520',
        'intitule': 'Banque',
        'total_debit': 500000,
        'total_credit': 170000,
        'solde_debit': 330000,
        'solde_credit': 0,
      });

      expect(ligne.soldeDebit, 330000);
      expect(ligne.soldeCredit, 0);
    });

    test('Balance.depuisJson lit les colonnes réelles (date_balance, pas annee_scolaire_id)', () {
      final balance = Balance.depuisJson({
        'id': 'b1',
        'etablissement_id': 'et1',
        'compte_id': 'c1',
        'date_balance': '2026-12-31',
        'solde_debit': 330000,
        'solde_credit': 0,
      });

      expect(balance.dateBalance, DateTime(2026, 12, 31));
    });

    test('AnomalieComptable.libelleAnomalie traduit les codes serveur', () {
      final anomalie = AnomalieComptable.depuisJson({
        'ecriture_id': 'e1',
        'date_ecriture': '2026-09-25',
        'libelle': 'Fournitures',
        'montant': 85000,
        'anomalie': 'double_saisie',
      });

      expect(anomalie.libelleAnomalie, 'Double saisie suspectée');
    });
  });
}
