/// Variantes visuelles d'établissement, alignées sur les 4 familles du
/// référentiel pédagogique CEDEAO (`public.type_systeme_educatif`, M4).
///
/// Une variante = une charte graphique complète (couleurs clair + sombre).
/// Les 4 familles ont chacune leur charte depuis l'ajout de
/// [arabophoneMixte] (registre REG-07, 2026-10-17).
enum AppThemeVariant {
  francophoneCfa('francophone_cfa'),
  anglophoneWaec('anglophone_waec'),
  lusophone('lusophone'),
  arabophoneMixte('arabophone_mixte');

  const AppThemeVariant(this.codeSystemeEducatif);

  /// Correspond à `public.type_systeme_educatif` (contrat M04).
  final String codeSystemeEducatif;

  /// Résout la variante à partir du code `type_systeme` d'un pays pédagogique.
  ///
  /// Repli sur [francophoneCfa] pour tout code inconnu ou absent
  /// (établissement sans pays renseigné, mode diagnostic hors-ligne sans
  /// référentiel en cache).
  static AppThemeVariant depuisCodeSysteme(String? codeSysteme) {
    for (final variante in AppThemeVariant.values) {
      if (variante.codeSystemeEducatif == codeSysteme) return variante;
    }
    return AppThemeVariant.francophoneCfa;
  }
}
