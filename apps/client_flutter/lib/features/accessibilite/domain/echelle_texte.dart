/// Échelle de taille de texte (D4, §34.9) — discrète, pas un curseur continu :
/// un facteur borné et connu à l'avance est plus sûr à vérifier visuellement
/// qu'une plage arbitraire.
enum EchelleTexte {
  petit(0.85, 'Petit'),
  normal(1.0, 'Normal'),
  grand(1.15, 'Grand'),
  tresGrand(1.3, 'Très grand');

  const EchelleTexte(this.facteur, this.libelle);

  /// Multiplicateur appliqué au `textScaler` global de l'application.
  final double facteur;
  final String libelle;

  static EchelleTexte depuisCode(String? code) {
    for (final v in EchelleTexte.values) {
      if (v.name == code) return v;
    }
    return EchelleTexte.normal;
  }
}
