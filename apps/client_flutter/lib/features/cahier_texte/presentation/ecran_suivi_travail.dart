import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../scolarite/domain/classe.dart';
import '../data/cahier_repository.dart';
import '../domain/cahier.dart';
import 'elements_cahier.dart';

/// Suivi d'un travail (REG-40) : qui a fait ou remis, qui est en retard,
/// note moyenne et questions difficiles d'un devoir numérique, relance.
class EcranSuiviTravail extends ConsumerWidget {
  const EcranSuiviTravail({super.key, required this.classe, required this.travail, this.direction = false});

  final Classe classe;
  final Travail travail;
  final bool direction;

  Future<void> _relancer(BuildContext context, WidgetRef ref) async {
    try {
      final n = await ref.read(cahierRepositoryProvider).relancer(travail.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(n == 0 ? 'Tout le monde a déjà fait ce travail.' : 'Rappel envoyé à $n personne${n > 1 ? 's' : ''} (élèves et parents).'),
        ));
      }
    } on ErreurCahier catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _retirer(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Retirer ce travail ?'),
        content: const Text('Il disparaît du cahier des élèves et des parents.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(cahierRepositoryProvider).retirerTravail(travail.id);
      ref.invalidate(travauxClasseProvider(classe.id));
      if (context.mounted) Navigator.of(context).pop();
    } on ErreurCahier catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suivi = ref.watch(suiviTravailProvider(travail.id));
    final devoir = travail.type == TypeTravail.devoirNumerique;
    final schema = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(travail.titre, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [IconButton(tooltip: 'Retirer', onPressed: () => _retirer(context, ref), icon: const Icon(Icons.delete_outline))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('relancer_travail'),
        onPressed: () => _relancer(context, ref),
        icon: const Icon(Icons.notifications_active_outlined),
        label: const Text('Relancer'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(suiviTravailProvider(travail.id)),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          Text([
            travail.type.libelle,
            if (travail.matiere != null) travail.matiere!,
            'pour ${dateLisible(travail.pourLe).toLowerCase()}',
            minutesLisibles(travail.tempsEstimeMin),
          ].join(' · ')),
          if (travail.consigne != null) ...[const SizedBox(height: 6), Text(travail.consigne!)],
          if (travail.piecesJointes.isNotEmpty) ...[const SizedBox(height: 6), PiecesJointes(pieces: travail.piecesJointes)],
          const SizedBox(height: 12),
          suivi.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text(e is ErreurCahier ? e.message : 'Suivi indisponible pour le moment.'),
            data: (s) {
              final total = s.eleves.length;
              final moyenne = s.moyenne;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  _Chiffre(valeur: '${s.termines}/$total', libelle: devoir ? 'remis' : 'faits'),
                  _Chiffre(valeur: '${s.enRetard}', libelle: 'en retard'),
                  if (devoir) _Chiffre(valeur: moyenne == null ? '—' : moyenne.toStringAsFixed(1).replaceAll('.', ','), libelle: 'moyenne / 20'),
                ]),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: total == 0 ? 0 : s.termines / total, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                if (devoir && s.questions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Questions, de la plus ratée à la mieux réussie', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  for (final q in s.questions)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text('Q${q.ordre}. ${q.enonce}', maxLines: 3, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8),
                            Text(q.reussite == null ? '—' : '${(q.reussite! * 100).round()} %',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: q.reussite != null && q.reussite! < 0.5 ? schema.error : null,
                                )),
                          ]),
                          if (q.competence != null)
                            Text(q.competence!, style: TextStyle(fontSize: 12, color: schema.onSurfaceVariant)),
                          if (q.aAider.isNotEmpty && (q.reussite ?? 1) < 0.7)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('À aider : ${q.aAider.join(', ')}', style: const TextStyle(fontSize: 12)),
                            ),
                        ]),
                      ),
                    ),
                  const Text('À reprendre en classe : les questions sous 50 % de réussite.', style: TextStyle(fontSize: 12)),
                ],
                const SizedBox(height: 20),
                Text('Élèves', style: theme.textTheme.titleSmall),
                for (final e in s.eleves)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      e.termine ? Icons.check_circle : (e.commenceLe != null ? Icons.timelapse : Icons.radio_button_unchecked),
                      color: e.termine ? Colors.green.shade700 : schema.onSurfaceVariant,
                    ),
                    title: Text(e.nom),
                    subtitle: Text([
                      if (e.remisLe != null) 'remis ${dateLisible(e.remisLe!).toLowerCase()}'
                      else if (e.faitLe != null) 'fait ${dateLisible(e.faitLe!).toLowerCase()}'
                      else if (e.commenceLe != null) 'commencé'
                      else 'pas encore fait',
                      if (e.enRetard) 'en retard',
                    ].join(' · ')),
                    trailing: e.surVingt == null
                        ? null
                        : Text('${e.surVingt!.toStringAsFixed(1).replaceAll('.', ',')}/20',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                if (devoir)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Résultat d’entraînement : il ne compte pas dans la moyenne du bulletin ; '
                        'il nourrit le profil de maîtrise de chaque élève.', style: TextStyle(fontSize: 12)),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.valeur, required this.libelle});

  final String valeur;
  final String libelle;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(valeur, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text(libelle, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}
