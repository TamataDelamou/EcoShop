import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme_variant.dart';
import '../../auth/application/auth_providers.dart';
import '../../referentiel/application/referentiel_providers.dart';
import '../data/theme_preference_store.dart';

final _themePreferenceStoreProvider = Provider<ThemePreferenceStore>((ref) {
  final store = CacheDocumentStore(ref.watch(databaseProvider), 'preferences');
  return ThemePreferenceStore(store);
});

/// Préférence d'apparence (clair/sombre/système) de l'utilisateur, persistée
/// localement (chargement asynchrone, [ThemeMode.system] tant qu'elle n'est
/// pas connue — jamais de flash clair→sombre au démarrage sur un mobile déjà
/// réglé en sombre).
final themeModeProvider =
    AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() {
    return ref.watch(_themePreferenceStoreProvider).lire();
  }

  Future<void> definir(ThemeMode mode) async {
    state = AsyncData(mode);
    await ref.read(_themePreferenceStoreProvider).ecrire(mode);
  }
}

/// Variante visuelle active, dérivée du pays pédagogique de l'établissement
/// actif (M4 : `pays_pedagogiques.type_systeme`) — jamais un choix libre de
/// l'utilisateur : la charte graphique reflète le système éducatif réel de
/// l'établissement. Repli sur [AppThemeVariant.francophoneCfa] tant que
/// l'établissement ou le référentiel pays n'est pas encore chargé.
final themeVariantProvider = Provider<AppThemeVariant>((ref) {
  final etablissement = ref.watch(etablissementActifProvider);
  final paysCode = etablissement?.paysCode;
  if (paysCode == null) return AppThemeVariant.francophoneCfa;

  final pays = ref.watch(paysPedagogiquesProvider).value ?? const [];
  for (final p in pays) {
    if (p.codeIso == paysCode) {
      return AppThemeVariant.depuisCodeSysteme(p.typeSysteme);
    }
  }
  return AppThemeVariant.francophoneCfa;
});
