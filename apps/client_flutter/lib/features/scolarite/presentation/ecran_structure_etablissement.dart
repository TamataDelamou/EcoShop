import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/scolarite_providers.dart';
import '../domain/classe.dart';
import '../domain/structure_etablissement.dart';
import '../domain/unite_operationnelle.dart';
import 'ecran_detail_classe.dart';

/// Annuaire de l'établissement : campus, années scolaires, périodes et
/// classes (M5) — consultable hors connexion une fois chargé (contrat M05).
class EcranStructureEtablissement extends ConsumerStatefulWidget {
  const EcranStructureEtablissement({super.key});

  @override
  ConsumerState<EcranStructureEtablissement> createState() =>
      _EcranStructureEtablissementState();
}

class _EcranStructureEtablissementState
    extends ConsumerState<EcranStructureEtablissement> {
  String? _anneeChoisie;

  @override
  Widget build(BuildContext context) {
    final structure = ref.watch(structureEtablissementProvider(_anneeChoisie));

    return Scaffold(
      appBar: AppBar(title: const Text('Structures & annuaire')),
      body: structure.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(4, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 48, color: context.palette.encreSecondaire),
                const SizedBox(height: 16),
                const Text(
                  "L'annuaire n'a pas encore été consulté : une connexion "
                  'est nécessaire au premier chargement.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(structureEtablissementProvider(_anneeChoisie)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (structureNullable) {
          if (structureNullable == null) {
            return const Center(child: Text('Aucun établissement actif.'));
          }
          return _Contenu(
            structure: structureNullable,
            anneeChoisieId: _anneeChoisie,
            onChoisirAnnee: (id) => setState(() => _anneeChoisie = id),
          );
        },
      ),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.structure,
    required this.anneeChoisieId,
    required this.onChoisirAnnee,
  });

  final StructureEtablissement structure;
  final String? anneeChoisieId;
  final ValueChanged<String?> onChoisirAnnee;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (structure.unites.isNotEmpty) ...[
          Text('Campus & unités', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final u in structure.unites) _PuceUnite(unite: u)],
          ),
          const SizedBox(height: 20),
        ],
        if (structure.anneesScolaires.isNotEmpty) ...[
          Text('Année scolaire', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final annee in structure.anneesScolaires)
                ChoiceChip(
                  label: Text(annee.libelle),
                  selected: (anneeChoisieId ?? structure.anneeCourante?.id) == annee.id,
                  onSelected: (_) => onChoisirAnnee(annee.id),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (structure.periodes.isNotEmpty) ...[
          Text('Périodes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final periode in structure.periodesTriees)
                Chip(avatar: const Icon(Icons.event_note_outlined, size: 16), label: Text(periode.libelle)),
            ],
          ),
          const SizedBox(height: 20),
        ],
        Text('Classes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (structure.classes.isEmpty)
          const Text('Aucune classe publiée pour cette année.')
        else
          for (var i = 0; i < structure.classes.length; i++)
            EntreeAnimee(index: i, enfant: _CarteClasse(classe: structure.classes[i])),
      ],
    );
  }
}

class _PuceUnite extends StatelessWidget {
  const _PuceUnite({required this.unite});

  final UniteOperationnelle unite;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(Icons.apartment_outlined, size: 16, color: context.palette.primaire),
      label: Text(unite.nom),
      backgroundColor: context.palette.primaire.withValues(alpha: 0.08),
    );
  }
}

class _CarteClasse extends StatelessWidget {
  const _CarteClasse({required this.classe});

  final Classe classe;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.meeting_room_outlined, color: context.palette.primaire),
        title: Text(classe.nom),
        subtitle: classe.capacite != null ? Text('Capacité : ${classe.capacite}') : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EcranDetailClasse(classe: classe)),
        ),
      ),
    );
  }
}

