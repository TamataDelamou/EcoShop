import 'ecriture_comptable.dart';
import 'journal.dart';
import 'ligne_balance.dart';
import 'ligne_journal.dart';
import 'mouvement_grand_livre.dart';
import 'plan_comptable.dart';
import 'signaux_ia_comptables.dart';

/// Erreur métier ou réseau du port [ComptabiliteRepository]. [code] porte
/// soit un code de contrainte serveur authentique (ex.
/// `ECRITURE_TENANT_INCOHERENT`, `ECRITURE_COMPTES_IDENTIQUES`,
/// `PLAN_COMPTABLE_PARENT_INCOHERENT`), soit `ERREUR_RESEAU` en cas de panne.
class ErreurComptabilite implements Exception {
  const ErreurComptabilite(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurComptabilite($code${detail != null ? ': $detail' : ''})';
}

/// Port Comptabilité sans OHADA (M14) — plan comptable ouvert, journaux,
/// écritures en partie double, documents (journal, grand livre, balance) et
/// signaux IA de supervision. Réservé direction/finance côté serveur
/// (`est_comptable`/`est_comptable_ecriture`) ; gating client purement
/// ergonomique, la RLS reste l'unique frontière de sécurité.
abstract interface class ComptabiliteRepository {
  // ---------------------------------------------------------------------
  // Configuration — plan comptable & journaux, en ligne uniquement.
  // ---------------------------------------------------------------------
  Future<List<PlanComptable>> planComptable(String etablissementId);
  Future<bool> enregistrerCompte(PlanComptable compte);
  Future<List<Journal>> journaux(String etablissementId);
  Future<bool> enregistrerJournal(Journal journal);

  // ---------------------------------------------------------------------
  // Écritures — partie double, tolérant hors-ligne (LWW device_id/client_ts).
  // ---------------------------------------------------------------------
  Future<List<EcritureComptable>> ecrituresRecentes(String etablissementId, {int limite = 100});
  Future<bool> enregistrerEcriture(EcritureComptable ecriture);

  // ---------------------------------------------------------------------
  // Documents comptables — RPC en ligne uniquement (agrégats non cachés).
  // ---------------------------------------------------------------------
  Future<List<LigneJournal>> journalComptable(
    String etablissementId,
    String journalId,
    DateTime debut,
    DateTime fin,
  );
  Future<List<MouvementGrandLivre>> grandLivre(
    String etablissementId,
    String compteId,
    DateTime debut,
    DateTime fin,
  );
  Future<List<LigneBalance>> balanceComptable(String etablissementId, DateTime date);
  Future<List<Balance>> genererBalance(String etablissementId, DateTime date);

  // ---------------------------------------------------------------------
  // IA de supervision — signaux descriptifs, jamais d'écriture automatique.
  // ---------------------------------------------------------------------
  Future<List<AnomalieComptable>> detecterAnomalies(String etablissementId);
  Future<List<ProjectionTresorerie>> predireTresorerie(String etablissementId, {int jours = 30});
  Future<List<EcritureRecommandee>> recommanderEcritures(String etablissementId);
  Future<List<TendanceMensuelle>> analyserTendances(String etablissementId, {int mois = 12});
}
