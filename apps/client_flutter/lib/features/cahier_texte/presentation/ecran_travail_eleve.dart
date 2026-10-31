import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../revision/domain/concours.dart';
import '../../revision/domain/examen.dart' show chrono;
import '../../revision/domain/question.dart';
import '../../revision/domain/quiz.dart';
import '../../revision/presentation/champ_reponse.dart';
import '../data/cahier_repository.dart';
import '../domain/cahier.dart';
import 'elements_cahier.dart';

/// Travail et cahier de texte d'un élève (REG-40), pour l'élève lui-même ou
/// pour son parent. « À faire » regroupé par échéance avec le temps prévu
/// chaque jour, « Fait » coché même sans réseau, cahier de texte de la
/// classe, devoirs numériques.
class EcranTravailEleve extends ConsumerStatefulWidget {
  const EcranTravailEleve({super.key, required this.ficheId, this.prenom, this.parent = false});

  final String ficheId;
  final String? prenom;

  /// Vu par un parent : les textes parlent de l'enfant.
  final bool parent;

  @override
  ConsumerState<EcranTravailEleve> createState() => _EcranTravailEleveState();
}

class _EcranTravailEleveState extends ConsumerState<EcranTravailEleve> {
  Future<void> _basculer(TravailEleve t, bool fait) async {
    try {
      await ref.read(cahierRepositoryProvider).marquerFait(t.id, widget.ficheId, fait);
    } on ErreurCahier catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    ref.invalidate(travauxFicheProvider(widget.ficheId));
  }

  void _ouvrirDevoir(TravailEleve t) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => EcranDevoir(ficheId: widget.ficheId, travail: t)))
        .then((_) => ref.invalidate(travauxFicheProvider(widget.ficheId)));
  }

  @override
  Widget build(BuildContext context) {
    final titre = widget.parent && widget.prenom != null ? 'Travail de ${widget.prenom}' : 'Mon travail';
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(titre),
          bottom: const TabBar(tabs: [Tab(text: 'À faire'), Tab(text: 'Cahier de texte'), Tab(text: 'Fait')]),
        ),
        body: TabBarView(children: [
          _listeTravaux(afaire: true),
          _OngletCahier(ficheId: widget.ficheId),
          _listeTravaux(afaire: false),
        ]),
      ),
    );
  }

  Widget _listeTravaux({required bool afaire}) {
    final travaux = ref.watch(travauxFicheProvider(widget.ficheId));
    final maintenant = DateTime.now();
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(travauxFicheProvider(widget.ficheId)),
      child: travaux.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(e is ErreurCahier ? e.message : 'Travail indisponible pour le moment.', textAlign: TextAlign.center),
          ),
        ]),
        data: (tous) {
          final liste = afaire
              ? ([for (final t in tous) if (!t.termine) t]..sort((a, b) => a.pourLe.compareTo(b.pourLe)))
              : ([for (final t in tous) if (t.termine) t]..sort((a, b) => b.pourLe.compareTo(a.pourLe)));
          if (liste.isEmpty) {
            return ListView(children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  afaire ? 'Rien à faire pour le moment. Bravo !' : 'Rien de terminé ces 30 derniers jours.',
                  key: Key(afaire ? 'rien_a_faire' : 'rien_de_fait'),
                  textAlign: TextAlign.center,
                ),
              ),
            ]);
          }
          final charge = chargeParJour([for (final t in liste) (pourLe: t.pourLe, minutes: t.tempsEstimeMin)]);
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
            for (final (i, t) in liste.indexed) ...[
              if (afaire && (i == 0 || jour(liste[i - 1].pourLe) != jour(t.pourLe)))
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        t.enRetardLe(maintenant) ? 'En retard — ${dateLisible(t.pourLe).toLowerCase()}' : 'Pour ${dateLisible(t.pourLe).toLowerCase()}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: t.enRetardLe(maintenant) ? Theme.of(context).colorScheme.error : null,
                        ),
                      ),
                    ),
                    Text('≈ ${minutesLisibles(charge[jour(t.pourLe)] ?? 0)}'),
                  ]),
                ),
              _CarteTravail(
                travail: t,
                onFait: t.estDevoir ? null : (v) => _basculer(t, v),
                onDevoir: t.estDevoir ? () => _ouvrirDevoir(t) : null,
              ),
            ],
          ]);
        },
      ),
    );
  }
}

