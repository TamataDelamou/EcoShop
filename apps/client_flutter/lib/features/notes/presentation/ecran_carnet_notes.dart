import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../../scolarite/domain/fiche_eleve.dart';
import '../application/notes_providers.dart';
import '../domain/note.dart';
import 'ecran_bulletins.dart';
import 'widgets/moyenne_badge.dart';
import 'widgets/sparkline_notes.dart';

/// Carnet de notes élève/parent (M6) — moyenne générale, moyennes par
/// matière et évolution, sans jamais recalculer côté client (contrat M06 §5).
///
/// Réactif au sélecteur d'enfant : appelé avec la fiche de l'enfant actif
/// ([EcranScolarite]/[EcranFicheEleve]), l'écran se reconstruit entièrement
/// dès que `enfantActifProvider` change de valeur.
class EcranCarnetNotes extends ConsumerWidget {
  const EcranCarnetNotes({super.key, required this.fiche});

  final FicheEleve fiche;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesDeFicheProvider((ficheId: fiche.id, periodeId: null)));
    final moyenneGenerale = ref.watch(
      moyenneEleveProvider((ficheId: fiche.id, matiereId: null, periodeId: null)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Notes — ${fiche.prenom}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Bulletins',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranBulletins(fiche: fiche)),
            ),
          ),
        ],
      ),
      body: notes.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(4, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Carnet indisponible hors connexion pour le moment.'),
          ),
        ),
        data: (liste) {
          final matieres = _grouperParMatiere(liste);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Moyenne générale', style: Theme.of(context).textTheme.titleMedium),
                      moyenneGenerale.when(
                        loading: () => const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        error: (erreur, _) => const MoyenneBadge(moyenne: null, grande: true),
                        data: (valeur) => MoyenneBadge(moyenne: valeur, grande: true),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (matieres.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Aucune note publiée pour le moment.')),
                )
              else
                for (var i = 0; i < matieres.length; i++)
                  EntreeAnimee(
                    index: i,
                    enfant: _CarteMatiere(ficheId: fiche.id, groupe: matieres[i]),
                  ),
            ],
          );
        },
      ),
    );
  }

  static List<_GroupeMatiere> _grouperParMatiere(List<Note> notes) {
    final parMatiere = <String, List<Note>>{};
    for (final note in notes) {
      final cle = note.evaluation?.programmeMatiereId ?? 'sans_matiere';
      parMatiere.putIfAbsent(cle, () => []).add(note);
    }

    return parMatiere.entries.map((entree) {
      final lignes = List<Note>.from(entree.value)
        ..sort((a, b) {
          final dateA = a.evaluation?.dateEvaluation ?? DateTime(0);
          final dateB = b.evaluation?.dateEvaluation ?? DateTime(0);
          return dateA.compareTo(dateB);
        });
      final matiereId = entree.key == 'sans_matiere' ? null : entree.key;
      final nom = lignes.map((n) => n.evaluation?.nomMatiere).whereType<String>().firstOrNull ??
          'Matière non précisée';
      return _GroupeMatiere(matiereId: matiereId, nomMatiere: nom, notes: lignes);
    }).toList(growable: false)
      ..sort((a, b) => a.nomMatiere.compareTo(b.nomMatiere));
  }
}

class _GroupeMatiere {
  const _GroupeMatiere({required this.matiereId, required this.nomMatiere, required this.notes});

  final String? matiereId;
  final String nomMatiere;
  final List<Note> notes;
}

class _CarteMatiere extends ConsumerWidget {
  const _CarteMatiere({required this.ficheId, required this.groupe});

  final String ficheId;
  final _GroupeMatiere groupe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moyenne = ref.watch(
      moyenneEleveProvider((ficheId: ficheId, matiereId: groupe.matiereId, periodeId: null)),
    );
    final valeurs = groupe.notes
        .where((n) => !n.absent && n.valeur != null)
        .map((n) => n.evaluation == null ? n.valeur! : (n.valeur! / n.evaluation!.bareme) * 20)
        .toList(growable: false);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(groupe.nomMatiere, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: moyenne.when(
          loading: () => const SizedBox.shrink(),
          error: (erreur, _) => const MoyenneBadge(moyenne: null),
          data: (valeur) => MoyenneBadge(moyenne: valeur),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SparklineNotes(valeursSur20: valeurs),
                const SizedBox(height: 12),
                for (final note in groupe.notes) _LigneNote(note: note),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneNote extends StatelessWidget {
  const _LigneNote({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final evaluation = note.evaluation;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              evaluation?.libelle ?? 'Évaluation',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            note.absent ? 'Absent·e' : '${note.valeur?.toStringAsFixed(1) ?? '—'}/${evaluation?.bareme.toStringAsFixed(0) ?? '20'}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: note.absent ? context.palette.encreSecondaire : context.palette.encre,
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
