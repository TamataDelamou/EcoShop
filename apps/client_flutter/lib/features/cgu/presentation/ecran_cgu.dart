import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../application/cgu_providers.dart';

/// Écran CGU (cahier §34.10) — deux usages distincts partagent le même
/// écran, sans logique dupliquée :
///  - inséré par `GardeSession` juste après la sélection d'établissement,
///    tant que la version courante n'est pas acceptée (bloquant) ;
///  - ouvert à tout moment depuis Profil (consultation, bouton masqué si
///    déjà accepté).
class EcranCgu extends ConsumerWidget {
  const EcranCgu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final statutAsync = ref.watch(cguStatutProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Conditions générales d\'utilisation')),
      body: statutAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Conditions indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (statut) {
          if (statut == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Aucune condition à accepter pour ce compte.'),
              ),
            );
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Version ${statut.numeroVersion}', style: TextStyle(color: palette.encreSecondaire)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(statut.contenu, style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (statut.acceptee)
                    Text(
                      'Acceptées.',
                      style: TextStyle(color: palette.succes, fontWeight: FontWeight.w600),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => ref.read(cguStatutProvider.notifier).accepter(),
                        child: const Text('Accepter'),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
