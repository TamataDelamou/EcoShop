import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/glass_card.dart';
import '../application/parent_ia_providers.dart';
import '../domain/parent_ia_repository.dart';

/// PARENT IA — déclaration manuelle d'usage (M16, sous-livrable 4/7).
///
/// Périmètre acté pour cette passe : déclaration manuelle UNIQUEMENT — la
/// mesure automatique Android (`usage_stats`/`UsageStatsManager`) reste un
/// écart documenté séparément (nécessite un appareil/émulateur Android réel
/// avec la permission accordée pour être vérifiée empiriquement, voir le
/// rapport d'écart). Cet écran couvre exactement le chemin qu'utilisait déjà
/// la source pour iOS et pour Android sans permission — jamais un mur
/// "indisponible", une estimation honnête déclarée par l'élève lui-même.
class EcranParentIaDeclarationUsage extends ConsumerStatefulWidget {
  const EcranParentIaDeclarationUsage({super.key, required this.ficheEleveId});

  final String ficheEleveId;

  @override
  ConsumerState<EcranParentIaDeclarationUsage> createState() =>
      _EcranParentIaDeclarationUsageState();
}

class _EcranParentIaDeclarationUsageState
    extends ConsumerState<EcranParentIaDeclarationUsage> {
  static const _apps = [
    'Réseaux sociaux (global)',
    'TikTok',
    'Instagram',
    'Snapchat',
    'YouTube',
    'Jeux mobiles',
  ];

  String _appChoisie = _apps.first;
  double _minutes = 60;
  bool _envoi = false;

  Future<void> _envoyer() async {
    setState(() => _envoi = true);
    try {
      final restrictionDeclenchee = await ref
          .read(parentIaRepositoryProvider)
          .declarerUsage(
            ficheEleveId: widget.ficheEleveId,
            appPrincipale: _appChoisie,
            minutes: _minutes.round(),
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restrictionDeclenchee
                ? 'Merci pour ta transparence — une notification t\'a été envoyée avec des conseils.'
                : 'Merci, c\'est enregistré. Ton usage reste raisonnable au vu de ton profil actuel.',
          ),
          backgroundColor: restrictionDeclenchee
              ? context.palette.accent
              : context.palette.succes,
        ),
      );
      Navigator.of(context).maybePop();
    } on ErreurParentIa catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Déclaration refusée (${e.code}).'),
          backgroundColor: context.palette.erreur,
        ),
      );
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Déclarer mon usage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            enfant: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: context.palette.primaire,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Indique une estimation honnête — c\'est ce qui rend PARENT IA utile pour toi.',
                    style: TextStyle(
                      color: context.palette.encreSecondaire,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Application principale concernée',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _apps.map((app) {
              final selectionne = app == _appChoisie;
              return ChoiceChip(
                label: Text(app),
                selected: selectionne,
                onSelected: (_) => setState(() => _appChoisie = app),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Temps estimé aujourd\'hui',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              Text(
                '${_minutes.round()} min',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.palette.primaire,
                ),
              ),
            ],
          ),
          Slider(
            value: _minutes,
            min: 0,
            max: 360,
            divisions: 36,
            onChanged: (v) => setState(() => _minutes = v),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: _envoi
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('Envoyer pour analyse'),
            onPressed: _envoi ? null : _envoyer,
          ),
        ],
      ),
    );
  }
}
