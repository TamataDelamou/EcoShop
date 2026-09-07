import 'charge_travail.dart';
import 'conflit_emploi.dart';
import 'emploi_du_temps.dart';
import 'evenement_agenda.dart';
import 'progression_pedagogique.dart';
import 'salle.dart';

/// Erreur métier de Planification & Agenda, à code stable.
class ErreurPlanification implements Exception {
  const ErreurPlanification(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurPlanification($code)';
}

/// Port du module Planification & Agenda (M11).
///
/// `emplois_du_temps`, `evenements_agenda` et `progression_pedagogique`
/// portent un facteur Last-Write-Wins (`modifie_le`/`device_id`, contrat
/// M11 §5) : leurs écritures suivent la même politique hors-ligne que les
/// présences (M7) via `sync_queue`. `salles` n'a pas de facteur LWW — sa
/// gestion reste une action de bureau, toujours en ligne.
abstract interface class PlanificationRepository {
  /// Salles de l'établissement.
  Future<List<Salle>> sallesEtablissement(String etablissementId);

  /// Emploi du temps d'une classe (vue élève/parent/personnel).
  Future<List<EmploiDuTemps>> emploisDeClasse(String classeId);

  /// Emploi du temps d'un enseignant, toutes classes confondues.
  Future<List<EmploiDuTemps>> emploisDeEnseignant(
    String enseignantProfileId,
    String etablissementId,
    String anneeScolaireId,
  );

  /// Occupation d'une salle sur une année (détection visuelle de conflits).
  Future<List<EmploiDuTemps>> emploisDeSalle(String salleId, String anneeScolaireId);

  /// Crée, modifie ou reporte une séance. Fonctionne hors connexion (file
  /// `sync_queue`) ; renvoie `true` si synchronisée immédiatement.
  Future<bool> enregistrerSeance(EmploiDuTemps emploi);

  /// Événements d'agenda de tout l'établissement (vue personnel).
  Future<List<EvenementAgenda>> evenementsEtablissement(String etablissementId, String anneeScolaireId);

  /// Événements d'agenda d'une classe (vue élève/parent).
  Future<List<EvenementAgenda>> evenementsDeClasse(String classeId, String anneeScolaireId);

  /// Crée ou modifie un événement d'agenda. Même politique hors-ligne que
  /// [enregistrerSeance].
  Future<bool> enregistrerEvenement(EvenementAgenda evenement);

  /// Progression pédagogique d'une classe (vue personnel uniquement — RLS).
  Future<List<ProgressionPedagogique>> progressionDeClasse(String classeId, String anneeScolaireId);

  /// Crée ou modifie une séance de progression. Même politique hors-ligne
  /// que [enregistrerSeance].
  Future<bool> enregistrerProgression(ProgressionPedagogique progression);

  /// Accepte ou rejette une proposition de rattrapage IA (`statut` cible :
  /// `planifiee` ou `annulee`) — action de bureau, toujours en ligne.
  Future<void> changerStatutProgression(String progressionId, String statut);

  /// Propose des séances de rattrapage pour les classes en difficulté (RPC
  /// `recommander_seances`, IA prescriptive) — renvoie le nombre de
  /// propositions actives.
  Future<int> recommanderSeances(String etablissementId, String anneeScolaireId);

  /// Suggère le premier créneau libre commun (RPC `suggerer_placement_seance`,
  /// CSP glouton) — `null` si aucun créneau ne convient.
  Future<Map<String, dynamic>?> suggererPlacement({
    required String etablissementId,
    required String anneeScolaireId,
    required String enseignantProfileId,
    required String classeId,
    required String salleId,
  });

  /// Détecte les chevauchements horaires (RPC `detecter_conflits_emploi`).
  Future<List<ConflitEmploi>> detecterConflits(String etablissementId, String anneeScolaireId);

  /// Charge horaire d'un enseignant (RPC `charger_travail_enseignant`).
  Future<ChargeTravailEnseignant> chargeEnseignant(
    String etablissementId,
    String anneeScolaireId,
    String enseignantProfileId,
  );

  /// Charge horaire d'une classe (RPC `charger_travail_eleve`).
  Future<ChargeTravailEleve> chargeEleve(String classeId);
}
