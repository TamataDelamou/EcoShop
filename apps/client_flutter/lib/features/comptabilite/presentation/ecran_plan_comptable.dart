import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/shimmer.dart';
import '../application/comptabilite_providers.dart';
import '../domain/enums_comptabilite.dart';
import '../domain/plan_comptable.dart';

/// Plan comptable (M14) — arbre OUVERT de comptes, aucune structure OHADA
/// imposée. Configuration en ligne uniquement (comme les salles en M11).
class EcranPlanComptable extends ConsumerWidget {
  const EcranPlanComptable({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comptes = ref.watch(planComptableProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Plan comptable')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _ouvrirFormulaire(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: comptes.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(5, (_) => const ShimmerCarteListe()),
        ),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (liste) {
          if (liste.isEmpty) {
            return const Center(child: Text("Aucun compte. Créez votre premier compte du plan."));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: liste.length,
            itemBuilder: (context, i) {
              final compte = liste[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(child: Text(compte.type.libelle.substring(0, 1))),
                  title: Text(compte.libelle),
                  subtitle: Text(compte.type.libelle),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _ouvrirFormulaire(context, ref, compte),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _ouvrirFormulaire(BuildContext context, WidgetRef ref, PlanComptable? existant) async {
    final codeCtrl = TextEditingController(text: existant?.code);
    final intituleCtrl = TextEditingController(text: existant?.intitule);
    var type = existant?.type ?? TypeCompte.autre;

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
              Text(existant == null ? 'Nouveau compte' : 'Modifier le compte',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextField(
                controller: codeCtrl,
                enabled: existant == null,
                decoration: const InputDecoration(labelText: 'Code (ex. 520)'),
              ),
              const SizedBox(height: 12),
              TextField(controller: intituleCtrl, decoration: const InputDecoration(labelText: 'Intitulé')),
              const SizedBox(height: 12),
              DropdownButtonFormField<TypeCompte>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: TypeCompte.values.map((t) => DropdownMenuItem(value: t, child: Text(t.libelle))).toList(),
                onChanged: (v) => setState(() => type = v!),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (codeCtrl.text.trim().isEmpty || intituleCtrl.text.trim().isEmpty) return;
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
    final compte = PlanComptable(
      id: existant?.id ?? const Uuid().v4(),
      etablissementId: etablissementId,
      code: codeCtrl.text.trim(),
      intitule: intituleCtrl.text.trim(),
      type: type,
    );
    await ref.read(comptabiliteRepositoryProvider).enregistrerCompte(compte);
    ref.invalidate(planComptableProvider(etablissementId));
  }
}