class _CarteTravail extends StatelessWidget {
  const _CarteTravail({required this.travail, this.onFait, this.onDevoir});

  final TravailEleve travail;
  final ValueChanged<bool>? onFait;
  final VoidCallback? onDevoir;

  @override
  Widget build(BuildContext context) {
    final t = travail;
    final schema = Theme.of(context).colorScheme;
    return Card(
      key: Key('travail_eleve_${t.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(iconeTravail(t.type), color: schema.primary)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text([t.matiere, t.type.libelle].whereType<String>().join(' · '),
                  style: TextStyle(fontSize: 12, color: schema.primary)),
              Text(t.titre, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (t.consigne != null) ...[const SizedBox(height: 2), Text(t.consigne!)],
              const SizedBox(height: 4),
              Text(
                [
                  minutesLisibles(t.tempsEstimeMin),
                  if (t.estDevoir) '${t.nbQuestions} questions',
                  if (t.dureeMin != null) 'chronométré ${t.dureeMin} min',
                  if (t.enseignant != null && t.enseignant!.isNotEmpty) t.enseignant!,
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: schema.onSurfaceVariant),
              ),
              if (t.piecesJointes.isNotEmpty) ...[const SizedBox(height: 6), PiecesJointes(pieces: t.piecesJointes)],
              if (t.estDevoir) ...[
                const SizedBox(height: 6),
                t.remisLe != null
                    ? OutlinedButton.icon(
                        key: Key('voir_devoir_${t.id}'),
                        onPressed: onDevoir,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: Text(t.score == null || t.nbQuestions == 0
                            ? 'Remis — voir'
                            : 'Remis : ${(t.score! * 20 / t.nbQuestions).toStringAsFixed(1).replaceAll('.', ',')}/20 — voir'),
                      )
                    : FilledButton.icon(
                        key: Key('faire_devoir_${t.id}'),
                        onPressed: onDevoir,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Faire le devoir'),
                      ),
              ],
            ]),
          ),
          if (onFait != null)
            Checkbox(
              key: Key('fait_${t.id}'),
              value: t.faitLe != null,
              onChanged: (v) => onFait!(v ?? false),
            ),
        ]),
      ),
    );
  }
}

class _OngletCahier extends ConsumerWidget {
  const _OngletCahier({required this.ficheId});

  final String ficheId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cahier = ref.watch(cahierFicheProvider(ficheId));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(cahierFicheProvider(ficheId)),
      child: cahier.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(e is ErreurCahier ? e.message : 'Cahier indisponible pour le moment.', textAlign: TextAlign.center),
          ),
        ]),
        data: (liste) => liste.isEmpty
            ? ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Les enseignants n’ont encore rien noté ces dernières semaines.', textAlign: TextAlign.center),
                ),
              ])
            : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
                for (final (i, s) in liste.indexed) ...[
                  if (i == 0 || jour(liste[i - 1].date) != jour(s.date))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                      child: Text(dateLisible(s.date), style: Theme.of(context).textTheme.titleSmall),
                    ),
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text([s.matiere, s.chapitre].whereType<String>().join(' · '),
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                        Text(s.titre, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (s.contenu != null) ...[const SizedBox(height: 4), Text(s.contenu!)],
                        if (s.piecesJointes.isNotEmpty) ...[const SizedBox(height: 6), PiecesJointes(pieces: s.piecesJointes)],
                      ]),
                    ),
                  ),
                ],
              ]),
      ),
    );
  }
}

/// Devoir numérique : sujet gardé sur le téléphone (sans durée), réponses,
/// remise (envoyée au retour du réseau s'il manque), correction.
class EcranDevoir extends ConsumerStatefulWidget {
  const EcranDevoir({super.key, required this.ficheId, required this.travail});

  final String ficheId;
  final TravailEleve travail;

