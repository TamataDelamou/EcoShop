/// Délais de verrouillage par rôle (REG-18, décision du 2026-10-23).
///
/// Le délai court dès que l'application passe en arrière-plan ou que l'écran
/// s'éteint. Un compte qui cumule plusieurs rôles (rôle principal + rôles
/// dans ses établissements) prend le délai **le plus court**. Le code reste
/// demandé à chaque action sensible, quel que soit le délai.
///
/// Seul endroit où ces valeurs sont écrites.
abstract final class DelaisVerrouillage {
  static const Map<String, Duration> parRole = {
    // Accès à toutes les écoles et aux décisions de la plateforme.
    'admin_gsg': Duration(minutes: 2),
    'admin_contenu': Duration(minutes: 2),
    // Encaissements, comptabilité, personnel, toute l'école ou le réseau.
    'direction': Duration(minutes: 5),
    'fondateur_reseau': Duration(minutes: 5),
    // Ventes et argent.
    'vendeur': Duration(minutes: 5),
    // Notes et absences d'une classe ; utilisé en cours.
    'enseignant': Duration(minutes: 15),
    // Données de ses enfants ; paiements protégés à part.
    'parent': Duration(minutes: 30),
    // Données d'un mineur ; téléphone souvent partagé en famille.
    'eleve': Duration(minutes: 30),
  };

  /// Rôle inconnu (poste administratif d'une école : comptable,
  /// secrétariat…) : traité comme le personnel administratif.
  static const parDefaut = Duration(minutes: 5);

  static Duration pour(Iterable<String> roles) {
    Duration? plusCourt;
    for (final role in roles) {
      final delai = parRole[role] ?? parDefaut;
      if (plusCourt == null || delai < plusCourt) plusCourt = delai;
    }
    return plusCourt ?? parDefaut;
  }

  /// Personnel et administration : captures d'écran bloquées sur Android
  /// antérieur à 13 (décision du 2026-10-23) ; parents et élèves non.
  static bool protegerCaptures(Iterable<String> roles) => roles.any((r) => r != 'parent' && r != 'eleve');
}
