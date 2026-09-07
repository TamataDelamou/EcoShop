import 'absence_personnel.dart';
import 'bulletin_paie.dart';
import 'conge.dart';
import 'contrat.dart';
import 'effectif_categorie.dart';
import 'employe.dart';
import 'recommandation_formation.dart';
import 'remplacement_suggere.dart';

/// Erreur métier de RH & Personnel, à code stable.
class ErreurRh implements Exception {
  const ErreurRh(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurRh($code)';
}

/// Port du module RH & Personnel (M8).
///
/// Deux séparations volontaires, cohérentes avec la RLS serveur (contrat
/// M08) :
/// - Les fiches employé/contrat et la validation des congés sont des actions
///   de bureau : toujours en ligne, jamais mises en file (`sync_queue`).
/// - Les demandes de congé (côté employé) et le pointage d'absence (côté RH)
///   sont des saisies de terrain : elles suivent la même politique
///   hors-ligne que les présences/retards de M7.
/// - `paie_bulletins` est **lecture seule** côté client en M8 (établissement
///   des bulletins reporté à M14) : ce port n'expose donc aucune méthode
///   d'écriture pour cette entité.
abstract interface class RhRepository {
  /// Annuaire du personnel d'un établissement (vue RH/direction — RLS ne
  /// renvoie que le dossier de l'appelant pour un profil non-RH).
  Future<List<Employe>> employesEtablissement(String etablissementId);

  /// Dossier de l'employé lié au compte connecté (auto-consultation).
  Future<Employe?> employeParProfil(String profileId);

  /// Fiche employé par identifiant.
  Future<Employe?> employe(String employeId);

  /// Historique des contrats d'un employé.
  Future<List<Contrat>> contratsDeEmploye(String employeId);

  /// Congés d'un employé (demandes, historique).
  Future<List<Conge>> congesDeEmploye(String employeId);

  /// Absences pointées d'un employé.
  Future<List<AbsencePersonnel>> absencesDeEmploye(String employeId);

  /// Bulletins de paie d'un employé (consultation, M14 prépare l'écriture).
  Future<List<BulletinPaie>> bulletinsDeEmploye(String employeId);

  /// Charge horaire hebdomadaire (RPC `charge_horaire`, affectations M5).
  Future<int> chargeHoraire(String employeId);

  /// Tableau de bord effectifs (RPC `analyser_effectifs`, IA descriptive).
  Future<List<EffectifCategorie>> analyserEffectifs(String etablissementId);

  /// Score de risque de turn-over 0-1 (RPC `calculer_score_turnover`, IA
  /// prédictive) — signal, pas un verdict.
  Future<double> scoreTurnover(String employeId);

  /// Recommandation de formation (RPC `recommander_formation`, IA
  /// prescriptive).
  Future<List<RecommandationFormation>> recommanderFormation(String employeId, String anneeScolaireId);

  /// Suggestions de remplacement pour les enseignants absents à une date
  /// (RPC `optimiser_remplacements`, IA prescriptive).
  Future<List<RemplacementSuggere>> optimiserRemplacements(String etablissementId, DateTime date);

  /// Crée ou met à jour un dossier employé (RH uniquement, toujours en ligne).
  Future<void> creerOuModifierEmploye(Employe employe);

  /// Crée un contrat (RH uniquement, toujours en ligne).
  Future<Contrat> creerContrat(Contrat contrat);

  /// Dépose une demande de congé. Fonctionne hors connexion (file
  /// `sync_queue`, comme `saisirPresence` en M7). Renvoie `true` si
  /// synchronisée immédiatement.
  Future<bool> demanderConge(Conge conge);

  /// Valide ou refuse une demande de congé (RH uniquement, toujours en
  /// ligne — le trigger serveur l'impose de toute façon).
  Future<void> validerConge(String congeId, {required String statut, required String valideePar});

  /// Pointe une absence de personnel. Même politique hors-ligne que
  /// [demanderConge].
  Future<bool> pointerAbsence(AbsencePersonnel absence);
}
