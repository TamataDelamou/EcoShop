import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../application/notes_providers.dart';
import '../domain/enums_notes.dart';
import '../domain/evaluation.dart';
import 'ecran_saisie_notes.dart';
import 'widgets/pastille_statut_evaluation.dart';

/// Évaluations d'une classe (M6) — point d'entrée du mode enseignant.
class EcranEvaluationsClasse extends ConsumerWidget {
  const EcranEvaluationsClasse({super.key, required this.classe});

  final Classe classe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evaluations = ref.watch(
      evaluationsDeClasseProvider((classeId: classe.id, periodeId: null)),
    );

    return Scaffold(
      appBar: AppBar(title: Text('Évaluations — ${classe.nom}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _creerEvaluation(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle évaluation'),
      ),
      body: evaluations.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(4, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Évaluations indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucune évaluation créée pour cette classe.'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: liste.length,
                itemBuilder: (context, i) => EntreeAnimee(
                  index: i,
                  enfant: _CarteEvaluation(classe: classe, evaluation: liste[i]),
                ),
              ),
      ),
    );
  }

  Future<void> _creerEvaluation(BuildContext context, WidgetRef ref) async {
    final profil = ref.read(profilProvider).value;
    if (profil == null) return;

    final resultat = await showModalBottomSheet<Evaluation>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FeuilleNouvelleEvaluation(classe: classe, enseignantProfileId: profil.id),
    );

    if (resultat != null && context.mounted) {
      ref.invalidate(evaluationsDeClasseProvider((classeId: classe.id, periodeId: null)));
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EcranSaisieNotes(evaluation: resultat, classe: classe)),
      );
    }
  }
}

class _CarteEvaluation extends ConsumerWidget {
  const _CarteEvaluation({required this.classe, required this.evaluation});

  final Classe classe;
  final Evaluation evaluation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(Icons.assignment_outlined, color: context.palette.primaire),
        title: Text(evaluation.libelle),
        subtitle: Text(
          '${evaluation.type.libelle} · ${evaluation.nomMatiere ?? 'Matière non précisée'} '
          '· coef. ${evaluation.coefficient.toStringAsFixed(0)}',
        ),
        trailing: PastilleStatutEvaluation(statut: evaluation.statut),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EcranSaisieNotes(evaluation: evaluation, classe: classe)),
        ),
      ),
    );
  }
}

class _FeuilleNouvelleEvaluation extends ConsumerStatefulWidget {
  const _FeuilleNouvelleEvaluation({required this.classe, required this.enseignantProfileId});

  final Classe classe;
  final String enseignantProfileId;

  @override
  ConsumerState<_FeuilleNouvelleEvaluation> createState() => _FeuilleNouvelleEvaluationState();
}

class _FeuilleNouvelleEvaluationState extends ConsumerState<_FeuilleNouvelleEvaluation> {
  final _libelleCtrl = TextEditingController();
  final _coefficientCtrl = TextEditingController(text: '1');
  final _baremeCtrl = TextEditingController(text: '20');
  TypeEvaluation _type = TypeEvaluation.controle;
  DateTime _date = DateTime.now();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _libelleCtrl.dispose();
    _coefficientCtrl.dispose();
    _baremeCtrl.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final libelle = _libelleCtrl.text.trim();
    final coefficient = double.tryParse(_coefficientCtrl.text.replaceAll(',', '.'));
    final bareme = double.tryParse(_baremeCtrl.text.replaceAll(',', '.'));

    if (libelle.isEmpty || coefficient == null || coefficient <= 0 || bareme == null || bareme <= 0) {
      setState(() => _erreur = 'Vérifiez le libellé, le coefficient et le barème.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final creee = await ref.read(notesRepositoryProvider).creerEvaluation(
            Evaluation(
              id: '',
              etablissementId: widget.classe.etablissementId,
              anneeScolaireId: widget.classe.anneeScolaireId,
              classeId: widget.classe.id,
              enseignantProfileId: widget.enseignantProfileId,
              libelle: libelle,
              dateEvaluation: _date,
              type: _type,
              coefficient: coefficient,
              bareme: bareme,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(creee);
    } catch (_) {
      if (!mounted) return;
      setState(() => _erreur = "Impossible de créer l'évaluation — réessayez.");
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nouvelle évaluation', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _libelleCtrl,
              decoration: const InputDecoration(labelText: 'Libellé', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TypeEvaluation>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
              items: [
                for (final t in TypeEvaluation.values)
                  DropdownMenuItem(value: t, child: Text(t.libelle)),
              ],
              onChanged: (v) => setState(() => _type = v ?? TypeEvaluation.controle),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _coefficientCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Coefficient', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _baremeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Barème', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final choisie = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(_date.year - 1),
                  lastDate: DateTime(_date.year + 1),
                );
                if (choisie != null) setState(() => _date = choisie);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(
                '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
              ),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: TextStyle(color: context.palette.erreur)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _enCours ? null : _valider,
              child: _enCours
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }
}
