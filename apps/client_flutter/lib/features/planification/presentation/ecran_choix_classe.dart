import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/shimmer.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../../auth/application/auth_providers.dart';

/// Sélecteur de classe générique (M11) — point d'entrée personnel vers
/// l'emploi du temps ou la progression pédagogique d'une classe donnée.
class EcranChoixClasse extends ConsumerWidget {
  const EcranChoixClasse({
    super.key,
    required this.titre,
    required this.onSelectionner,
    this.seulementMesClasses = false,
  });

  final String titre;
  final void Function(BuildContext context, Classe classe) onSelectionner;

  /// Enseignant : seulement les classes qui lui sont confiées (« Cours et
  /// enseignants » ou professeur principal). Il voyait toutes les classes de
  /// l'école pour l'appel et les notes (retour du porteur de projet,
  /// 2026-10-31).
  final bool seulementMesClasses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final structure = ref.watch(structureEtablissementProvider(null));
    final affectations = seulementMesClasses ? ref.watch(mesAffectationsProvider) : null;
    final moi = seulementMesClasses ? ref.watch(profilProvider).valueOrNull?.id : null;
    if (affectations != null && affectations.isLoading && !affectations.hasValue) {
      return Scaffold(appBar: AppBar(title: Text(titre)), body: const Center(child: CircularProgressIndicator()));
    }
    final confiees = {for (final a in affectations?.valueOrNull ?? const []) a.classeId};
    bool retenue(Classe c) => !seulementMesClasses || confiees.contains(c.id) || (moi != null && c.enseignantPrincipalId == moi);

    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: structure.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(4, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(child: Text('Classes indisponibles hors connexion pour le moment.')),
        data: (donnees) {
          final classes = [for (final c in donnees?.classes ?? const <Classe>[]) if (retenue(c)) c];
          if (classes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  seulementMesClasses
                      ? 'Aucune classe ne vous est confiée pour le moment. La direction vous attribue vos classes '
                          'dans « Cours et enseignants ».'
                      : 'Aucune classe enregistrée.',
                  key: const Key('aucune_classe_confiee'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
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
