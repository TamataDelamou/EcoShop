import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../../../core/sync/device_id_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../application/marketplace_providers.dart';
import 'ecran_choix_paiement.dart';
import 'ligne_achat.dart';
import 'widgets/montant.dart';

/// Panier (M13) — panier serveur si l'établissement est résolu, sinon
/// brouillon local (voir [PanierBrouillonLocal]) tant que l'identifiant
/// d'établissement n'a pas été saisi au checkout.
class EcranPanier extends ConsumerWidget {
  const EcranPanier({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profil = ref.watch(profilProvider).value;
    final etablissement = ref.watch(etablissementActifProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mon panier')),
      body: profil == null
          ? const Center(child: Text('Connexion requise.'))
          : etablissement != null
              ? _PanierServeur(profileId: profil.id, etablissementId: etablissement.id)
              : const _PanierBrouillon(),
    );
  }
}

// ---------------------------------------------------------------------------
// Panier serveur (établissement résolu).
// ---------------------------------------------------------------------------

class _PanierServeur extends ConsumerWidget {
  const _PanierServeur({required this.profileId, required this.etablissementId});

  final String profileId;
  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (profileId: profileId, etablissementId: etablissementId);
    final panierAsync = ref.watch(panierActifProvider(args));

    return panierAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Panier indisponible hors connexion pour le moment.')),
      data: (panier) {
        if (panier == null) return const _PanierVide();
        final lignesAsync = ref.watch(lignesPanierProvider(panier.id));
        return lignesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const Center(child: Text('Panier indisponible hors connexion pour le moment.')),
          data: (lignes) {
            if (lignes.isEmpty) return const _PanierVide();
            final achats = lignes
                .map<LigneAchat>((l) => (
                      catalogueProduitId: l.catalogueProduitId,
                      nom: l.libelleProduit ?? '—',
                      prix: l.prixUnitaire ?? 0,
                      quantite: l.quantite,
                    ))
                .toList();
            return _CorpsPanier(
              lignes: achats,
              onQuantite: (index, quantite) async {
                final ligne = lignes[index];
                final depot = ref.read(marketplaceRepositoryProvider);
                if (quantite <= 0) {
                  await depot.supprimerLignePanier(ligne.id);
                } else {
                  await depot.enregistrerLignePanier(ligne.copierAvec(quantite: quantite));
                }
                ref.invalidate(lignesPanierProvider(panier.id));
              },
              onCommander: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EcranChoixPaiement(
                    etablissementId: etablissementId,
                    commercantId: panier.commercantId!,
                    profileId: profileId,
                    panierId: panier.id,
                    lignes: achats,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Panier brouillon (établissement inconnu).
// ---------------------------------------------------------------------------

class _PanierBrouillon extends ConsumerWidget {
  const _PanierBrouillon();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brouillonAsync = ref.watch(panierBrouillonLocalProvider);

    return brouillonAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Panier indisponible.')),
      data: (brouillon) {
        if (brouillon.estVide || brouillon.commercantId == null) return const _PanierVide();
        final produitsAsync = ref.watch(produitsProvider(brouillon.commercantId));
        return produitsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const Center(child: Text('Panier indisponible hors connexion pour le moment.')),
          data: (produits) {
            final parId = {for (final p in produits) p.id: p};
            final ids = brouillon.quantites.keys.where(parId.containsKey).toList(growable: false);
            if (ids.isEmpty) return const _PanierVide();
            final achats = ids
                .map<LigneAchat>((id) => (
                      catalogueProduitId: id,
                      nom: parId[id]!.libelle,
                      prix: parId[id]!.prix,
                      quantite: brouillon.quantites[id]!,
                    ))
                .toList();
            return _CorpsPanier(
              lignes: achats,
              onQuantite: (index, quantite) =>
                  ref.read(panierBrouillonLocalProvider.notifier).definirQuantite(ids[index], quantite),
              onCommander: () =>
                  _demanderEtablissement(context, ref, brouillon.commercantId!, brouillon.quantites, achats),
            );
          },
        );
      },
    );
  }

  Future<void> _demanderEtablissement(
    BuildContext context,
    WidgetRef ref,
    String commercantId,
    Map<String, int> quantites,
    List<LigneAchat> achats,
  ) async {
    final controleur = TextEditingController();
    final etablissementId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Établissement partenaire', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              "Renseignez l'identifiant de l'établissement communiqué par votre école "
              "(affiche, lien ou QR partagé par l'établissement) pour finaliser votre commande.",
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controleur,
              decoration: const InputDecoration(labelText: 'Identifiant établissement', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final valeur = controleur.text.trim();
                if (valeur.isNotEmpty) Navigator.of(context).pop(valeur);
              },
              child: const Text('Continuer'),
            ),
          ],
        ),
      ),
    );
    if (etablissementId == null || !context.mounted) return;

    final profil = ref.read(profilProvider).value;
    if (profil == null) return;
    final deviceId = await ref.read(deviceIdProvider.future);
    final depot = ref.read(marketplaceRepositoryProvider);

    final panier = construirePanier(
      etablissementId: etablissementId,
      profileId: profil.id,
      commercantId: commercantId,
      deviceId: deviceId,
    );
    await depot.enregistrerPanier(panier);

    for (final entree in quantites.entries) {
      await depot.enregistrerLignePanier(construireLignePanier(
        panierId: panier.id,
        catalogueProduitId: entree.key,
        quantite: entree.value,
      ));
    }

    await ref.read(panierBrouillonLocalProvider.notifier).vider();
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EcranChoixPaiement(
          etablissementId: etablissementId,
          commercantId: commercantId,
          profileId: profil.id,
          panierId: panier.id,
          lignes: achats,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Corps partagé (liste + total + bouton commander).
// ---------------------------------------------------------------------------

class _CorpsPanier extends StatelessWidget {
  const _CorpsPanier({required this.lignes, required this.onQuantite, required this.onCommander});

  final List<LigneAchat> lignes;
  final void Function(int index, int quantite) onQuantite;
  final VoidCallback onCommander;

  @override
  Widget build(BuildContext context) {
    final total = lignes.fold<double>(0, (a, l) => a + l.prix * l.quantite);
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: lignes.length,
            itemBuilder: (context, i) {
              final ligne = lignes[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ligne.nom, style: Theme.of(context).textTheme.titleSmall),
                            Text(formaterMontant(ligne.prix, 'XOF'), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => onQuantite(i, ligne.quantite - 1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('${ligne.quantite}', style: Theme.of(context).textTheme.titleMedium),
                      IconButton(
                        onPressed: () => onQuantite(i, ligne.quantite + 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total'),
                    Text(
                      formaterMontant(total, 'XOF'),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: context.palette.primaire),
                    ),
                  ],
                ),
              ),
              FilledButton(onPressed: onCommander, child: const Text('Commander')),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanierVide extends StatelessWidget {
  const _PanierVide();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 56, color: context.palette.encreSecondaire),
            const SizedBox(height: 12),
            const Text('Votre panier est vide.'),
          ],
        ),
      ),
    );
  }
}
