import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme_variant.dart';
import '../application/theme_providers.dart';

/// Écran de préférence d'apparence : bascule clair/sombre/système et rappel
/// de la charte graphique active (dérivée de l'établissement, non modifiable
/// ici — voir [themeVariantProvider]).
class EcranPreferencesApparence extends ConsumerWidget {
  const EcranPreferencesApparence({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modeAsync = ref.watch(themeModeProvider);
    final variante = ref.watch(themeVariantProvider);
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Apparence')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Luminosité', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: modeAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => const ListTile(
                title: Text('Préférence indisponible — mode système appliqué'),
              ),
              data: (mode) => RadioGroup<ThemeMode>(
                groupValue: mode,
                onChanged: (m) => _definir(ref, m),
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: Text('Clair'),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Sombre'),
                      value: ThemeMode.dark,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Système'),
                      subtitle: Text('Suit le réglage de l\'appareil'),
                      value: ThemeMode.system,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Charte graphique', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.palette_outlined, color: palette.primaire),
              title: Text(_libelleVariante(variante)),
              subtitle: const Text(
                'Déterminée par le système éducatif du pays de votre établissement '
                '(référentiel pédagogique CEDEAO) — non modifiable manuellement.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _definir(WidgetRef ref, ThemeMode? mode) {
    if (mode == null) return;
    ref.read(themeModeProvider.notifier).definir(mode);
  }

  static String _libelleVariante(AppThemeVariant variante) => switch (variante) {
        AppThemeVariant.francophoneCfa => 'Francophone CFA — Innovation & Énergie',
        AppThemeVariant.anglophoneWaec => 'Anglophone WAEC',
        AppThemeVariant.lusophone => 'Lusophone',
      };
}
