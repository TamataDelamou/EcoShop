import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/parent_ia_providers.dart';
import '../domain/restriction_parent_ia.dart';
import 'widgets/badge_signal_ia.dart';

/// PARENT IA — historique des restrictions (M16, sous-livrable 4/7).
///
/// Écran PARTAGÉ entre les deux audiences autorisées à le lire — le parent
/// confirmé (toujours en lecture seule : seul l'élève peut activer/désactiver
/// PARENT IA, depuis `EcranParentIaActivation`) et l'élève lui-même — la
/// policy RLS `parent_ia_config_select`/`parent_ia_historique_select`
/// autorise exactement les deux, jamais le personnel de l'établissement
/// (donnée de bien-être numérique d'un mineur, divergence délibérée du
/// reste de l'app).
class EcranParentIaHistorique extends ConsumerWidget {
  const EcranParentIaHistorique({
    super.key,
    required this.ficheEleveId,
    required this.nomEleve,
  });

  final String ficheEleveId;
  final String nomEleve;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(parentIaConfigProvider(ficheEleveId));
    final historique = ref.watch(parentIaHistoriqueProvider(ficheEleveId));

    return Scaffold(
      appBar: AppBar(title: Text('PARENT IA — $nomEleve')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(parentIaConfigProvider(ficheEleveId));
          ref.invalidate(parentIaHistoriqueProvider(ficheEleveId));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            config.when(
              loading: () => const ShimmerCarteListe(),
              error: (erreur, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Configuration indisponible pour le moment.'),
              ),
              data: (c) => GlassCard(
                enfant: Row(
                  children: [
                    Icon(
                      c.actif ? Icons.shield_rounded : Icons.shield_outlined,
                      color: c.actif
                          ? context.palette.succes
                          : context.palette.encreSecondaire,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.actif
                                ? 'PARENT IA actif'
                                : 'PARENT IA non activé',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            c.actif
                                ? 'Activé par $nomEleve — consultable en lecture seule ici.'
                                : 'Ce paramètre ne peut être activé que par $nomEleve lui-même.',
                            style: TextStyle(
                              color: context.palette.encreSecondaire,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Historique des restrictions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                const BadgeSignalIa(),
              ],
            ),
            const SizedBox(height: 8),
            historique.when(
              loading: () => const ShimmerCarteListe(),
              error: (erreur, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Historique indisponible pour le moment.'),
              ),
              data: (liste) {
                if (liste.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Aucune restriction déclenchée pour le moment.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final r in liste) _CarteRestriction(restriction: r),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CarteRestriction extends StatelessWidget {
  const _CarteRestriction({required this.restriction});

  final RestrictionParentIa restriction;

  Color _couleurRisque(BuildContext context) {
    if (restriction.niveauRisqueEchec >= 70) return context.palette.erreur;
    if (restriction.niveauRisqueEchec >= 40) return context.palette.accent;
    return context.palette.succes;
  }

  @override
  Widget build(BuildContext context) {
    final couleur = _couleurRisque(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        enfant: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: couleur.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.notifications_active_rounded,
                color: couleur,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${restriction.appConcernee} — ${restriction.tempsUsageMinutes} min',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  if (restriction.matiereARisque != null)
                    Text(
                      'Matière à risque : ${restriction.matiereARisque}',
                      style: TextStyle(
                        color: context.palette.encreSecondaire,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(restriction.createdAt),
                    style: TextStyle(
                      color: context.palette.encreSecondaire,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: couleur.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${restriction.niveauRisqueEchec}%',
                style: TextStyle(
                  color: couleur,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à '
      '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
}
