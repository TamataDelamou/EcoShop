import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/shimmer.dart';
import '../application/comptabilite_providers.dart';
import '../domain/enums_comptabilite.dart';
import '../domain/journal.dart';

/// Journaux (M14) — livres chronologiques (opérations, banque, caisse,
/// achats, ventes). Configuration en ligne uniquement.
class EcranJournaux extends ConsumerWidget {
  const EcranJournaux({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journaux = ref.watch(journauxProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Journaux')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _ouvrirFormulaire(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: journaux.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (liste) {
          if (liste.isEmpty) {
            return const Center(child: Text("Aucun journal. Créez votre premier journal."));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: liste.length,
            itemBuilder: (context, i) {
              final journal = liste[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(journal.libelle),
                  subtitle: Text(journal.type.libelle),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _ouvrirFormulaire(context, ref, journal),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _ouvrirFormulaire(BuildContext context, WidgetRef ref, Journal? existant) async {
    final codeCtrl = TextEditingController(text: existant?.code);
    final intituleCtrl = TextEditingController(text: existant?.intitule);
    var type = existant?.type ?? TypeJournal.operations;

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
              Text(existant == null ? 'Nouveau journal' : 'Modifier le journal',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextField(
                controller: codeCtrl,
                enabled: existant == null,
                decoration: const InputDecoration(labelText: 'Code (ex. BQ)'),
              ),
              const SizedBox(height: 12),
              TextField(controller: intituleCtrl, decoration: const InputDecoration(labelText: 'Intitulé')),
              const SizedBox(height: 12),
              DropdownButtonFormField<TypeJournal>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: TypeJournal.values.map((t) => DropdownMenuItem(value: t, child: Text(t.libelle))).toList(),
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
    final journal = Journal(
      id: existant?.id ?? const Uuid().v4(),
      etablissementId: etablissementId,
      code: codeCtrl.text.trim(),
      intitule: intituleCtrl.text.trim(),
      type: type,
    );
    await ref.read(comptabiliteRepositoryProvider).enregistrerJournal(journal);
    ref.invalidate(journauxProvider(etablissementId));
  }
}
