import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/sync/device_id_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../../scolarite/domain/inscription.dart';
import '../application/notes_providers.dart';
import '../domain/evaluation.dart';
import '../domain/note.dart';
import 'widgets/pastille_statut_evaluation.dart';

/// Grille de saisie des notes d'une classe pour une évaluation (M6, mode
/// enseignant) — fonctionne sans réseau : chaque ligne enregistrée hors
/// connexion part dans la file `sync_queue` et se resynchronise seule au
/// retour du réseau (contrat M06 §5, ch. 34-35).
class EcranSaisieNotes extends ConsumerWidget {
  const EcranSaisieNotes({super.key, required this.evaluation, required this.classe});

  final Evaluation evaluation;
  final Classe classe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inscriptions = ref.watch(inscriptionsDeClasseProvider(classe.id));
    final notes = ref.watch(notesDeEvaluationProvider(evaluation.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(evaluation.libelle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: PastilleStatutEvaluation(statut: evaluation.statut)),
          ),
        ],
      ),
      body: Column(
        children: [
          const _BandeauHorsLigneSaisie(),
          Expanded(
            child: switch ((inscriptions, notes)) {
              (AsyncData(value: final eleves), AsyncData(value: final lignes)) => _Grille(
                  evaluation: evaluation,
                  eleves: eleves,
                  notesParFiche: {for (final n in lignes) n.ficheEleveId: n},
                ),
              (AsyncError(), _) || (_, AsyncError()) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Impossible de charger la classe ou les notes.'),
                  ),
                ),
              _ => ListView(
                  padding: const EdgeInsets.all(16),
                  children: List.generate(6, (_) => const ShimmerCarteListe()),
                ),
            },
          ),
        ],
      ),
      bottomNavigationBar: evaluation.statut.code == 'brouillon'
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.publish_outlined),
                  label: const Text("Publier l'évaluation"),
                  onPressed: () async {
                    await ref.read(notesRepositoryProvider).publierEvaluation(evaluation.id);
                    ref.invalidate(evaluationsDeClasseProvider((classeId: classe.id, periodeId: null)));
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            )
          : null,
    );
  }
}

class _BandeauHorsLigneSaisie extends ConsumerWidget {
  const _BandeauHorsLigneSaisie();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(estEnLigneProvider)) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.orangePop.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: AppColors.orangePop),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hors ligne — les notes saisies seront envoyées au retour du réseau.',
              style: TextStyle(color: AppColors.orangePop, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Grille extends StatelessWidget {
  const _Grille({required this.evaluation, required this.eleves, required this.notesParFiche});

  final Evaluation evaluation;
  final List<Inscription> eleves;
  final Map<String, Note> notesParFiche;

  @override
  Widget build(BuildContext context) {
    if (eleves.isEmpty) {
      return const Center(child: Text('Aucun élève inscrit dans cette classe.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: eleves.length,
      itemBuilder: (context, i) {
        final inscription = eleves[i];
        return _LigneSaisie(
          evaluation: evaluation,
          inscription: inscription,
          noteExistante: notesParFiche[inscription.ficheEleveId],
        );
      },
    );
  }
}

enum _EtatLigne { repos, enCours, synchronise, enAttente, erreur }

class _LigneSaisie extends ConsumerStatefulWidget {
  const _LigneSaisie({required this.evaluation, required this.inscription, this.noteExistante});

  final Evaluation evaluation;
  final Inscription inscription;
  final Note? noteExistante;

  @override
  ConsumerState<_LigneSaisie> createState() => _LigneSaisieState();
}

class _LigneSaisieState extends ConsumerState<_LigneSaisie> {
  late final TextEditingController _valeurCtrl =
      TextEditingController(text: widget.noteExistante?.valeur?.toString() ?? '');
  late bool _absent = widget.noteExistante?.absent ?? false;
  _EtatLigne _etat = _EtatLigne.repos;

  @override
  void dispose() {
    _valeurCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final profil = ref.read(profilProvider).value;
    if (profil == null) return;

    final valeur = _absent ? null : double.tryParse(_valeurCtrl.text.replaceAll(',', '.'));
    if (!_absent && valeur == null) {
      setState(() => _etat = _EtatLigne.erreur);
      return;
    }
    if (!_absent && valeur! > widget.evaluation.bareme) {
      setState(() => _etat = _EtatLigne.erreur);
      return;
    }

    setState(() => _etat = _EtatLigne.enCours);

    final deviceId = await ref.read(deviceIdProvider.future);
    final enLigne = ref.read(estEnLigneProvider);
    final note = construireNoteSaisie(
      etablissementId: widget.evaluation.etablissementId,
      evaluationId: widget.evaluation.id,
      ficheEleveId: widget.inscription.ficheEleveId,
      saisiPar: profil.id,
      deviceId: deviceId,
      enLigne: enLigne,
      valeur: valeur,
      absent: _absent,
    );

    try {
      final synchronisee = await ref.read(notesRepositoryProvider).saisirNote(note);
      if (!mounted) return;
      setState(() => _etat = synchronisee ? _EtatLigne.synchronise : _EtatLigne.enAttente);
    } catch (_) {
      if (!mounted) return;
      setState(() => _etat = _EtatLigne.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nom = widget.inscription.fiche?.nomComplet ?? 'Élève';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(nom, overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _valeurCtrl,
                enabled: !_absent,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '/${widget.evaluation.bareme.toStringAsFixed(0)}',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _absent,
                  onChanged: (v) => setState(() => _absent = v ?? false),
                ),
                const Text('Absent', style: TextStyle(fontSize: 10)),
              ],
            ),
            const SizedBox(width: 4),
            _BoutonEtat(etat: _etat, onAppui: _enregistrer),
          ],
        ),
      ),
    );
  }
}

class _BoutonEtat extends StatelessWidget {
  const _BoutonEtat({required this.etat, required this.onAppui});

  final _EtatLigne etat;
  final VoidCallback onAppui;

  @override
  Widget build(BuildContext context) {
    return switch (etat) {
      _EtatLigne.enCours => const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      _EtatLigne.synchronise =>
        IconButton(icon: const Icon(Icons.check_circle, color: AppColors.vertMenthe), onPressed: onAppui),
      _EtatLigne.enAttente =>
        IconButton(icon: const Icon(Icons.cloud_off, color: AppColors.orangePop), onPressed: onAppui),
      _EtatLigne.erreur =>
        IconButton(icon: const Icon(Icons.error_outline, color: AppColors.erreur), onPressed: onAppui),
      _EtatLigne.repos =>
        IconButton(icon: const Icon(Icons.save_outlined, color: AppColors.bleuElectrique), onPressed: onAppui),
    };
  }
}
