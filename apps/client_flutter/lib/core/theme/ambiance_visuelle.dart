/// Ambiance visuelle choisie par l'utilisateur (préférence personnelle,
/// mémorisée sur l'appareil). Par défaut, l'application suit la charte de
/// l'établissement ([etablissement]) — couleur et logo propres à l'école
/// compris. Les autres ambiances sont un confort personnel : elles ne
/// changent ni les documents imprimés ni ce que voient les autres comptes.
///
/// Le contraste élevé (accessibilité, D4) reste toujours prioritaire.
enum AmbianceVisuelle {
  etablissement('etablissement', "Charte de l'établissement", 'Couleurs et logo de votre école'),
  ocean('ocean', 'Océan', 'Bleus profonds et corail, reposant'),
  savane('savane', 'Savane', 'Ocres chauds et vert, lumineux'),
  graphite('graphite', 'Graphite', 'Gris sobres, sans distraction');

  const AmbianceVisuelle(this.code, this.libelle, this.description);

  /// Code persisté localement (jamais en base).
  final String code;
  final String libelle;
  final String description;

  static AmbianceVisuelle depuisCode(String? code) => AmbianceVisuelle.values.firstWhere(
        (a) => a.code == code,
        orElse: () => AmbianceVisuelle.etablissement,
      );
}
