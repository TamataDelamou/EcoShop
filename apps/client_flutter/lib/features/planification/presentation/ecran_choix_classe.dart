import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/shimmer.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';

/// Sélecteur de classe générique (M11) — point d'entrée personnel vers
/// l'emploi du temps ou la progression pédagogique d'une classe donnée.
class EcranChoixClasse extends ConsumerWidget {
  const EcranChoixClasse({super.key, required this.titre, required this.onSelectionner});

  final String titre;
  final void Function(BuildContext context, Classe classe) onSelectionner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final structure = ref.watch(structureEtablissementProvider(null));

    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: structure.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(4, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(child: Text('Classes indisponibles hors connexion pour le moment.')),
        data: (donnees) {
          final classes = donnees?.classes ?? const [];
          if (classes.isEmpty) return const Center(child: Text('Aucune classe enregistrée.'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: classes.length,
            itemBuilder: (context, i) {
              final classe = classes[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.class_outlined),
                  title: Text(classe.nom),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onSelectionner(context, classe),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
