import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../application/regionalisation_providers.dart';
import 'section_langue.dart';
import 'section_region.dart';

/// Étape d'onboarding Langue/Région (D3) — insérée par `GardeSession` APRÈS
/// la liaison fiche/sélection établissement (pays/devise dépendent de
/// l'établissement déjà résolu), non bloquante : « Continuer » marque
/// l'étape vue pour ce profil et laisse `RacineApp` réorienter vers
/// l'accueil, sans navigation explicite (même logique déclarative que le
/// reste de la garde de session).
///
/// Réutilise `SectionLangue`/`SectionRegion`, identiques à celles de
/// `EcranPreferencesApparence` — pas de logique dupliquée entre les deux
/// endroits.
class EcranOnboardingRegionalisation extends ConsumerWidget {
  const EcranOnboardingRegionalisation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Avant de commencer', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Vérifiez ces réglages — vous pourrez les changer plus tard '
                'depuis Profil > Apparence.',
                style: TextStyle(color: palette.encreSecondaire),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SectionLangue(),
                      SizedBox(height: 24),
                      SectionRegion(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => ref.read(onboardingRegionalisationVuProvider.notifier).marquerVu(),
                  child: const Text('Continuer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
