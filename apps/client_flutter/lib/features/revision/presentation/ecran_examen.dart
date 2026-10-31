import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/revision_providers.dart';
import '../domain/examen.dart';
import '../domain/question.dart';
import '../domain/quiz.dart';
import 'champ_reponse.dart';

/// Examen blanc (cahier 11.2) : les conditions d'un vrai examen pour
/// s'entraîner à gérer le temps et le stress (la pratique en conditions
/// réelles rend moins anxieux le jour J). Correction après la remise
/// seulement, même si l'élève revient en arrière.
class EcranExamen extends ConsumerStatefulWidget {
  const EcranExamen({
    super.key,
    required this.examen,
    this.competences = const {},
    this.petitesClasses = false,
    this.maintenant,
    this.hasard,
  });

  final SessionExamen examen;

  /// Compétence → libellé, pour les points forts et à renforcer.
  final Map<String, String> competences;
  final bool petitesClasses;

  /// Heure courante, remplaçable en test.
  final DateTime Function()? maintenant;
  final Random? hasard;

  @override
  ConsumerState<EcranExamen> createState() => _EcranExamenState();
}

class _EcranExamenState extends ConsumerState<EcranExamen> {
  SessionExamen get _e => widget.examen;
  late final Random _hasard = widget.hasard ?? Random();
  DateTime _maintenant() => (widget.maintenant ?? DateTime.now)();
  int _index = 0;
  Timer? _minuteur;
  bool? _recu;

