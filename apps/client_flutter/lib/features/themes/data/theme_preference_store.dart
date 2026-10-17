import 'package:flutter/material.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/theme/ambiance_visuelle.dart';

/// Persistance locale de la préférence d'apparence (clair/sombre/système).
///
/// Choix hors-ligne prioritaire : un réglage d'affichage ne doit jamais
/// attendre un aller-retour réseau. Réutilise le [CacheDocumentStore]
/// générique (Drift) déjà partagé par les modules M5+ plutôt que d'ajouter une
/// dépendance `shared_preferences` pour un seul champ.
class ThemePreferenceStore {
  ThemePreferenceStore(this._store);

  final CacheDocumentStore _store;

  static const _type = 'apparence';
  static const _cle = 'mode';

  Future<ThemeMode> lire() async {
    final document = await _store.lireDocument(_type, _cle);
    final valeur = document?['mode'] as String?;
    return switch (valeur) {
      'clair' => ThemeMode.light,
      'sombre' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> ecrire(ThemeMode mode) {
    final valeur = switch (mode) {
      ThemeMode.light => 'clair',
      ThemeMode.dark => 'sombre',
      ThemeMode.system => 'systeme',
    };
    return _store.ecrireDocument(_type, _cle, {'mode': valeur});
  }

  static const _cleAmbiance = 'ambiance';

  /// Ambiance personnelle (REG-07 C) — [AmbianceVisuelle.etablissement] par défaut.
  Future<AmbianceVisuelle> lireAmbiance() async {
    final document = await _store.lireDocument(_type, _cleAmbiance);
    return AmbianceVisuelle.depuisCode(document?['ambiance'] as String?);
  }

  Future<void> ecrireAmbiance(AmbianceVisuelle ambiance) {
    return _store.ecrireDocument(_type, _cleAmbiance, {'ambiance': ambiance.code});
  }
}
