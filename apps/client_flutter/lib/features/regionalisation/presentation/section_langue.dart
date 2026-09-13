import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/regionalisation_providers.dart';

/// Section « Langue » (D3) — préférence modifiable, stockée localement.
///
/// Une seule option opérante (Français) pour ne pas présenter un faux
/// choix qui ne changerait rien à l'écran : la traduction réelle de l'app
/// est un chantier distinct (aucune infrastructure `intl`/ARB dans ce
/// projet à ce jour). Le widget reste générique (`languesDisponibles`)
/// pour accueillir d'autres langues plus tard sans être reconstruit.
///
/// Partagée telle quelle entre l'étape d'onboarding
/// (`EcranOnboardingRegionalisation`) et `EcranPreferencesApparence`, pour
/// ne jamais dupliquer cette logique entre les deux endroits.
class SectionLangue extends ConsumerWidget {
  const SectionLangue({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final langueAsync = ref.watch(langueProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Langue', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: langueAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const ListTile(
              title: Text('Préférence indisponible — français appliqué'),
            ),
            data: (code) => RadioGroup<String>(
              groupValue: code,
              onChanged: (c) => _definir(ref, c),
              child: Column(
                children: [
                  for (final langue in languesDisponibles)
                    RadioListTile<String>(title: Text(langue.$2), value: langue.$1),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _definir(WidgetRef ref, String? code) {
    if (code == null) return;
    ref.read(langueProvider.notifier).definir(code);
  }
}