  @override
  void initState() {
    super.initState();
    _minuteur = Timer.periodic(const Duration(seconds: 1), (_) => _tic());
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  void _tic() {
    if (!mounted || _e.remis) return;
    if (_e.tempsEcoule(_maintenant()) && _e.remiseAutomatique) {
      _remettre(automatique: true);
    } else {
      setState(() {});
    }
  }

  Future<void> _remettre({bool automatique = false}) async {
    if (_e.remis) return;
    _minuteur?.cancel();
    setState(() => _e.remettre(_maintenant(), automatique: automatique));
    try {
      final recu = await ref.read(revisionRepositoryProvider).enregistrerExamen(_e);
      if (mounted) setState(() => _recu = recu);
    } catch (_) {
      if (mounted) setState(() => _recu = false);
    }
    ref.invalidate(espaceRevisionProvider(_e.ficheId));
    ref.invalidate(progressionRevisionProvider);
  }

  Future<void> _confirmerRemise() async {
    final reste = _e.nonRepondues;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remettre ta copie ?'),
        content: Text(reste == 0
            ? 'Tu as répondu à toutes les questions. Après la remise, tu ne pourras plus rien changer.'
            : 'Il reste $reste question${reste > 1 ? 's' : ''} sans réponse. Après la remise, tu ne pourras plus rien changer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Continuer')),
          FilledButton(key: const Key('examen_confirmer_remise'), onPressed: () => Navigator.of(d).pop(true), child: const Text('Remettre')),
        ],
      ),
    );
    if (ok == true) await _remettre();
  }

  Future<void> _quitter() async {
    if (_e.remis) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Quitter l’examen ?'),
        content: const Text('Ta copie sera remise telle qu’elle est, comme à la fin d’un vrai examen.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Continuer')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Remettre et quitter')),
        ],
      ),
    );
    if (ok != true) return;
    await _remettre();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final restant = _e.restantS(_maintenant());
    final schema = Theme.of(context).colorScheme;
    final presqueFini = restant <= 60;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (aQuitte, _) {
        if (!aQuitte) _quitter();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _quitter),
          title: Text(_e.remis ? 'Résultat de l’examen' : 'Examen blanc'),
          actions: [
            if (!_e.remis)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    !_e.remiseAutomatique && restant == 0
                        ? '+${chrono(_e.depassementS(_maintenant()))}'
                        : chrono(restant),
                    key: const Key('examen_chrono'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: presqueFini ? schema.error : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(child: _e.remis ? _resultat(context) : _copie(context)),
      ),
    );
  }

  Widget _copie(BuildContext context) {
    final q = _e.questions[_index];
    final schema = Theme.of(context).colorScheme;
    return Column(children: [
      // Navigation : une pastille par question, pleine si répondue.
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (var i = 0; i < _e.questions.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  key: ValueKey('examen_aller_$i'),
                  label: Text('${i + 1}'),
                  selected: i == _index,
                  avatar: _e.completes.contains(i) ? const Icon(Icons.check, size: 16) : null,
                  onSelected: (_) => setState(() => _index = i),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (!_e.remiseAutomatique)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _e.restantS(_maintenant()) == 0
                      ? 'Le temps conseillé est passé : prends le temps de finir, puis remets ta copie.'
                      : 'Chronomètre indicatif : ta copie n’est pas ramassée à la fin du temps.',
                  key: const Key('examen_chrono_indicatif'),
                  style: TextStyle(color: schema.tertiary),
                ),
              ),
            Text('Question ${_index + 1} sur ${_e.questions.length}', style: TextStyle(color: schema.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              q.contenu.type == TypeQuestion.texteATrous
                  ? q.contenu.enonce.replaceAllMapped(ContenuQuestion.motifTrou, (m) => '……(${m.group(1)})')
                  : q.contenu.enonce,
              key: const Key('examen_enonce'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ChampReponse(
              key: ValueKey('examen_reponse_$_index'),
              question: q,
              initiale: _e.reponses[_index],
              petitesClasses: widget.petitesClasses,
              hasard: _hasard,
              onChanged: (d, complete) {
                final avant = _e.completes.contains(_index);
                _e.repondre(_index, d, complete: complete);
                if (avant != complete) setState(() {});
              },
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          OutlinedButton(
            key: const Key('examen_precedente'),
            onPressed: _index == 0 ? null : () => setState(() => _index--),
            child: const Text('Précédente'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _index < _e.questions.length - 1
                ? FilledButton.tonal(
                    key: const Key('examen_suivante'),
                    onPressed: () => setState(() => _index++),
                    child: const Text('Suivante'),
                  )
                : FilledButton(
                    key: const Key('examen_remettre'),
                    onPressed: _confirmerRemise,
                    child: const Text('Remettre ma copie'),
                  ),
          ),
        ]),
      ),
    ]);
  }

  Widget _resultat(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    String note(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString().replaceAll('.', ',');
    String libelle(BilanCompetence b) => widget.competences[b.competenceId] ?? 'Autres questions';
    final forts = _e.pointsForts();
    final faibles = _e.aRenforcer();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        if (_e.remiseParLeTemps)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Temps écoulé : ta copie a été remise automatiquement.',
                key: const Key('examen_remise_auto'), textAlign: TextAlign.center, style: TextStyle(color: schema.tertiary)),
          ),
        Text('${note(_e.noteSur20)} / 20', key: const Key('examen_note'), textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('${_e.justes} bonne${_e.justes > 1 ? 's' : ''} réponse${_e.justes > 1 ? 's' : ''}, '
            '${_e.fausses} à revoir · ${dureeLisible(_e.dureeS)}',
            key: const Key('examen_detail'), textAlign: TextAlign.center),
        if (_recu == false)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Gardé sur ce téléphone, envoyé au retour du réseau.',
                textAlign: TextAlign.center, style: TextStyle(color: schema.onSurfaceVariant)),
          ),
        const SizedBox(height: 8),
        Text('Examen blanc : il ne compte jamais dans les notes de l’école.',
            textAlign: TextAlign.center, style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
        if (forts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Points forts', style: Theme.of(context).textTheme.titleSmall),
          for (final b in forts)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.star_outline, color: Colors.green),
              title: Text(libelle(b)),
              trailing: Text('${(b.reussite * 100).round()} %'),
            ),
        ],
        if (faibles.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('À renforcer', style: Theme.of(context).textTheme.titleSmall),
          for (final b in faibles)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.flag_outlined, color: schema.tertiary),
              title: Text(libelle(b)),
              trailing: Text('${(b.reussite * 100).round()} %'),
            ),
        ],
        const SizedBox(height: 16),
        Text('Correction', style: Theme.of(context).textTheme.titleSmall),
        for (var i = 0; i < _e.questions.length; i++)
          Card(
            key: ValueKey('examen_correction_$i'),
            child: ListTile(
              leading: Icon(
                _e.corrections[i].juste ? Icons.check_circle : Icons.cancel_outlined,
                color: _e.corrections[i].juste ? Colors.green.shade700 : schema.error,
              ),
              title: Text('${i + 1}. ${_e.questions[i].contenu.enonce}', maxLines: 3, overflow: TextOverflow.ellipsis),
              subtitle: Text([
                if (!_e.completes.contains(i)) 'Sans réponse.',
                if (!_e.corrections[i].juste) 'Bonne réponse : ${_e.questions[i].contenu.bonneReponseLisible()}',
                _e.questions[i].contenu.explication,
              ].join('\n')),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(key: const Key('examen_terminer'), onPressed: () => Navigator.of(context).pop(), child: const Text('Terminer')),
      ],
    );
  }
}
