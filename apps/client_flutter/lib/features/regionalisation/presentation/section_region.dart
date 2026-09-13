import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../auth/application/auth_providers.dart';

/// Section « Région » (D3) — pays et devise, **lecture seule**, dérivés de
/// l'établissement actif. Jamais un choix libre : même principe déjà
/// appliqué à la charte graphique (`themeVariantProvider`), et précédent
/// direct côté `ecoshop_flutter` (`EtablissementModel.countryCode`/
/// `currency`, déjà consommés en lecture seule pour le formatage).
///
/// Partagée telle quelle entre l'étape d'onboarding
/// (`EcranOnboardingRegionalisation`) et `EcranPreferencesApparence`.
class SectionRegion extends ConsumerWidget {
  const SectionRegion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etablissement = ref.watch(etablissementActifProvider);
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Région', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.flag_outlined, color: palette.primaire),
                title: const Text('Pays'),
                subtitle: Text(etablissement?.paysCode ?? '—'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.payments_outlined, color: palette.primaire),
                title: const Text('Devise'),
                subtitle: Text(etablissement?.deviseCode ?? '—'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Déterminés par votre établissement — non modifiables ici.',
          style: TextStyle(color: palette.encreSecondaire, fontSize: 12),
        ),
      ],
    );
  }
}
