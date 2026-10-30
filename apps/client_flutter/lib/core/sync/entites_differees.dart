/// Opérations mises en file par le lot 4 (REG-35) : faites sans réseau,
/// rejouées par `RejeuActionsDifferees` (coquille) au retour du réseau.
///
/// Identifiant d'entrée de file : `<entité>:<id de l'élément>` — une
/// seconde décision sur le même élément, prise avant l'envoi, remplace la
/// première (la dernière intention de l'utilisateur part seule).
abstract final class EntitesDifferees {
  static const evaluationCreation = 'evaluation_creation';
  static const evaluationPublication = 'evaluation_publication';
  static const sanctionProposition = 'sanction_proposition';
  static const sanctionValidation = 'sanction_validation';
  static const sanctionStatut = 'sanction_statut';
  static const congeDecision = 'conge_decision';
  static const inscriptionBoursier = 'inscription_boursier';
  static const progressionStatut = 'progression_statut';
  static const lignePanierSuppression = 'ligne_panier_suppression';

  static const toutes = [
    evaluationCreation,
    evaluationPublication,
    sanctionProposition,
    sanctionValidation,
    sanctionStatut,
    congeDecision,
    inscriptionBoursier,
    progressionStatut,
    lignePanierSuppression,
  ];

  static String identifiant(String entite, String id) => '$entite:$id';
}
