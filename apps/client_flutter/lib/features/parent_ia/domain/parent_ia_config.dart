/// Paramètre PARENT IA (M16, sous-livrable 4/7, cahier §15.3) — projection
/// cliente de `public.parent_ia_config`. Une fois `actif = true`, ce
/// paramètre ne peut plus être désactivé avant `verrouilleJusquau` — verrou
/// posé et vérifié UNIQUEMENT côté serveur (`activer_parent_ia`/
/// `desactiver_parent_ia`, jamais une écriture cliente directe : voir la
/// migration, aucune policy d'écriture n'existe sur cette table).
class ParentIaConfig {
  const ParentIaConfig({
    required this.actif,
    this.dateActivation,
    this.verrouilleJusquau,
    required this.consentementEleve,
  });

  final bool actif;
  final DateTime? dateActivation;
  final DateTime? verrouilleJusquau;
  final bool consentementEleve;

  /// true tant que l'élève ne peut pas désactiver/modifier le paramètre.
  bool get estVerrouille =>
      actif &&
      verrouilleJusquau != null &&
      DateTime.now().isBefore(verrouilleJusquau!);

  int get joursRestantsAvantDeverrouillage {
    if (!estVerrouille) return 0;
    return verrouilleJusquau!.difference(DateTime.now()).inDays + 1;
  }

  factory ParentIaConfig.inactif() =>
      const ParentIaConfig(actif: false, consentementEleve: false);

  factory ParentIaConfig.depuisJson(Map<String, dynamic> json) =>
      ParentIaConfig(
        actif: json['actif'] as bool? ?? false,
        dateActivation: json['date_activation'] == null
            ? null
            : DateTime.parse(json['date_activation'] as String),
        verrouilleJusquau: json['verrouille_jusquau'] == null
            ? null
            : DateTime.parse(json['verrouille_jusquau'] as String),
        consentementEleve: json['consentement_eleve'] as bool? ?? false,
      );
}
