import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/bandeau_synchronisation.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/comptabilite_providers.dart';
import '../application/pieces_comptables_providers.dart';
import '../domain/pieces_comptables.dart';

/// Exercices comptables et clôtures (REG-03 C2) : ouverture, clôture de
/// période (au moins trimestrielle, art. 22 de l'Acte uniforme), clôture
/// d'exercice avec report à nouveau automatique.
class EcranExercicesComptables extends ConsumerStatefulWidget {
  const EcranExercicesComptables({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranExercicesComptables> createState() => _EcranExercicesComptablesState();
}

class _EcranExercicesComptablesState extends ConsumerState<EcranExercicesComptables> {
  bool _enCours = false;

  void _rafraichir() {
    ref.invalidate(exercicesComptablesProvider(widget.etablissementId));
    ref.invalidate(planComptableProvider(widget.etablissementId));
  }

  Future<void> _executer(Future<String> Function() action) async {
    setState(() => _enCours = true);
    try {
      final message = await action();
      if (!mounted) return;
      _rafraichir();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } on ErreurPiecesComptables catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _ouvrir(List<ExerciceComptable> existants) async {
    // Proposition : la suite du dernier exercice, sinon l'année civile en cours.
    final dernier = existants.isEmpty ? null : existants.reduce((a, b) => a.dateFin.isAfter(b.dateFin) ? a : b);
    var debut = dernier == null ? DateTime(DateTime.now().year, 1, 1) : dernier.dateFin.add(const Duration(days: 1));
    var fin = DateTime(debut.year, 12, 31);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Ouvrir un exercice'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('En comptabilité OHADA, l\'exercice couvre l\'année civile (du 1er janvier au 31 décembre) ; '
                'seul le premier peut commencer en cours d\'année.'),
            const SizedBox(height: 12),
            _ChampDate(
              key: const Key('exercice_debut'),
              libelle: 'Début',
              valeur: debut,
              onChange: dernier == null ? (d) => setDialog(() => debut = d) : null,
            ),
            _ChampDate(
              key: const Key('exercice_fin'),
              libelle: 'Fin',
              valeur: fin,
              onChange: (d) => setDialog(() => fin = d),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
            FilledButton(
              key: const Key('confirmer_ouverture'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ouvrir'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _executer(() async {
      await ref.read(piecesComptablesRepositoryProvider).ouvrirExercice(widget.etablissementId, debut, fin);
      return 'Exercice ouvert.';
    });
  }

  Future<void> _cloturerPeriode(ExerciceComptable x) async {
    final suggestion = _finDeMoisPrecedent(DateTime.now());
    final initiale = suggestion.isBefore(x.dateDebut) || suggestion.isAfter(x.dateFin) ? x.dateFin : suggestion;
    final date = await showDatePicker(
      context: context,
      helpText: 'Clôturer jusqu\'au (inclus)',
      initialDate: initiale,
      firstDate: x.clotureJusquAu?.add(const Duration(days: 1)) ?? x.dateDebut,
      lastDate: x.dateFin,
    );
    if (date == null || !mounted) return;
    final ok = await _confirmer(
      'Clôturer jusqu\'au ${dateCourte(date)} ?',
      'Plus aucune pièce ne pourra être saisie, modifiée ou annulée à une date antérieure. Cette opération est définitive.',
    );
    if (!ok) return;
    await _executer(() async {
      await ref.read(piecesComptablesRepositoryProvider).cloturerPeriode(widget.etablissementId, date);
      return 'Période clôturée jusqu\'au ${dateCourte(date)}.';
    });
  }

  Future<void> _cloturerExercice(ExerciceComptable x) async {
    final ok = await _confirmer(
      'Clôturer ${x.libelle} ?',
      'Le résultat sera calculé, les soldes des comptes de bilan reportés dans l\'exercice suivant (à-nouveaux) '
          'et l\'exercice sera définitivement figé. Réservé à la Direction.',
    );
    if (!ok) return;
    await _executer(() async {
      final r = await ref.read(piecesComptablesRepositoryProvider).cloturerExercice(x.id);
      final nature = r.resultat >= 0 ? 'excédent / bénéfice' : 'déficit / perte';
      return '${x.libelle} clôturé : résultat ${formaterMontant(r.resultat)} ($nature).';
    });
  }

  Future<bool> _confirmer(String titre, String texte) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titre),
        content: Text(texte),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(key: const Key('confirmer_cloture'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirmer')),
        ],
      ),
    );
    return ok == true;
  }

  static DateTime _finDeMoisPrecedent(DateTime d) => DateTime(d.year, d.month, 1).subtract(const Duration(days: 1));

  @override
  Widget build(BuildContext context) {
    final exercices = ref.watch(exercicesComptablesProvider(widget.etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Exercices et clôtures')),
      floatingActionButton: exercices.whenOrNull(
        data: (liste) => FloatingActionButton.extended(
          key: const Key('ouvrir_exercice'),
          onPressed: _enCours ? null : () => _ouvrir(liste),
          icon: const Icon(Icons.add),
          label: const Text('Ouvrir un exercice'),
        ),
      ),
      body: Column(children: [
        const BandeauSynchronisation(),
        Expanded(
          child: exercices.when(
        loading: () => ListView(padding: const EdgeInsets.all(16), children: List.generate(3, (_) => const ShimmerCarteListe())),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e is ErreurPiecesComptables ? e.messageUtilisateur : 'Indisponible pour le moment.', textAlign: TextAlign.center),
          ),
        ),
        data: (liste) {
          if (liste.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucun exercice. Ouvrez le premier pour commencer à saisir des pièces.', textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [for (final x in liste) _carte(context, x)],
          );
        },
      ),
        ),
      ]),
    );
  }

  Widget _carte(BuildContext context, ExerciceComptable x) {
    final palette = context.palette;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(x.cloture ? Icons.lock_outline : Icons.lock_open_outlined,
                  color: x.cloture ? palette.encreSecondaire : palette.primaire),
              const SizedBox(width: 8),
              Expanded(child: Text(x.libelle, style: Theme.of(context).textTheme.titleMedium)),
              Text(x.cloture ? 'Clôturé' : 'Ouvert'),
            ]),
            const SizedBox(height: 6),
            Text('Du ${dateCourte(x.dateDebut)} au ${dateCourte(x.dateFin)}'),
            if (!x.cloture && x.clotureJusquAu != null) Text('Périodes clôturées jusqu\'au ${dateCourte(x.clotureJusquAu!)}'),
            if (x.cloture && x.resultat != null) Text('Résultat : ${formaterMontant(x.resultat!)}'),
            if (!x.cloture) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  key: Key('cloturer_periode_${x.id}'),
                  onPressed: _enCours ? null : () => _cloturerPeriode(x),
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('Clôturer une période'),
                ),
                FilledButton.tonalIcon(
                  key: Key('cloturer_exercice_${x.id}'),
                  onPressed: _enCours ? null : () => _cloturerExercice(x),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Clôturer l\'exercice'),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChampDate extends StatelessWidget {
  const _ChampDate({super.key, required this.libelle, required this.valeur, this.onChange});

  final String libelle;
  final DateTime valeur;
  final ValueChanged<DateTime>? onChange;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(libelle),
        subtitle: Text(dateCourte(valeur)),
        trailing: onChange == null ? null : const Icon(Icons.calendar_today_outlined),
        onTap: onChange == null
            ? null
            : () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: valeur,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) onChange!(d);
              },
      );
}
