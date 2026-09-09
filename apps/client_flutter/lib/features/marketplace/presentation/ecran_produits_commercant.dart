import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../../../core/widgets/shimmer.dart';
import '../application/marketplace_providers.dart';
import '../domain/catalogue_produit.dart';
import '../domain/commercant.dart';
import 'actions_panier.dart';
import 'widgets/montant.dart';

/// Produits d'un commerçant. Recherche texte sur [CatalogueProduit.libelle]/
/// description — pas de colonne « catégorie » dans le DDL réel
/// (`catalogues_produits`) : aucun filtre par taxonomie n'est donc proposé.
class EcranProduitsCommercant extends ConsumerStatefulWidget {
  const EcranProduitsCommercant({super.key, required this.commercant});

  final Commercant commercant;

  @override
  ConsumerState<EcranProduitsCommercant> createState() => _EcranProduitsCommercantState();
}

class _EcranProduitsCommercantState extends ConsumerState<EcranProduitsCommercant> {
  final _recherche = TextEditingController();
  String _terme = '';

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final produits = ref.watch(produitsProvider(widget.commercant.id));

    return Scaffold(
      appBar: AppBar(title: Text(widget.commercant.nom)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _recherche,
              onChanged: (v) => setState(() => _terme = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher un produit…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: produits.when(
              loading: () => ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: List.generate(4, (_) => const ShimmerCarteListe()),
              ),
              error: (e, _) =>
                  const Center(child: Text('Produits indisponibles hors connexion pour le moment.')),
              data: (liste) {
                final filtres = _terme.isEmpty
                    ? liste
                    : liste
                        .where((p) =>
                            p.libelle.toLowerCase().contains(_terme) ||
                            (p.description?.toLowerCase().contains(_terme) ?? false))
                        .toList(growable: false);
                if (filtres.isEmpty) {
                  return const Center(child: Text('Aucun produit ne correspond à la recherche.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtres.length,
                  itemBuilder: (context, i) => _CarteProduit(produit: filtres[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteProduit extends ConsumerWidget {
  const _CarteProduit({required this.produit});

  final CatalogueProduit produit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.inventory_2_outlined, color: context.palette.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(produit.libelle, style: Theme.of(context).textTheme.titleSmall),
                  if (produit.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      produit.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    formaterMontant(produit.prix, produit.devise),
                    style: TextStyle(fontWeight: FontWeight.w700, color: context.palette.primaire),
                  ),
                ],
              ),
            ),
            IconButton.filled(
              onPressed: () => ajouterProduitAuPanier(context, ref, produit),
              icon: const Icon(Icons.add_shopping_cart_outlined),
            ),
          ],
        ),
      ),
    );
  }
}
