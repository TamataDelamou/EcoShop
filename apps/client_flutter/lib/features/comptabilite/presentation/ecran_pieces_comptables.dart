import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/pieces_comptables_providers.dart';
import '../domain/pieces_comptables.dart';
import 'ecran_exercices_comptables.dart';
import 'ecran_saisie_piece.dart';

enum _Filtre { toutes, brouillards, validees }

/// Pièces comptables d'un exercice (REG-03 C2) : brouillards à finir,
/// pièces validées (numérotées, définitives), annulations.
class EcranPiecesComptables extends ConsumerStatefulWidget {
  const EcranPiecesComptables({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranPiecesComptables> createState() => _EcranPiecesComptablesState();
}

class _EcranPiecesComptablesState extends ConsumerState<EcranPiecesComptables> {
  String? _exerciceId;
  _Filtre _filtre = _Filtre.toutes;

  ExerciceComptable? _exerciceParDefaut(List<ExerciceComptable> liste) {
    final aujourdhui = DateTime.now();
    for (final x in liste) {
      if (!x.cloture && x.contient(aujourdhui)) return x;
    }
    for (final x in liste) {
      if (!x.cloture) return x;
    }
    return liste.isEmpty ? null : liste.first;
  }

  Future<void> _ouvrirSaisie({PieceComptable? brouillard}) async {
    final fait = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => EcranSaisiePiece(etablissementId: widget.etablissementId, brouillard: brouillard),
    ));
    if (fait == true) _rafraichir();
  }

