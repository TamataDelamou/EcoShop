import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/marketplace_providers.dart';
import '../domain/enums_marketplace.dart';
import '../domain/sous_compte_marchand.dart';

/// Configuration des sous-comptes marchands (M13) — un par fournisseur et par
/// établissement (contrainte `(etablissement_id, fournisseur)` UNIQUE), gérée
/// par la direction. Aucun secret n'est saisi ici : `referenceCompte` est un
/// identifiant public (merchant id), les clés API vivent en Edge Function.
class EcranSousComptesMarchands extends ConsumerWidget {
  const EcranSousComptesMarchands({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sousComptes = ref.watch(sousComptesEtablissementProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Sous-comptes marchands')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _ouvrirFormulaire(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: sousComptes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (liste) {
          if (liste.isEmpty) {
            return const Center(child: Text('Aucun sous-compte configuré. Ajoutez CinetPay ou Mobile Money.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: liste.length,
            itemBuilder: (context, i) {
              final sc = liste[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(sc.fournisseur == TypeFournisseurPaiement.cinetpay
                      ? Icons.credit_card_outlined
                      : Icons.phone_iphone_outlined),
                  title: Text(sc.libelle),
                  subtitle: Text('${sc.fournisseur.libelle} — ${sc.referenceCompte}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _ouvrirFormulaire(context, ref, sc),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _ouvrirFormulaire(BuildContext context, WidgetRef ref, SousCompteMarchand? existant) async {
    final libelleCtrl = TextEditingController(text: existant?.libelle);
    final referenceCtrl = TextEditingController(text: existant?.referenceCompte);
    var fournisseur = existant?.fournisseur ?? TypeFournisseurPaiement.cinetpay;

    final confirme = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
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
              Text(existant == null ? 'Nouveau sous-compte' : 'Modifier le sous-compte',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              DropdownButtonFormField<TypeFournisseurPaiement>(
                initialValue: fournisseur,
                decoration: const InputDecoration(labelText: 'Fournisseur'),
                items: TypeFournisseurPaiement.values
                    .map((f) => DropdownMenuItem(value: f, child: Text(f.libelle)))
                    .toList(),
                onChanged: existant != null ? null : (v) => setState(() => fournisseur = v!),
              ),
              const SizedBox(height: 12),
              TextField(controller: libelleCtrl, decoration: const InputDecoration(labelText: 'Libellé')),
              const SizedBox(height: 12),
              TextField(
                controller: referenceCtrl,
                decoration: const InputDecoration(labelText: 'Identifiant marchand (merchant id)'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (libelleCtrl.text.trim().isEmpty || referenceCtrl.text.trim().isEmpty) return;
                  Navigator.of(context).pop(true);
                },
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirme != true) return;
    final sousCompte = SousCompteMarchand(
      id: existant?.id ?? const Uuid().v4(),
      etablissementId: etablissementId,
      fournisseur: fournisseur,
      libelle: libelleCtrl.text.trim(),
      referenceCompte: referenceCtrl.text.trim(),
    );
    await ref.read(marketplaceRepositoryProvider).enregistrerSousCompte(sousCompte);
    ref.invalidate(sousComptesEtablissementProvider(etablissementId));
  }
}
