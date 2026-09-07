import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/referentiel_providers.dart';
import '../domain/arborescence_niveau.dart';
import '../domain/filiere_educative.dart';
import '../domain/niveau_educatif.dart';
import '../domain/programme_matiere.dart';
import 'widgets/pastille.dart';

/// Filières, programme officiel et matières d'un niveau (M4).
class EcranProgrammeNiveau extends ConsumerStatefulWidget {
  const EcranProgrammeNiveau({super.key, required this.niveau, required this.paysNom});

  final NiveauEducatif niveau;
  final String paysNom;

  @override
  ConsumerState<EcranProgrammeNiveau> createState() => _EcranProgrammeNiveauState();
}

class _EcranProgrammeNiveauState extends ConsumerState<EcranProgrammeNiveau> {
  String? _filiereSelectionneeId;

  @override
  Widget build(BuildContext context) {
    final arbo = ref.watch(arborescenceNiveauProvider(widget.niveau.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.niveau.nom),
      ),
      body: arbo.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: AppColors.encreSecondaire),
                const SizedBox(height: 16),
                const Text(
                  'Ce niveau n\'a pas encore été consulté hors-ligne : une '
                  'connexion est nécessaire au premier chargement.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref
                      .invalidate(arborescenceNiveauProvider(widget.niveau.id)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (arborescence) => _Contenu(
          paysNom: widget.paysNom,
          arborescence: arborescence,
          filiereSelectionneeId: _filiereSelectionneeId,
          onFiliereSelectionnee: (id) => setState(() => _filiereSelectionneeId = id),
        ),
      ),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.paysNom,
    required this.arborescence,
    required this.filiereSelectionneeId,
    required this.onFiliereSelectionnee,
  });

  final String paysNom;
  final ArborescenceNiveau arborescence;
  final String? filiereSelectionneeId;
  final ValueChanged<String?> onFiliereSelectionnee;

  @override
  Widget build(BuildContext context) {
    final programme = arborescence.programmePrincipal(filiereId: filiereSelectionneeId);
    final matieres =
        programme == null ? const <ProgrammeMatiere>[] : arborescence.matieresDuProgramme(programme.id);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(paysNom, style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.encreSecondaire,
            )),
        const SizedBox(height: 4),
        if (arborescence.filieres.isNotEmpty) ...[
          Text('Filière', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _SelecteurFilieres(
            filieres: arborescence.filieres,
            selectionneeId: filiereSelectionneeId,
            onSelectionner: onFiliereSelectionnee,
          ),
          const SizedBox(height: 20),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                programme == null ? 'Programme officiel' : programme.nom,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (programme?.anneeScolaire != null)
              Pastille(
                texte: programme!.anneeScolaire!,
                couleur: AppColors.bleuElectrique,
                icone: Icons.event_outlined,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (programme == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucun programme publié pour ce niveau.'),
            ),
          )
        else if (matieres.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucune matière publiée pour ce programme.'),
            ),
          )
        else
          for (var i = 0; i < matieres.length; i++)
            EntreeAnimee(index: i, enfant: _CarteMatiere(matiere: matieres[i])),
      ],
    );
  }
}

class _SelecteurFilieres extends StatelessWidget {
  const _SelecteurFilieres({
    required this.filieres,
    required this.selectionneeId,
    required this.onSelectionner,
  });

  final List<FiliereEducative> filieres;
  final String? selectionneeId;
  final ValueChanged<String?> onSelectionner;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filiere in filieres)
          ChoiceChip(
            label: Text(filiere.nom),
            selected: selectionneeId == filiere.id,
            onSelected: (choisi) => onSelectionner(choisi ? filiere.id : null),
          ),
      ],
    );
  }
}

class _CarteMatiere extends StatelessWidget {
  const _CarteMatiere({required this.matiere});

  final ProgrammeMatiere matiere;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.menu_book_outlined, color: AppColors.bleuElectrique),
        title: Text(matiere.nom),
        subtitle: matiere.volumeHoraireAnnuel != null
            ? Text('${matiere.volumeHoraireAnnuel} h / an')
            : null,
        trailing: matiere.coefficient != null
            ? Pastille(
                texte: 'Coef. ${matiere.coefficient}',
                couleur: AppColors.orangePop,
              )
            : null,
      ),
    );
  }
}
