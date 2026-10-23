import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/ambiance_visuelle.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_palettes.dart';
import '../../../core/theme/app_theme_variant.dart';
import '../../accessibilite/presentation/section_accessibilite.dart';
import '../../regionalisation/presentation/section_langue.dart';
import '../../regionalisation/presentation/section_region.dart';
import '../application/theme_providers.dart';

/// Écran de préférence d'apparence : bascule clair/sombre/système, rappel
/// de la charte graphique active (dérivée de l'établissement, non modifiable
/// ici — voir [themeVariantProvider]), depuis D3 langue (modifiable) et
/// région (pays/devise, lecture seule), et depuis D4 accessibilité
/// (contraste élevé, taille du texte) — l'écran accumule ces sections par
/// choix assumé (même patron `SectionXxx` réutilisé, jamais dupliqué).
class EcranPreferencesApparence extends ConsumerWidget {
  const EcranPreferencesApparence({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variante = ref.watch(themeVariantProvider);
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Langue et affichage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Clair, sombre ou automatique : dans la barre du haut
          // (`BoutonApparence`), seul endroit où il se règle.
          Text('Charte graphique', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.palette_outlined, color: palette.primaire),
              title: Text(_libelleVariante(variante)),
              subtitle: const Text(
                'Déterminée par le système éducatif du pays de votre établissement '
                '(référentiel pédagogique CEDEAO) — non modifiable manuellement. '
                "La Direction peut y ajouter la couleur et le logo de l'établissement.",
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SectionLangue(),
          const SizedBox(height: 24),
          const SectionRegion(),
          const SizedBox(height: 24),
          const SectionAccessibilite(),
          const SizedBox(height: 24),
          Text('Ambiance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Un choix personnel, sur cet appareil uniquement : les documents imprimés '
            "gardent toujours la charte de l'établissement.",
            style: TextStyle(fontSize: 13, color: palette.encreSecondaire),
          ),
          const SizedBox(height: 8),
          const _SectionAmbiance(),
        ],
      ),
    );
  }

  static String _libelleVariante(AppThemeVariant variante) => switch (variante) {
        AppThemeVariant.francophoneCfa => 'Francophone CFA — Innovation & Énergie',
        AppThemeVariant.anglophoneWaec => 'Anglophone WAEC',
        AppThemeVariant.lusophone => 'Lusophone',
        AppThemeVariant.arabophoneMixte => 'Arabophone',
      };
}

/// Choix de l'ambiance personnelle (REG-07 C) : chaque carte montre ses
/// couleurs réelles, dans la luminosité en cours.
class _SectionAmbiance extends ConsumerWidget {
  const _SectionAmbiance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ambiance = ref.watch(ambianceProvider).valueOrNull ?? AmbianceVisuelle.etablissement;
    final variante = ref.watch(themeVariantProvider);
    final couleurEtablissement = ref.watch(identiteEtablissementProvider).couleur;
    final brightness = Theme.of(context).brightness;
    final palette = context.palette;

    return Column(
      children: [
        for (final a in AmbianceVisuelle.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CarteAmbiance(
              ambiance: a,
              apercu: a == AmbianceVisuelle.etablissement
                  ? AppPalettes.resoudre(variante, brightness, couleurEtablissement: couleurEtablissement)
                  : AppPalettes.pourAmbiance(a, brightness)!,
              selectionnee: a == ambiance,
              surTap: () => ref.read(ambianceProvider.notifier).definir(a),
              couleurSelection: palette.primaire,
            ),
          ),
      ],
    );
  }
}

class _CarteAmbiance extends StatelessWidget {
  const _CarteAmbiance({
    required this.ambiance,
    required this.apercu,
    required this.selectionnee,
    required this.surTap,
    required this.couleurSelection,
  });

  final AmbianceVisuelle ambiance;
  final AppPalette apercu;
  final bool selectionnee;
  final VoidCallback surTap;
  final Color couleurSelection;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selectionnee ? couleurSelection : palette.bordure,
          width: selectionnee ? 2 : 1,
        ),
      ),
      child: InkWell(
        key: Key('ambiance_${ambiance.code}'),
        borderRadius: BorderRadius.circular(16),
        onTap: surTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Échantillon : fond, couleur principale, accent.
              Container(
                width: 64,
                height: 40,
                decoration: BoxDecoration(
                  color: apercu.fond,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: apercu.bordure),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Point(couleur: apercu.primaire),
                    _Point(couleur: apercu.accent),
                    _Point(couleur: apercu.succes),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ambiance.libelle, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(ambiance.description, style: TextStyle(fontSize: 12, color: palette.encreSecondaire)),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: selectionnee
                    ? Icon(Icons.check_circle_rounded, key: const ValueKey('oui'), color: couleurSelection)
                    : Icon(Icons.circle_outlined, key: const ValueKey('non'), color: palette.bordure),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.couleur});

  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(width: 12, height: 12, decoration: BoxDecoration(color: couleur, shape: BoxShape.circle));
  }
}