  @override
  ConsumerState<EcranDevoir> createState() => _EcranDevoirState();
}

class _EcranDevoirState extends ConsumerState<EcranDevoir> {
  SujetManche? _sujet;
  ResultatManche? _resultat;
  ErreurCahier? _erreur;
  final Map<String, Object?> _reponses = {};
  final Set<String> _completes = {};
  int _index = 0;
  bool _envoi = false;
  final _chrono = Stopwatch();
  Timer? _minuteur;

  bool get _chronometre => widget.travail.dureeMin != null;

  @override
  void initState() {
    super.initState();
    if (widget.travail.remisLe != null) {
      _chargerCorrection();
    } else {
      _charger();
    }
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _erreur = null);
    try {
      final s = await ref
          .read(cahierRepositoryProvider)
          .sujetDevoir(widget.travail.id, widget.ficheId, chronometre: _chronometre);
      if (!mounted) return;
      setState(() => _sujet = s);
      _chrono.start();
      if (_chronometre) _minuteur = Timer.periodic(const Duration(seconds: 1), (_) => _tic());
    } on ErreurCahier catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  Future<void> _chargerCorrection() async {
    try {
      final r = await ref.read(cahierRepositoryProvider).correction(widget.travail.id, widget.ficheId);
      if (mounted) setState(() => _resultat = r);
    } on ErreurCahier catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  int get _restantS => _sujet == null ? 0 : _sujet!.limite.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);

  void _tic() {
    if (!mounted || _resultat != null || _envoi) return;
    if (_restantS == 0) {
      _remettre();
    } else {
      setState(() {});
    }
  }

