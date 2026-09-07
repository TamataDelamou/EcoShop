import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/marketplace_providers.dart';
import '../domain/commercant.dart';
import 'ecran_produits_commercant.dart';

/// Catalogue marketplace (M13) — liste des commerçants actifs. Lecture
/// publique (`commercants` RLS `using (true)`), aucune notion d'établissement.
class EcranCatalogue extends ConsumerWidget {
  const EcranCatalogue({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commercants = ref.watch(commercantsProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(commercantsProvider.future),
      child: commercants.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(5, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => ListView(
          children: const [
            Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Catalogue indisponible hors connexion pour le moment.')),
            ),
          ],
        ),
        data: (liste) {
          if (liste.isEmpty) {
            return ListView(
              children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucun commerçant.')))],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: liste.length,
            itemBuilder: (context, i) => _CarteCommercant(commercant: liste[i]),
          );
        },
      ),
    );
  }
}

class _CarteCommercant extends StatelessWidget {
  const _CarteCommercant({required this.commercant});

  final Commercant commercant;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.bleuElectrique,
          child: Icon(Icons.storefront_outlined, color: Colors.white),
        ),
        title: Text(commercant.nom),
        subtitle: commercant.raisonSociale != null ? Text(commercant.raisonSociale!) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EcranProduitsCommercant(commercant: commercant)),
        ),
      ),
    );
  }
}
