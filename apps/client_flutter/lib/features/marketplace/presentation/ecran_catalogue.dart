import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../../../core/widgets/selecteur_vue.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/marketplace_providers.dart';
import '../domain/commercant.dart';
import 'ecran_produits_commercant.dart';

/// Catalogue marketplace (M13) — liste des commerçants actifs. Lecture
/// publique (`commercants` RLS `using (true)`), aucune notion d'établissement.
///
/// Premier terrain d'application du sélecteur grille/liste/cartes (D1,
/// `SelecteurVue`/`ModeAffichage`) — D2 le réutilise tel quel pour les
/// cartes profil, sans le redessiner. Mode par défaut = « cartes », pour
/// préserver le rendu déjà existant tant que personne ne bascule le
/// sélecteur.
class EcranCatalogue extends ConsumerStatefulWidget {
  const EcranCatalogue({super.key});

  @override
  ConsumerState<EcranCatalogue> createState() => _EcranCatalogueState();
}

class _EcranCatalogueState extends ConsumerState<EcranCatalogue> {
  ModeAffichage _mode = ModeAffichage.cartes;

  @override
  Widget build(BuildContext context) {
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
              children: const [
                Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucun commerçant.'))),
              ],
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SelecteurVue(
                    mode: _mode,
                    onChanged: (m) => setState(() => _mode = m),
                  ),
                ),
              ),
              Expanded(child: _corps(context, liste)),
            ],
          );
        },
      ),
    );
  }

  Widget _corps(BuildContext context, List<Commercant> liste) {
    return switch (_mode) {
      ModeAffichage.liste => ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: liste.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => _LigneCommercant(commercant: liste[i]),
        ),
      ModeAffichage.grille => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.sizeOf(context).width >= 720 ? 4 : 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: liste.length,
          itemBuilder: (context, i) => _TuileCommercant(commercant: liste[i]),
        ),
      ModeAffichage.cartes => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: liste.length,
          itemBuilder: (context, i) => _CarteCommercant(commercant: liste[i]),
        ),
    };
  }
}

void _ouvrirCommercant(BuildContext context, Commercant commercant) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => EcranProduitsCommercant(commercant: commercant)),
  );
}

/// Mode « cartes » — rendu inchangé par rapport à l'écran d'avant D1 (défaut
/// préservé).
class _CarteCommercant extends StatelessWidget {
  const _CarteCommercant({required this.commercant});

  final Commercant commercant;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: context.palette.primaire,
          child: const Icon(Icons.storefront_outlined, color: Colors.white),
        ),
        title: Text(commercant.nom),
        subtitle: commercant.raisonSociale != null ? Text(commercant.raisonSociale!) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _ouvrirCommercant(context, commercant),
      ),
    );
  }
}

/// Mode « liste » — dense, sans `Card`, pour scanner beaucoup de
/// commerçants d'un coup d'œil.
class _LigneCommercant extends StatelessWidget {
  const _LigneCommercant({required this.commercant});

  final Commercant commercant;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.storefront_outlined, color: context.palette.primaire),
      title: Text(commercant.nom),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _ouvrirCommercant(context, commercant),
    );
  }
}

/// Mode « grille » — tuile compacte, 2 colonnes (4 sur grand écran).
class _TuileCommercant extends StatelessWidget {
  const _TuileCommercant({required this.commercant});

  final Commercant commercant;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => _ouvrirCommercant(context, commercant),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: context.palette.primaire,
                child: const Icon(Icons.storefront_outlined, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                commercant.nom,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
