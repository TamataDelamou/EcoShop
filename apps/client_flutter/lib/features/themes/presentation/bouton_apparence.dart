import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/theme_providers.dart';

/// Apparence (clair, sombre ou automatique), dans la barre du haut : le
/// seul endroit où elle se règle. « Automatique » suit le téléphone et
/// reste le choix par défaut.
class BoutonApparence extends ConsumerWidget {
  const BoutonApparence({super.key});

  static String libelle(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'Automatique (comme le téléphone)',
        ThemeMode.light => 'Clair',
        ThemeMode.dark => 'Sombre',
      };

  static IconData icone(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    return PopupMenuButton<ThemeMode>(
      key: const Key('bouton_apparence'),
      tooltip: 'Apparence : ${libelle(mode)}',
      icon: Icon(icone(mode)),
      initialValue: mode,
      onSelected: (m) => ref.read(themeModeProvider.notifier).definir(m),
      itemBuilder: (context) => [
        for (final m in const [ThemeMode.system, ThemeMode.light, ThemeMode.dark])
          PopupMenuItem<ThemeMode>(
            key: Key('apparence_${m.name}'),
            value: m,
            child: Row(
              children: [
                Icon(icone(m), size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(libelle(m))),
                if (m == mode) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check, size: 20, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
