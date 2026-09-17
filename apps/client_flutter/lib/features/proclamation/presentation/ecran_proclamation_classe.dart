import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../scolarite/domain/classe.dart';
import '../application/proclamation_providers.dart';
import '../domain/eleve_mention.dart';
import '../domain/proclamation_repository.dart';

/// Verrou définitif des notes + mention admis(e)/recalé(e) pour les classes
/// d'examen (cahier §12.3, §12.4, §7.3). Réservé à la Direction — la
/// véritable autorité reste la RPC serveur (`est_direction`, RLS), défense
/// en profondeur, même discipline que `EcranGenerationBulletinsClasse`.
class EcranProclamationClasse extends ConsumerStatefulWidget {
  const EcranProclamationClasse({super.key, required this.classe});

  final Classe classe;

  @override
  ConsumerState<EcranProclamationClasse> createState() => _EcranProclamationClasseState();
}

class _EcranProclamationClasseState extends ConsumerState<EcranProclamationClasse> {
  String? _erreur;
  bool _proclamationEnCours = false;
  final Set<String> _mentionsEnCours = {};

  ({String classeId, String anneeScolaireId}) get _argsProclamee =>
      (classeId: widget.classe.id, anneeScolaireId: widget.classe.anneeScolaireId);

  void _rafraichirTout() {
    ref.invalidate(classeEstProclameeProvider(_argsProclamee));
    ref.invalidate(elevesDeClasseMentionProvider(widget.classe.id));
  }

  Future<void> _definirMention(EleveMention eleve, String mention) async {
    setState(() {
      _erreur = null;
      _mentionsEnCours.add(eleve.inscriptionId);
    });
    try {
      await ref.read(proclamationRepositoryProvider).definirMentionFinale(
            inscriptionId: eleve.inscriptionId,
            mention: mention,
          );
      ref.invalidate(elevesDeClasseMentionProvider(widget.classe.id));
    } on ErreurProclamation catch (e) {
      if (mounted) setState(() => _erreur = _messageErreur(e.code));
    } finally {
      if (mounted) setState(() => _mentionsEnCours.remove(eleve.inscriptionId));
    }
  }

  Future<bool> _confirmerProclamation() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Proclamer cette classe ?'),
        content: const Text(
          'Une fois proclamée, aucune note, appréciation ou mention de '
          'cette classe pour cette année ne pourra plus jamais être '
          'modifiée — y compris par l\'Administrateur GSG. Cette action '
          'est définitive et irréversible.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Proclamer')),
        ],
      ),
    );
    return confirme ?? false;
  }

  Future<void> _proclamer() async {
    if (!await _confirmerProclamation()) return;

    setState(() {
      _proclamationEnCours = true;
      _erreur = null;
    });
    try {
      await ref.read(proclamationRepositoryProvider).proclamerClasse(
            classeId: widget.classe.id,
            anneeScolaireId: widget.classe.anneeScolaireId,
          );
      _rafraichirTout();
    } on ErreurProclamation catch (e) {
      if (mounted) setState(() => _erreur = _messageErreur(e.code));
    } finally {
      if (mounted) setState(() => _proclamationEnCours = false);
    }
  }

  String _messageErreur(String code) => switch (code) {
        'MENTION_MANQUANTE' =>
          'Impossible de proclamer : un ou plusieurs élèves n\'ont pas encore de mention finale.',
        'CLASSE_DEJA_PROCLAMEE' => 'Cette classe est déjà proclamée — verrou définitif.',
        'PERMISSION_REFUSEE' => 'Action réservée à la Direction de l\'établissement.',
        _ => 'Une erreur est survenue — réessayez.',
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final estExamenAsync = ref.watch(classeEstExamenProvider(widget.classe.id));
    final estProclameeAsync = ref.watch(classeEstProclameeProvider(_argsProclamee));
    final elevesAsync = ref.watch(elevesDeClasseMentionProvider(widget.classe.id));

    return Scaffold(
      appBar: AppBar(title: Text('Proclamation - ${widget.classe.nom}')),
      body: switch ((estExamenAsync, estProclameeAsync, elevesAsync)) {
        (AsyncData(value: final estExamen), AsyncData(value: final estProclamee), AsyncData(value: final eleves)) =>
          _corps(estExamen: estExamen, estProclamee: estProclamee, eleves: eleves, palette: palette),
        (AsyncError(), _, _) || (_, AsyncError(), _) || (_, _, AsyncError()) => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Indisponible hors connexion pour le moment.'),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _corps({
    required bool estExamen,
    required bool estProclamee,
    required List<EleveMention> eleves,
    required AppPalette palette,
  }) {
    if (estProclamee) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: palette.succes),
              const SizedBox(height: 16),
              Text(
                'Classe proclamée — verrouillage définitif.',
                style: TextStyle(color: palette.succes, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (!estExamen)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Cette classe n\'est pas une classe d\'examen — aucune mention '
              'requise avant proclamation.',
              style: TextStyle(color: palette.encreSecondaire),
            ),
          ),
        Expanded(
          child: estExamen
              ? ListView.builder(
                  itemCount: eleves.length,
                  itemBuilder: (context, i) {
                    final eleve = eleves[i];
                    final enCours = _mentionsEnCours.contains(eleve.inscriptionId);
                    return ListTile(
                      title: Text('${eleve.prenom} ${eleve.nom}'),
                      subtitle: eleve.mentionFinale == null
                          ? const Text('Mention non définie')
                          : Text(eleve.mentionFinale == 'admis' ? 'Admis(e)' : 'Recalé(e)'),
                      trailing: enCours
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'admis', label: Text('Admis(e)')),
                                ButtonSegment(value: 'recale', label: Text('Recalé(e)')),
                              ],
                              selected: eleve.mentionFinale == null ? const {} : {eleve.mentionFinale!},
                              emptySelectionAllowed: true,
                              onSelectionChanged: (selection) {
                                if (selection.isEmpty) return;
                                _definirMention(eleve, selection.first);
                              },
                            ),
                    );
                  },
                )
              : const SizedBox.shrink(),
        ),
        if (_erreur != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_erreur!, style: TextStyle(color: palette.erreur)),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _proclamationEnCours ? null : _proclamer,
              icon: _proclamationEnCours
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.gavel_outlined),
              label: const Text('Proclamer la classe'),
            ),
          ),
        ),
      ],
    );
  }
}
