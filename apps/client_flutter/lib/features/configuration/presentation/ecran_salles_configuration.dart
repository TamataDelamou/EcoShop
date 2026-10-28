import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../etablissement/domain/etablissement.dart';
import '../../planification/application/planification_providers.dart';
import '../../planification/domain/salle.dart';
import '../application/configuration_providers.dart';
import 'elements_configuration.dart';

/// Salles de l'établissement (REG-23) : salles de classe, laboratoires,
/// salle informatique, terrain… L'emploi du temps évite de mettre deux
/// cours dans la même salle.
class EcranSallesConfiguration extends ConsumerWidget {
  const EcranSallesConfiguration({super.key, required this.etablissement});

  final Etablissement etablissement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salles = ref.watch(sallesEtablissementProvider(etablissement.id));
    final liste = salles.valueOrNull ?? const <Salle>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Salles')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bouton_nouvelle_salle'),
        onPressed: () => _editer(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle salle'),
      ),
      body: salles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ErreurChargement(onReessayer: () => ref.invalidate(sallesEtablissementProvider(etablissement.id))),
        data: (_) => liste.isEmpty
            ? EtatVide(
                icone: Icons.meeting_room_outlined,
                titre: 'Aucune salle',
                texte: 'Facultatif : utile pour les laboratoires, la salle informatique ou les classes qui changent de salle.',
                action: FilledButton.icon(
                  onPressed: () => _editer(context, ref, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une salle'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  for (final s in liste)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.meeting_room_outlined)),
                        title: Text(s.libelle, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: s.capacite == null ? null : Text('${s.capacite} places'),
                        onTap: () => _editer(context, ref, s),
                        trailing: IconButton(
                          tooltip: 'Retirer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await executer(context, () => ref.read(configurationRepositoryProvider).retirerSalle(s),
                                succes: 'Salle retirée.');
                            if (ok) {
                              ref.invalidate(sallesEtablissementProvider(etablissement.id));
                              rafraichirConfiguration(ref.invalidate, etablissementId: etablissement.id);
                            }
                          },
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _editer(BuildContext context, WidgetRef ref, Salle? salle) async {
    final code = TextEditingController(text: salle?.code ?? '');
    final nom = TextEditingController(text: salle?.nom ?? '');
    final capacite = TextEditingController(text: salle?.capacite?.toString() ?? '');
    final valide = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(salle == null ? 'Nouvelle salle' : 'Modifier la salle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: code, autofocus: true, decoration: const InputDecoration(labelText: 'Code', hintText: 'S12, LABO…')),
            TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom (facultatif)', hintText: 'Laboratoire de SVT')),
            TextField(
              controller: capacite,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Places (facultatif)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (valide != true || !context.mounted) return;
    if (code.text.trim().isEmpty) {
      signaler(context, 'Donnez un code à la salle.');
      return;
    }
    final ok = await executer(
      context,
      () => ref.read(configurationRepositoryProvider).enregistrerSalle(
            id: salle?.id,
            etablissementId: etablissement.id,
            code: code.text,
            nom: nom.text,
            capacite: int.tryParse(capacite.text.trim()),
          ),
      succes: 'Salle enregistrée.',
    );
    if (ok) {
      ref.invalidate(sallesEtablissementProvider(etablissement.id));
      rafraichirConfiguration(ref.invalidate, etablissementId: etablissement.id);
    }
  }
}
