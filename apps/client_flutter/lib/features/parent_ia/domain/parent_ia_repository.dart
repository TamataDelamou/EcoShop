import 'parent_ia_config.dart';
import 'restriction_parent_ia.dart';

/// Erreur métier de PARENT IA, à code stable.
class ErreurParentIa implements Exception {
  const ErreurParentIa(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurParentIa($code)';
}

/// Port PARENT IA (M16, sous-livrable 4/7) — déclaration manuelle
/// uniquement pour cette passe (voir [declarerUsage]). Le client n'écrit
/// JAMAIS directement `parent_ia_config`/`parent_ia_historique` (aucune
/// policy d'écriture cliente n'existe sur ces tables) et n'appelle JAMAIS
/// l'API Anthropic directement (Edge Function `analyser_usage_parent_ia`,
/// seul point d'entrée).
abstract interface class ParentIaRepository {
  /// Configuration actuelle pour une fiche (élève propriétaire ou parent
  /// confirmé — jamais le personnel de l'établissement, divergence
  /// délibérée par rapport au reste de l'app).
  Future<ParentIaConfig> configuration(String ficheEleveId);

  /// Historique des restrictions, du plus récent au plus ancien.
  Future<List<RestrictionParentIa>> historique(String ficheEleveId);

  /// Active PARENT IA — réservé à l'élève propriétaire de la fiche. Pose un
  /// verrou de 30 jours calculé côté serveur, infalsifiable.
  Future<ParentIaConfig> activer({
    required String ficheEleveId,
    required bool consentement,
  });

  /// Tentative de désactivation — refusée tant que le verrou n'est pas
  /// écoulé (`ErreurParentIa` avec un code `PARENT_IA_VERROUILLE ...`).
  Future<ParentIaConfig> desactiver(String ficheEleveId);

  /// Déclare un usage (formulaire manuel : app principale + minutes) et
  /// déclenche l'analyse IA — renvoie si une restriction a été notifiée.
  Future<bool> declarerUsage({
    required String ficheEleveId,
    required String appPrincipale,
    required int minutes,
  });
}
