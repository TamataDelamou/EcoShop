/// Actions sensibles (REG-18, partie C) : le code secret (ou l'empreinte) est
/// demandé **à chaque fois**, quel que soit le délai de verrouillage :
/// paiement, validation et verrouillage de notes, écritures et clôtures
/// comptables, encaissements, décisions de l'administration GSG, changement
/// de téléphone.
///
/// Appelé au point d'entrée de chaque opération (dépôt utilisé par les
/// écrans, avant le choix « en ligne / hors connexion ») :
///
/// ```dart
/// await exigerCodeSecret('Enregistrer l’encaissement');
/// ```
///
/// La demande elle-même (feuille du pavé numérique) est branchée par
/// l'application au démarrage (`GardienVerrou`). Sans branchement — tests
/// unitaires des dépôts, mode diagnostic sans Supabase — rien n'est demandé.
/// Le serveur reste la seule autorité sur les droits (RLS inchangées) : ce
/// verrou protège un téléphone laissé sans surveillance.
library;

/// L'utilisateur n'a pas confirmé son code : l'action n'a pas eu lieu.
class ActionSensibleAnnulee implements Exception {
  const ActionSensibleAnnulee(this.motif);

  final String motif;

  @override
  String toString() => 'Action annulée : code secret non confirmé.';
}

typedef DemandeCode = Future<bool> Function(String motif);

abstract final class GardienActionsSensibles {
  static DemandeCode? _demande;

  static void brancher(DemandeCode? demande) => _demande = demande;

  static bool get estBranche => _demande != null;

  static Future<void> exiger(String motif) async {
    final demande = _demande;
    if (demande == null) return;
    if (!await demande(motif)) throw ActionSensibleAnnulee(motif);
  }
}

/// Raccourci pour les dépôts.
Future<void> exigerCodeSecret(String motif) => GardienActionsSensibles.exiger(motif);

/// Exécute [action] après confirmation du code. À placer **autour** de la
/// traduction des erreurs du dépôt : [ActionSensibleAnnulee] doit arriver
/// telle quelle à l'écran.
Future<T> avecCode<T>(String motif, Future<T> Function() action) async {
  await exigerCodeSecret(motif);
  return action();
}
