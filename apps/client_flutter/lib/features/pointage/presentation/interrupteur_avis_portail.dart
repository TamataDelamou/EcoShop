import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pointage_providers.dart';

/// Parent ou élève : recevoir ou non les avis d'arrivée et de sortie au
/// portail. Les alertes (absence, sortie avant l'heure) partent toujours.
class InterrupteurAvisPortail extends ConsumerWidget {
  const InterrupteurAvisPortail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valeur = ref.watch(avisArriveeSortieProvider);
    return SwitchListTile(
      key: const Key('avis_portail'),
      secondary: const Icon(Icons.door_front_door_outlined),
      title: const Text("Avis d'arrivée et de sortie de l'école"),
      subtitle: const Text("Les alertes d'absence et de sortie avant l'heure arrivent toujours."),
      value: valeur.valueOrNull ?? true,
      onChanged: valeur.isLoading
          ? null
          : (v) async {
              try {
                await ref.read(pointageRepositoryProvider).definirAvisArriveeSortie(v);
                ref.invalidate(avisArriveeSortieProvider);
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Réglage impossible sans réseau. Réessayez une fois connecté.')),
                );
              }
            },
    );
  }
}
