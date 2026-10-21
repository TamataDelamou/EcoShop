import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../application/pointage_providers.dart';
import '../domain/pointage.dart';

final _packsProvider = FutureProvider.autoDispose<List<PackSms>>((ref) => ref.watch(pointageRepositoryProvider).tousLesPacks());
final _soldesProvider = FutureProvider.autoDispose<List<({String id, String nom, String? ville, int solde})>>(
  (ref) => ref.watch(pointageRepositoryProvider).soldesEtablissements(),
);

/// Administration GSG (REG-09) : prix des packs de SMS revendus aux écoles,
/// et crédit manuel après un paiement reçu hors application.
class EcranCreditsSmsGsg extends ConsumerWidget {
  const EcranCreditsSmsGsg({super.key});

  Future<void> _modifierPack(BuildContext context, WidgetRef ref, PackSms pack) async {
    final prix = TextEditingController(text: pack.prix > 0 ? pack.prix.round().toString() : '');
    var actif = pack.actif;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(pack.libelle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: prix,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: 'Prix (${pack.devise})', border: const OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: actif,
                onChanged: (v) => set(() => actif = v),
                title: const Text('En vente'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    final montant = double.tryParse(prix.text) ?? 0;
    prix.dispose();
    if (ok != true) return;
    try {
      await ref.read(pointageRepositoryProvider).definirPack(PackSms(
            code: pack.code,
            libelle: pack.libelle,
            quantite: pack.quantite,
            prix: montant,
            devise: pack.devise,
            actif: actif,
          ));
      ref.invalidate(_packsProvider);
    } on ErreurPointage catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    }
  }

  Future<void> _crediter(BuildContext context, WidgetRef ref, ({String id, String nom, String? ville, int solde}) ecole) async {
    final quantite = TextEditingController();
    final reference = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Créditer ${ecole.nom}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantite,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(labelText: 'Nombre de SMS (négatif pour corriger)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reference,
              decoration: const InputDecoration(labelText: 'Référence du paiement reçu', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Créditer')),
        ],
      ),
    );
    final n = int.tryParse(quantite.text.trim()) ?? 0;
    final ref0 = reference.text.trim();
    quantite.dispose();
    reference.dispose();
    if (ok != true || n == 0) return;
    try {
      final solde = await ref.read(pointageRepositoryProvider).crediter(ecole.id, n, ref0);
      ref.invalidate(_soldesProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${ecole.nom} : $solde SMS disponibles.')));
    } on ErreurPointage catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final packs = ref.watch(_packsProvider);
    final soldes = ref.watch(_soldesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Crédits SMS des écoles')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('Packs en vente', style: Theme.of(context).textTheme.titleMedium),
          Text('Fixez le prix de revente de chaque pack ; un pack sans prix n\'est pas proposé aux écoles.',
              style: TextStyle(color: palette.encreSecondaire, fontSize: 12)),
          ...packs.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(e is ErreurPointage ? e.messageUtilisateur : 'Indisponible.')],
            data: (liste) => [
              for (final p in liste)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(p.actif ? Icons.check_circle : Icons.pause_circle_outline,
                      color: p.actif ? palette.succes : palette.encreSecondaire),
                  title: Text(p.libelle),
                  subtitle: Text(p.prix > 0 ? '${p.prix.round()} ${p.devise}' : 'Prix à fixer'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _modifierPack(context, ref, p),
                ),
            ],
          ),
          const Divider(height: 32),
          Text('Solde des écoles', style: Theme.of(context).textTheme.titleMedium),
          ...soldes.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(e is ErreurPointage ? e.messageUtilisateur : 'Indisponible.')],
            data: (liste) => [
              for (final e in liste)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.nom),
                  subtitle: e.ville == null ? null : Text(e.ville!),
                  trailing: Text('${e.solde} SMS', style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => _crediter(context, ref, e),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
