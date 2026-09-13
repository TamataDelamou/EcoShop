import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/accessibilite_providers.dart';
import '../domain/echelle_texte.dart';

/// Section « Accessibilité » (D4, §34.9) — contraste élevé et taille du
/// texte, seul écart confirmé absent partout (ni `ecoshop_flutter`, ni ce
/// client) avant cette passe. Ajoutée à `EcranPreferencesApparence`, aux
/// côtés de Thème/Langue/Région — même patron établi en D3.
class SectionAccessibilite extends ConsumerWidget {
  const SectionAccessibilite({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contrasteAsync = ref.watch(contrasteEleveProvider);
    final echelleAsync = ref.watch(echelleTexteProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Accessibilité', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: contrasteAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const ListTile(
              title: Text('Préférence indisponible — contraste standard appliqué'),
            ),
            data: (actif) => SwitchListTile(
              title: const Text('Contraste élevé'),
              subtitle: const Text('Remplace la charte graphique par une palette à contraste maximal'),
              value: actif,
              onChanged: (v) => ref.read(contrasteEleveProvider.notifier).definir(v),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Taille du texte'),
                const SizedBox(height: 8),
                echelleAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Text('Préférence indisponible — taille normale appliquée'),
                  data: (echelle) => Wrap(
                    spacing: 8,
                    children: [
                      for (final e in EchelleTexte.values)
                        ChoiceChip(
                          label: Text(e.libelle),
                          selected: echelle == e,
                          onSelected: (_) => ref.read(echelleTexteProvider.notifier).definir(e),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
