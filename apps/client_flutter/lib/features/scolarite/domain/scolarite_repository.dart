import 'affectation_enseignant.dart';
import 'encaissement_scolarite.dart';
import 'enums_scolarite.dart';
import 'fiche_eleve.dart';
import 'frais_scolarite_config.dart';
import 'inscription.dart';
import 'palier_paiement_config.dart';
import 'relation_parent_eleve.dart';
import 'solde_scolarite.dart';
import 'structure_etablissement.dart';
import 'verifications_reinscription.dart';

/// Erreur métier de la scolarité, à code stable.
class ErreurScolarite implements Exception {
  const ErreurScolarite(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurScolarite($code)';
}

/// Port du module Administration & Scolarité (M5) et de son extension
/// Inscription/Réinscription/Encaissement (M15quater).
///
/// Chaque implémentation doit fonctionner hors connexion en retombant sur le
/// cache local pour les lectures (contrat M05 — annuaires et fiches liées) ;
/// les écritures restent soumises aux permissions RLS et exigent le réseau
/// (comme [lierEnfant] déjà en M5 — aucune de ces écritures n'a de sens en
/// file d'attente offline : un matricule généré serveur, un solde ou une
/// détection de doublon ne peuvent pas être approximés localement).
abstract interface class ScolariteRepository {
  /// Annuaire (unités, années, classes, périodes) d'un établissement, pour
  /// l'année scolaire [anneeScolaireId] ou, à défaut, l'année courante.
  Future<StructureEtablissement> structureEtablissement(
    String etablissementId, {
    String? anneeScolaireId,
  });

  /// Élèves inscrits dans une classe (fiche embarquée).
  Future<List<Inscription>> inscriptionsDeClasse(String classeId);

  /// Historique des inscriptions d'une fiche (classe embarquée), la plus
  /// récente d'abord — sert à afficher la classe actuelle d'un enfant/élève.
  Future<List<Inscription>> inscriptionsDeFiche(String ficheEleveId);

  /// Fiche de l'utilisateur connecté (élève lié à sa propre fiche).
  Future<FicheEleve?> maFiche();

  /// Enseignants et matières affectés à une classe (noms embarqués).
  Future<List<AffectationEnseignant>> affectationsDeClasse(String classeId);

  /// Classes et matières affectées à l'enseignant connecté.
  Future<List<AffectationEnseignant>> mesAffectations();

  /// Enfants liés au parent connecté (sélecteur d'enfant), fiche embarquée.
  Future<List<RelationParentEleve>> mesEnfants();

  /// Fiche d'un élève donné (rafraîchissement ponctuel).
  Future<FicheEleve?> ficheEleve(String ficheId);

  /// Lie le parent connecté à un nouvel enfant (RPC `lier_parent_a_fiche`,
  /// double facteur matricule + date de naissance). Renvoie l'id de la relation.
  Future<String> lierEnfant({
    required String matricule,
    required DateTime dateNaissance,
    TypeRelationParentale type = TypeRelationParentale.parent,
  });

  // --- M15quater : inscription, réinscription, doublon -----------------

  /// Recherche une fiche par matricule (point d'entrée de la réinscription —
  /// équivalent du matricule au lieu du téléphone parent utilisé côté
  /// source, cf. rapport d'écart M15quater).
  Future<FicheEleve?> ficheParMatricule({
    required String etablissementId,
    required String matricule,
  });

  /// Crée un nouvel élève et sa première inscription (RPC
  /// `creer_inscription_nouvel_eleve` — matricule généré serveur). Renvoie
  /// l'id de la fiche élève créée.
  Future<String> creerInscriptionNouvelEleve({
    required String etablissementId,
    required String nom,
    required String prenom,
    required DateTime dateNaissance,
    required String classeId,
    required String anneeScolaireId,
    String? sexe,
  });

  /// Signal informatif (pas un blocage) : un élève de mêmes nom/prénom/date
  /// de naissance est-il déjà inscrit actif quelque part (RPC
  /// `verifier_doublon_eleve`) ?
  Future<bool> verifierDoublonEleve({
    required String nom,
    required String prenom,
    required DateTime dateNaissance,
  });

  /// Vérifications informatives avant réinscription (RPC
  /// `verifications_reinscription`) : impayé, sanction active, statut
  /// boursier de l'année précédente.
  Future<VerificationsReinscription> verificationsReinscription({
    required String ficheEleveId,
    required String anneePrecedenteId,
  });

  /// Réinscrit une fiche existante dans une classe pour une année scolaire
  /// (RPC `creer_reinscription`). Renvoie l'id de la nouvelle inscription.
  Future<String> creerReinscription({
    required String ficheEleveId,
    required String classeId,
    required String anneeScolaireId,
  });

  /// Définit le statut boursier d'une inscription (annuel — jamais
  /// permanent). `boursier_modifie_par`/`_le` sont posés par le serveur.
  Future<void> definirStatutBoursier({
    required String inscriptionId,
    required bool boursier,
  });

  /// Met à jour les champs administratifs complémentaires du dossier élève
  /// (filiation, quartier, contact d'urgence, redoublement, n° de classe).
  Future<void> mettreAJourFicheAdmin(FicheEleve fiche);

  // --- M15quater : paramètres financiers de l'établissement -------------

  Future<List<FraisScolariteConfig>> fraisScolariteConfig({
    required String etablissementId,
    required String anneeScolaireId,
  });

  Future<void> enregistrerFraisScolariteConfig(FraisScolariteConfig config);

  Future<List<PalierPaiementConfig>> paliersPaiementConfig({
    required String etablissementId,
    required String anneeScolaireId,
  });

  Future<void> enregistrerPalierPaiement(PalierPaiementConfig palier);

  // --- M15quater : encaissement de scolarité -----------------------------

  /// Solde calculé côté serveur (tarif applicable − encaissements validés).
  Future<SoldeScolarite> soldeScolarite(String inscriptionId);

  /// Historique des encaissements d'une inscription, le plus récent d'abord.
  Future<List<EncaissementScolarite>> encaissementsDeInscription(String inscriptionId);

  /// Encaissements récents d'un établissement, tous élèves confondus (cahier
  /// journal des encaissements), le plus récent d'abord.
  Future<List<EncaissementScolarite>> encaissementsRecents(
    String etablissementId, {
    int limite = 100,
  });

  /// Enregistre un encaissement. `saisiPar` est ignoré : le serveur impose
  /// toujours `auth.uid()` (trigger `encaissements_verifie_tenant`).
  Future<EncaissementScolarite> enregistrerEncaissement(EncaissementScolarite encaissement);

  /// Annule un encaissement (jamais de suppression physique) — motif requis.
  Future<void> annulerEncaissement({
    required String encaissementId,
    required String motif,
  });
}