  void _rafraichir() {
    final id = _exerciceId;
    if (id != null) {
      ref.invalidate(piecesComptablesProvider((etablissementId: widget.etablissementId, exerciceId: id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercices = ref.watch(exercicesComptablesProvider(widget.etablissementId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pièces comptables'),
        actions: [
          IconButton(
            tooltip: 'Exercices et clôtures',
            icon: const Icon(Icons.event_available_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EcranExercicesComptables(etablissementId: widget.etablissementId),
            )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('nouvelle_piece'),
        onPressed: () => _ouvrirSaisie(),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle pièce'),
      ),
      body: exercices.when(
        loading: () => ListView(padding: const EdgeInsets.all(16), children: List.generate(4, (_) => const ShimmerCarteListe())),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (liste) {
          if (liste.isEmpty) {
            return _AucunExercice(etablissementId: widget.etablissementId);
          }
          final courant = liste.where((x) => x.id == _exerciceId).firstOrNull ?? _exerciceParDefaut(liste)!;
          _exerciceId = courant.id;
          final pieces = ref.watch(piecesComptablesProvider((etablissementId: widget.etablissementId, exerciceId: courant.id)));

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const Key('choix_exercice'),
                      initialValue: courant.id,
                      decoration: const InputDecoration(labelText: 'Exercice', isDense: true),
                      items: [
                        for (final x in liste)
                          DropdownMenuItem(
                            value: x.id,
                            child: Text('${x.libelle}${x.cloture ? ' (clôturé)' : ''}'),
                          ),
                      ],
                      onChanged: (v) => setState(() => _exerciceId = v),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SegmentedButton<_Filtre>(
                  segments: const [
                    ButtonSegment(value: _Filtre.toutes, label: Text('Toutes')),
                    ButtonSegment(value: _Filtre.brouillards, label: Text('Brouillards')),
                    ButtonSegment(value: _Filtre.validees, label: Text('Validées')),
                  ],
                  selected: {_filtre},
                  onSelectionChanged: (s) => setState(() => _filtre = s.first),
                ),
              ),
              Expanded(
                child: pieces.when(
                  loading: () => ListView(padding: const EdgeInsets.all(16), children: List.generate(4, (_) => const ShimmerCarteListe())),
                  error: (e, _) => const Center(child: Text('Pièces indisponibles hors connexion.')),
                  data: (toutes) {
                    final visibles = toutes.where((p) => switch (_filtre) {
                          _Filtre.toutes => true,
                          _Filtre.brouillards => !p.estValidee,
                          _Filtre.validees => p.estValidee,
                        }).toList();
                    if (visibles.isEmpty) {
                      return const Center(child: Text('Aucune pièce pour ce filtre.'));
                    }
                    return RefreshIndicator(
                      onRefresh: () async => _rafraichir(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: visibles.length,
                        itemBuilder: (context, i) => _CartePiece(
                          piece: visibles[i],
                          onTap: () async {
                            final change = await Navigator.of(context).push<bool>(MaterialPageRoute(
                              builder: (_) => EcranDetailPiece(etablissementId: widget.etablissementId, pieceId: visibles[i].id),
                            ));
                            if (change == true) _rafraichir();
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AucunExercice extends StatelessWidget {
  const _AucunExercice({required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.event_note_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Aucun exercice comptable. Ouvrez votre premier exercice pour saisir des pièces.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EcranExercicesComptables(etablissementId: etablissementId),
              )),
              child: const Text('Ouvrir un exercice'),
            ),
          ]),
        ),
      );
}

class _CartePiece extends StatelessWidget {
  const _CartePiece({required this.piece, required this.onTap});

  final PieceComptable piece;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (icone, couleur, etat) = !piece.estValidee
        ? (Icons.edit_note_outlined, palette.accent, 'Brouillard')
        : piece.estAnnulee
            ? (Icons.block_outlined, palette.encreSecondaire, 'Annulée')
            : piece.origine == OriginePiece.contrepassation
                ? (Icons.undo_outlined, palette.encreSecondaire, 'Contre-passation')
                : (Icons.verified_outlined, palette.primaire, 'Validée');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(backgroundColor: couleur.withValues(alpha: 0.12), child: Icon(icone, color: couleur)),
        title: Text(piece.libelle, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('${dateCourte(piece.datePiece)} · ${piece.reference ?? 'sans numéro'} · $etat'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// Détail d'une pièce : lignes, actions selon l'état (valider, modifier,
/// supprimer le brouillard ; contre-passer une pièce validée).
class EcranDetailPiece extends ConsumerStatefulWidget {
  const EcranDetailPiece({super.key, required this.etablissementId, required this.pieceId});

  final String etablissementId;
  final String pieceId;

  @override
  ConsumerState<EcranDetailPiece> createState() => _EcranDetailPieceState();
}

class _EcranDetailPieceState extends ConsumerState<EcranDetailPiece> {
  bool _enCours = false;

  Future<void> _action(Future<String?> Function() action) async {
    setState(() => _enCours = true);
    try {
      final message = await action();
      if (!mounted) return;
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } on ErreurPiecesComptables catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _contrepasser(PieceComptable piece) async {
    final choix = await showDialog<({String motif, DateTime date})>(
      context: context,
      builder: (_) => _DialogueContrepassation(piece: piece),
    );
    if (choix == null || !mounted) return;
    await _action(() async {
      await ref.read(piecesComptablesRepositoryProvider).contrepasser(piece.id, choix.motif, choix.date);
      ref.invalidate(pieceComptableDetailProvider(widget.pieceId));
      return 'Pièce annulée par contre-passation.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(pieceComptableDetailProvider(widget.pieceId));
    final depot = ref.read(piecesComptablesRepositoryProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Pièce comptable')),
        body: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(e is ErreurPiecesComptables ? e.messageUtilisateur : 'Pièce indisponible hors connexion.'),
          ),
          data: (piece) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(piece.libelle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                [
                  dateCourte(piece.datePiece),
                  piece.reference ?? 'Brouillard (sans numéro)',
                  if (piece.journalCode != null) 'Journal ${piece.journalCode}',
                  if (piece.origine != OriginePiece.saisie) piece.origine.libelle,
                ].join(' · '),
                key: const Key('entete_piece'),
              ),
              if (piece.pieceJustificative != null) ...[
                const SizedBox(height: 4),
                Text('Justificatif : ${piece.pieceJustificative}'),
              ],
              if (piece.estAnnulee) ...[
                const SizedBox(height: 8),
                Chip(
                  avatar: const Icon(Icons.block_outlined, size: 18),
                  label: const Text('Annulée par contre-passation'),
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                ),
              ],
              const SizedBox(height: 16),
              Card(
                child: Column(children: [
                  for (final l in piece.lignes)
                    ListTile(
                      dense: true,
                      title: Text('${l.compteCode} — ${l.compteIntitule}'),
                      subtitle: l.libelle == null ? null : Text(l.libelle!),
                      trailing: Text(
                        l.debit != 0 ? 'D ${formaterMontant(l.debit)}' : 'C ${formaterMontant(l.credit)}',
                      ),
                    ),
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    title: const Text('Totaux'),
                    trailing: Text('D ${formaterMontant(piece.totalDebit)} · C ${formaterMontant(piece.totalCredit)}'),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              if (!piece.estValidee) ...[
                FilledButton.icon(
                  key: const Key('valider_piece'),
                  onPressed: _enCours
                      ? null
                      : () => _action(() async {
                            final ref0 = await depot.valider(piece.id);
                            ref.invalidate(pieceComptableDetailProvider(widget.pieceId));
                            return 'Pièce $ref0 validée.';
                          }),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Valider'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _enCours
                      ? null
                      : () async {
                          final fait = await Navigator.of(context).push<bool>(MaterialPageRoute(
                            builder: (_) => EcranSaisiePiece(etablissementId: widget.etablissementId, brouillard: piece),
                          ));
                          if (fait == true) ref.invalidate(pieceComptableDetailProvider(widget.pieceId));
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('supprimer_brouillard'),
                  onPressed: _enCours
                      ? null
                      : () => _action(() async {
                            await depot.supprimerBrouillard(piece.id);
                            if (context.mounted) Navigator.of(context).pop(true);
                            return null;
                          }),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer le brouillard'),
                ),
              ] else if (piece.contrepassable)
                OutlinedButton.icon(
                  key: const Key('contrepasser_piece'),
                  onPressed: _enCours ? null : () => _contrepasser(piece),
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('Annuler par contre-passation'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialogue de contre-passation : il possède son champ de saisie (libéré
/// avec lui, après l'animation de fermeture) et renvoie motif et date.
class _DialogueContrepassation extends StatefulWidget {
  const _DialogueContrepassation({required this.piece});

  final PieceComptable piece;

  @override
  State<_DialogueContrepassation> createState() => _DialogueContrepassationState();
}

class _DialogueContrepassationState extends State<_DialogueContrepassation> {
  final _motif = TextEditingController();
  late DateTime _date =
      DateTime.now().isBefore(widget.piece.datePiece) ? widget.piece.datePiece : DateTime.now();
  bool _motifManquant = false;

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Annuler ${widget.piece.reference} ?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Une pièce de contre-passation, en montants négatifs, sera créée et validée. '
            'La pièce d\'origine reste visible, marquée « annulée ».'),
        const SizedBox(height: 12),
        TextField(
          key: const Key('motif_contrepassation'),
          controller: _motif,
          decoration: InputDecoration(
            labelText: 'Motif (obligatoire)',
            errorText: _motifManquant ? 'Indiquez le motif.' : null,
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: widget.piece.datePiece,
              lastDate: DateTime(2100),
            );
            if (d != null) setState(() => _date = d);
          },
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('Date : ${dateCourte(_date)}'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Retour')),
        FilledButton(
          key: const Key('confirmer_contrepassation'),
          onPressed: () {
            final motif = _motif.text.trim();
            if (motif.isEmpty) {
              setState(() => _motifManquant = true);
              return;
            }
            Navigator.of(context).pop((motif: motif, date: _date));
          },
          child: const Text('Contre-passer'),
        ),
      ],
    );
  }
}
