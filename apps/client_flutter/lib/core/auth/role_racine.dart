/// Rôle racine — modèle de rôles à deux niveaux (cahier v4.1, ch. 4).
///
/// Les rôles racine sont les identités de base d'un compte ; les permissions
/// fines au sein d'un établissement passent par les postes déclarés.
enum RoleRacine {
  eleve('eleve'),
  parent('parent'),
  enseignant('enseignant'),
  direction('direction'),
  vendeur('vendeur'),
  fondateurReseau('fondateur_reseau'),
  adminGsg('admin_gsg'),
  adminContenu('admin_contenu');

  const RoleRacine(this.code);

  /// Code tel que stocké dans `profiles.role_racine` et copié dans le JWT.
  final String code;

  /// Seuls Élève et Parent sont auto-inscriptibles (ch. 5.2).
  bool get estAutoInscriptible =>
      this == RoleRacine.eleve || this == RoleRacine.parent;

  /// Rôles plateforme : jamais auto-attribués, attribués par GSG (ch. 4).
  bool get estPlateforme =>
      this == RoleRacine.adminGsg || this == RoleRacine.adminContenu;

  /// Résout un code issu de la base ou du JWT en [RoleRacine].
  static RoleRacine? depuisCode(String? code) {
    for (final role in RoleRacine.values) {
      if (role.code == code) return role;
    }
    return null;
  }
}
