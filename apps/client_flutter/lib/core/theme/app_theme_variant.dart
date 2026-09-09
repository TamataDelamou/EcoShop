/// Variantes visuelles d'établissement, alignées sur les 4 familles du
/// référentiel pédagogique CEDEAO (`public.type_systeme_educatif`, M4).
///
/// Une variante = une charte graphique complète (couleurs clair + sombre).
/// `arabophoneMixte` n'a pas encore de charte dédiée : les établissements de
/// cette famille utilisent [francophoneCfa] par repli, en attendant un futur
/// module (cf. rapport d'écart M15bis) — ce n'est pas un oubli silencieux,
/// c'est une conséquence assumée du périmètre de ce module.
enum AppThemeVariant {
  francophoneCfa('francophone_cfa'),
  anglophoneWaec('anglophone_waec'),
  lusophone('lusophone');

  const AppThemeVariant(this.codeSystemeEducatif);

  /// Correspond à `public.type_systeme_educatif` (contrat M04).
  final String codeSystemeEducatif;

  /// Résout la variante à partir du code `type_systeme` d'un pays pédagogique.
  ///
  /// Repli sur [francophoneCfa] pour `arabophone_mixte` (pas encore de charte
  /// dédiée) et pour tout code inconnu ou absent (établissement sans pays
  /// renseigné, mode diagnostic hors-ligne sans référentiel en cache).
  static AppThemeVariant depuisCodeSysteme(String? codeSysteme) {
    for (final variante in AppThemeVariant.values) {
      if (variante.codeSystemeEducatif == codeSysteme) return variante;
    }
    return AppThemeVariant.francophoneCfa;
  }
}
