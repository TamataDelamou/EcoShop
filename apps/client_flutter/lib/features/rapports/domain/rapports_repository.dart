import 'anomalie_statistique.dart';
import 'indicateur_cle.dart';
import 'rapport.dart';
import 'recommandation_strategique.dart';

/// Erreur métier de Rapports & Statistiques, à code stable.
class ErreurRapports implements Exception {
  const ErreurRapports(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurRapports($code)';
}

/// Port du module Rapports & Statistiques (M10).
///
/// Consolidation M6×M7×M8×M9 (contrat M10) : indicateurs clés, rapports
/// générés en différé, détection d'anomalies et recommandations
/// stratégiques, toutes réservées au personnel (`est_personnel`) — un
/// parent/élève ne voit que ses propres `rapports` (bulletin, relevé).
abstract interface class RapportsRepository {
  /// Rapports d'une fiche élève (vue parent/élève — bulletin, relevé).
  Future<List<Rapport>> rapportsDeFiche(String ficheEleveId);

  /// Rapports de tout l'établissement (vue personnel).
  Future<List<Rapport>> rapportsEtablissement(String etablissementId);

  /// Dépose une demande de génération. Fonctionne hors connexion (file
  /// `sync_queue`) — marque `demandeHorsLigne` conformément au contrat M10 ;
  /// renvoie `true` si synchronisée immédiatement.
  Future<bool> demanderRapport(Rapport rapport);

  /// Indicateurs clés d'un établissement pour une année (personnel).
  Future<List<IndicateurCle>> indicateursEtablissement(String etablissementId, String anneeScolaireId);

  /// Recalcule les 7 indicateurs clés, dont `eleves_a_risque` (M16) (RPC
  /// `consolider_indicateurs_etablissement`).
  Future<int> consoliderIndicateurs(String etablissementId, String anneeScolaireId);

  /// Anomalies statistiques d'un établissement pour une année (personnel).
  Future<List<AnomalieStatistique>> anomaliesEtablissement(String etablissementId, String anneeScolaireId);

  /// Lance la détection d'anomalies (RPC `detecter_anomalies`) — renvoie le
  /// nombre de nouvelles anomalies détectées.
  Future<int> detecterAnomalies(String etablissementId, String anneeScolaireId);

  /// Change le statut d'une anomalie (confirmée/rejetée/traitée) —
  /// `rapports.administrer`, toujours en ligne.
  Future<void> traiterAnomalie(String anomalieId, String statut, {required String traiteePar});

  /// Recommandations stratégiques d'un établissement pour une année (personnel).
  Future<List<RecommandationStrategique>> recommandationsEtablissement(String etablissementId, String anneeScolaireId);

  /// Génère les recommandations pour les classes à risque (RPC
  /// `recommander_actions`) — renvoie le nombre total de recommandations.
  Future<int> genererRecommandations(String etablissementId, String anneeScolaireId);

  /// Valide, rejette ou marque « mise en œuvre » une recommandation —
  /// `rapports.administrer`, toujours en ligne.
  Future<void> statuerRecommandation(String recommandationId, String statut, {required String valideePar});

  /// Score de risque d'une classe (RPC `risque_classe`, IA prédictive).
  Future<Map<String, dynamic>> risqueClasse(String classeId);

  /// Résumé exécutif en langage naturel (RPC `generer_resume_executif`, NLG).
  Future<String> resumeExecutif(String etablissementId, String anneeScolaireId);
}
