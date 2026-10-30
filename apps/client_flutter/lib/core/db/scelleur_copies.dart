/// Scellement des copies gardées sur l'appareil (REG-35 — décision sur la
/// déconnexion, 2026-10-30).
///
/// Les copies d'écran d'un compte sont chiffrées avec la clé de ce compte :
/// elles restent sur le téléphone à la déconnexion (le même compte les
/// retrouve sans tout retélécharger) mais sont illisibles pour tout autre
/// compte du même appareil. Modèle de CommCare (données chiffrées par
/// utilisateur, gardées après la déconnexion) et de la file d'envoi REG-18.
abstract interface class ScelleurCopies {
  /// Texte à enregistrer pour [clair] dans [domaine] ; null : ne rien
  /// enregistrer (chiffrement impossible — une copie n'est jamais gardée en
  /// clair à la place).
  Future<String?> sceller(String domaine, String clair);

  /// Texte lisible de [stocke], ou null s'il n'est pas lisible par le compte
  /// connecté (copie d'un autre compte, ou ancienne copie en clair d'avant
  /// le scellement).
  Future<String?> ouvrir(String domaine, String stocke);
}