  Future<void> _remettre() async {
    final s = _sujet;
    if (_envoi || _resultat != null || s == null) return;
    _minuteur?.cancel();
    _chrono.stop();
    setState(() => _envoi = true);
    try {
      final r = await ref
          .read(cahierRepositoryProvider)
          .remettreDevoir(widget.travail.id, widget.ficheId, Map.of(_reponses), s.questions.length, _chrono.elapsed.inSeconds);
      if (mounted) setState(() => _resultat = r);
    } on ErreurCahier catch (e) {
      if (mounted) setState(() => _erreur = e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _confirmer() async {
    final reste = (_sujet?.questions.length ?? 0) - _completes.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remettre le devoir ?'),
        content: Text(reste <= 0
            ? 'Tu as répondu à tout. Après la remise, plus rien ne change.'
            : 'Il reste $reste question${reste > 1 ? 's' : ''} sans réponse. Après la remise, plus rien ne change.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Continuer')),
          FilledButton(key: const Key('devoir_confirmer'), onPressed: () => Navigator.of(d).pop(true), child: const Text('Remettre')),
        ],
      ),
    );
    if (ok == true) await _remettre();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_resultat != null ? 'Résultat' : widget.travail.titre, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_chronometre && _sujet != null && _resultat == null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(chrono(_restantS),
                    key: const Key('devoir_chrono'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: _restantS <= 60 ? Theme.of(context).colorScheme.error : null,
                    )),
              ),
            ),
        ],
      ),
      body: SafeArea(child: _corps(context)),
    );
  }

  Widget _corps(BuildContext context) {
    if (_resultat case final r?) return _vueResultat(context, r);
    if (_erreur case final e? when _sujet == null) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        Text(
          e.code == 'HORS_LIGNE'
              ? (_chronometre
                  ? 'Ce devoir est chronométré : il faut le réseau pour le commencer.'
                  : 'Pas de réseau, et ce devoir n’a pas encore été téléchargé sur ce téléphone. '
                      'Ouvre-le une fois connecté : tu pourras ensuite le faire sans réseau.')
              : e.message,
          key: const Key('devoir_erreur'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: widget.travail.remisLe != null ? _chargerCorrection : _charger, child: const Text('Réessayer')),
      ]);
    }
    final s = _sujet;
    if (s == null || _envoi) return const Center(child: CircularProgressIndicator());
    if (s.questions.isEmpty) return const Center(child: Text('Sujet vide.'));
    final q = s.questions[_index];
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (var i = 0; i < s.questions.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('${i + 1}'),
                  selected: i == _index,
                  avatar: _completes.contains(s.questions[i].id) ? const Icon(Icons.check, size: 16) : null,
                  onSelected: (_) => setState(() => _index = i),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          if (_erreur case final e?) Text(e.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Text('Question ${_index + 1} sur ${s.questions.length}'),
          const SizedBox(height: 8),
          Text(
            q.contenu.type == TypeQuestion.texteATrous
                ? q.contenu.enonce.replaceAllMapped(ContenuQuestion.motifTrou, (m) => '……(${m.group(1)})')
                : q.contenu.enonce,
            key: const Key('devoir_enonce'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          ChampReponse(
            key: ValueKey('devoir_reponse_${q.id}'),
            question: q,
            initiale: _reponses[q.id],
            onChanged: (d, complete) {
              _reponses[q.id] = d;
              final avant = _completes.contains(q.id);
              complete ? _completes.add(q.id) : _completes.remove(q.id);
              if (avant != complete) setState(() {});
            },
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          OutlinedButton(onPressed: _index == 0 ? null : () => setState(() => _index--), child: const Text('Précédente')),
          const SizedBox(width: 8),
          Expanded(
            child: _index < s.questions.length - 1
                ? FilledButton.tonal(key: const Key('devoir_suivante'), onPressed: () => setState(() => _index++), child: const Text('Suivante'))
                : FilledButton(key: const Key('devoir_remettre'), onPressed: _confirmer, child: const Text('Remettre le devoir')),
          ),
        ]),
      ),
    ]);
  }

  Widget _vueResultat(BuildContext context, ResultatManche r) {
    final schema = Theme.of(context).colorScheme;
    final questions = _sujet?.questions ?? const <QuestionQuiz>[];
    final note = r.questions == 0 ? 0.0 : r.score * 20 / r.questions;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 32), children: [
      if (r.enAttente)
        const Text('Pas de réseau : ton devoir est gardé sur ce téléphone et part dès le retour du réseau. '
            'La note arrivera ensuite.', key: Key('devoir_en_attente'), textAlign: TextAlign.center)
      else ...[
        Text('${note.toStringAsFixed(1).replaceAll('.', ',')} / 20',
            key: const Key('devoir_note'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        Text('${r.score.toStringAsFixed(1).replaceAll('.', ',')} bonne(s) réponse(s) sur ${r.questions}', textAlign: TextAlign.center),
        if (r.horsDelai)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Remis après la date limite.', textAlign: TextAlign.center, style: TextStyle(color: schema.error)),
          ),
        const SizedBox(height: 8),
        const Text('Devoir d’entraînement : il ne compte pas dans la moyenne, il t’aide à progresser.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        const SizedBox(height: 16),
        if (r.corrections.isEmpty)
          const Text('La correction s’affichera après la date limite.', textAlign: TextAlign.center)
        else if (questions.isNotEmpty) ...[
          Text('Correction', style: Theme.of(context).textTheme.titleSmall),
          for (final (i, q) in questions.indexed)
            if (r.contenuCorrige(q) case final c?)
              Card(
                child: ListTile(
                  leading: Icon(
                    (r.corrections[q.id]?.score ?? 0) >= 1 ? Icons.check_circle : Icons.cancel_outlined,
                    color: (r.corrections[q.id]?.score ?? 0) >= 1 ? Colors.green.shade700 : schema.error,
                  ),
                  title: Text('${i + 1}. ${c.enonce}', maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    if ((r.corrections[q.id]?.score ?? 0) < 1) 'Bonne réponse : ${c.bonneReponseLisible()}',
                    if (c.explication.isNotEmpty) c.explication,
                  ].join('\n')),
                ),
              ),
        ] else
          Text('${r.corrections.values.where((c) => c.score >= 1).length} réponse(s) juste(s). '
              'Le détail est sur le téléphone où le devoir a été fait.', textAlign: TextAlign.center),
      ],
      const SizedBox(height: 16),
      FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Terminer')),
    ]);
  }
}
