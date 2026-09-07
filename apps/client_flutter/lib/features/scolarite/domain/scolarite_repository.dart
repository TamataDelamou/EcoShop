import 'affectation_enseignant.dart';
import 'enums_scolarite.dart';
import 'fiche_eleve.dart';
import 'inscription.dart';
import 'relation_parent_eleve.dart';
import 'structure_etablissement.dart';

/// Erreur métier de la scolarité, à code stable.
class ErreurScolarite implements Exception {
  const ErreurScolarite(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurScolarite($code)';
}

/// Port du module Administration & Scolarité (M5).
///
/// Chaque implémentation doit fonctionner hors connexion en retombant sur le
/// cache local pour les lectures (contrat M05 — annuaires et fiches liées) ;
/// les écritures restent soumises aux permissions RLS et exigent le réseau.
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
}
