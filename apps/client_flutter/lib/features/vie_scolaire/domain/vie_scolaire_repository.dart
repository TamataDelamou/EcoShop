import 'alerte_decrochage.dart';
import 'evenement_scolaire.dart';
import 'presence.dart';
import 'retard.dart';
import 'sanction.dart';

/// Erreur métier de Vie scolaire, à code stable.
class ErreurVieScolaire implements Exception {
  const ErreurVieScolaire(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurVieScolaire($code)';
}

/// Port du module Absences & Vie scolaire (M7).
///
/// Deux règles d'or (contrat M07 §5, éthique IA) :
/// - `generer_alertes_decrochage` est **`service_role` uniquement** — ce port
///   n'expose donc aucune méthode pour la déclencher depuis le client.
/// - `alertes_decrochage` n'a **aucune policy d'écriture** côté client (RLS
///   ne définit qu'un SELECT) : ce port est délibérément lecture seule pour
///   cette table — marquer une alerte traitée reste une action back-office.
abstract interface class VieScolaireRepository {
  /// Présences d'une classe à une date (grille de pointage enseignant).
  Future<List<Presence>> presencesDeClasse(String classeId, DateTime date);

  /// Historique des présences/absences d'une fiche.
  Future<List<Presence>> presencesDeFiche(String ficheEleveId);

  /// Historique des retards d'une fiche.
  Future<List<Retard>> retardsDeFiche(String ficheEleveId);

  /// Sanctions d'une fiche (visibles : personnel, ou élève/parent concerné).
  Future<List<Sanction>> sanctionsDeFiche(String ficheEleveId);

  /// Alertes décrochage d'une fiche (élève/parent : uniquement transmises).
  Future<List<AlerteDecrochage>> alertesDeFiche(String ficheEleveId);

  /// Alertes décrochage d'un établissement (vue direction/scolarité).
  Future<List<AlerteDecrochage>> alertesEtablissement(String etablissementId);

  /// Calendrier des événements affectant la présence attendue.
  Future<List<EvenementScolaire>> evenementsEtablissement(String etablissementId);

  /// Tableau de bord comportemental descriptif (RPC `analyse_comportement`).
  Future<Map<String, dynamic>> analyseComportement(String ficheEleveId, String anneeScolaireId);

  /// Score de décrochage 0-1 (RPC `calculer_score_decrochage`) — signal, pas
  /// un verdict : toujours présenté avec la mention de validation humaine.
  Future<double> scoreDecrochage(String ficheEleveId, String anneeScolaireId);

  /// Recommandation éducative non punitive (RPC `recommander_sanction_educative`).
  Future<Map<String, dynamic>> recommandationSanction(String ficheEleveId, String anneeScolaireId);

  /// Taux de présence attendu à une date (RPC `predire_presence`).
  Future<double> predirePresence(String etablissementId, DateTime date);

  /// Pointe une présence. Fonctionne hors connexion (file `sync_queue`, LWW),
  /// comme `saisirNote` en M6. Renvoie `true` si synchronisée immédiatement.
  Future<bool> saisirPresence(Presence presence);

  /// Enregistre un retard. Même politique hors-ligne que [saisirPresence].
  Future<bool> saisirRetard(Retard retard);

  /// Propose une sanction (origine humaine ou IA — une origine IA reste
  /// `proposee` tant qu'aucun humain ne l'a validée, contrainte serveur).
  Future<Sanction> proposerSanction(Sanction sanction);

  /// Valide une sanction proposée (humain requis, y compris pour l'IA).
  Future<void> validerSanction(String sanctionId, {required String valideePar});

  /// Change le statut d'une sanction déjà validée (notifiée, exécutée, annulée).
  Future<void> changerStatutSanction(String sanctionId, String statut);
}
