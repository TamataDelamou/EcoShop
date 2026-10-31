import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/concours_providers.dart';
import '../data/concours_repository.dart';
import '../domain/concours.dart';
import '../domain/examen.dart';
import '../domain/question.dart';
import '../domain/quiz.dart';
import 'champ_reponse.dart';

String _jourHeure(DateTime d) {
  final l = d.toLocal();
  String z(int n) => n.toString().padLeft(2, '0');
  return '${z(l.day)}/${z(l.month)} à ${z(l.hour)}h${z(l.minute)}';
}

String _note(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

/// Entrée « Concours et olympiades » dans « Réviser » (REG-38 lot E2a).
class CarteConcours extends ConsumerWidget {
  const CarteConcours({super.key, required this.ficheId, required this.prenom, required this.parent, this.maintenant});

  final String ficheId;
  final String prenom;
  final bool parent;
  final DateTime Function()? maintenant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(concoursEleveProvider(ficheId)).valueOrNull ?? const <Concours>[];
    if (liste.isEmpty) return const SizedBox.shrink();
    final m = (maintenant ?? DateTime.now)();
    final aJouer = liste.where((c) => c.inscrit && c.mancheAJouer(m) != null).length;
    final ouverts = liste.where((c) => c.ouvert).length;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        key: const Key('carte_concours'),
        leading: const Icon(Icons.emoji_events_outlined),
        title: const Text('Concours et olympiades', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(aJouer > 0
            ? '$aJouer manche${aJouer > 1 ? 's' : ''} à jouer maintenant'
            : '$ouverts ouvert${ouverts > 1 ? 's' : ''} · écoles, pays et sous-région'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EcranConcours(ficheId: ficheId, prenom: prenom, parent: parent, maintenant: maintenant),
        )),
      ),
    );
  }
}

class EcranConcours extends ConsumerWidget {
  const EcranConcours({super.key, required this.ficheId, required this.prenom, required this.parent, this.maintenant});

  final String ficheId;
  final String prenom;
  final bool parent;
  final DateTime Function()? maintenant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(concoursEleveProvider(ficheId));
    return Scaffold(
      appBar: AppBar(title: const Text('Concours et olympiades')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(concoursEleveProvider(ficheId)),
        child: liste.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(e is ErreurConcours ? e.message : 'Concours indisponibles pour le moment.', textAlign: TextAlign.center),
          ]),
          data: (l) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'Les résultats des concours ne comptent jamais dans les notes de l’école.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              if (l.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Aucun concours pour le moment.')),
              for (final c in l)
                _CarteUnConcours(concours: c, ficheId: ficheId, prenom: prenom, parent: parent, maintenant: maintenant),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarteUnConcours extends ConsumerWidget {
  const _CarteUnConcours({
    required this.concours,
    required this.ficheId,
    required this.prenom,
    required this.parent,
    this.maintenant,
  });

  final Concours concours;
  final String ficheId;
  final String prenom;
  final bool parent;
  final DateTime Function()? maintenant;

  Future<void> _inscrire(BuildContext context, WidgetRef ref) async {
    final messager = ScaffoldMessenger.of(context);
    try {
      await ref.read(concoursRepositoryProvider).inscrire(concours.id, ficheId);
      ref.invalidate(concoursEleveProvider(ficheId));
      messager.showSnackBar(SnackBar(content: Text(parent ? '$prenom est inscrit(e).' : 'Tu es inscrit(e).')));
    } on ErreurConcours catch (e) {
      messager.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = concours;
    final schema = Theme.of(context).colorScheme;
    final m = (maintenant ?? DateTime.now)();
    final aJouer = c.inscrit ? c.mancheAJouer(m) : null;
    return Card(
      key: ValueKey('concours_${c.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.titre, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            [c.type.libelle, c.organisateur, if (c.international) 'International' else if (c.paysCode != null) c.paysCode!]
                .join(' · '),
            style: TextStyle(color: schema.onSurfaceVariant),
          ),
          if (c.description case final d? when d.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(d)),
          if (c.recompenses case final r? when r.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(Icons.military_tech_outlined, size: 18, color: schema.tertiary),
                const SizedBox(width: 6),
                Expanded(child: Text(r)),
              ]),
            ),
          const SizedBox(height: 8),
          for (final x in c.manches)
            ListTile(
              key: ValueKey('manche_${x.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch ((x.remise, x.etat(m))) {
                (true, _) => Icons.check_circle_outline,
                (_, EtatManche.ouverte) => Icons.play_circle_outline,
                (_, EtatManche.aVenir) => Icons.schedule,
                _ => Icons.lock_outline,
              }),
              title: Text('${x.titre} · ${x.questions} questions · ${x.dureeMin} min'),
              subtitle: Text(x.remise
                  ? x.horsDelai
                      ? 'Copie arrivée hors délai : hors classement.'
                      : 'Remise · ${_note(x.score ?? 0)} / ${x.questions}'
                  : switch (x.etat(m)) {
                      EtatManche.aVenir => 'Ouvre le ${_jourHeure(x.ouverture)}',
                      EtatManche.ouverte => 'Ouverte jusqu’au ${_jourHeure(x.fermeture)}',
                      EtatManche.fermee => 'Fermée',
                    }),
            ),
          if (c.certificat case final code?) _BlocCertificat(code: code),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!c.inscrit && c.inscriptionsOuvertes(m))
              FilledButton.icon(
                key: Key('concours_inscrire_${c.id}'),
                onPressed: () => _inscrire(context, ref),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: Text(parent ? 'Inscrire $prenom' : 'M’inscrire'),
              ),
            if (aJouer != null)
              FilledButton.icon(
                key: Key('concours_jouer_${aJouer.id}'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => EcranMancheConcours(ficheId: ficheId, concours: c, manche: aJouer, maintenant: maintenant),
                )),
                icon: const Icon(Icons.play_arrow),
                label: Text(aJouer.commencee ? 'Reprendre la manche' : 'Commencer la manche'),
              ),
            if (c.inscrit && c.manches.any((x) => x.remise))
              OutlinedButton.icon(
                key: Key('concours_classement_${c.id}'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => EcranClassementConcours(concours: c, ficheId: ficheId),
                )),
                icon: const Icon(Icons.leaderboard_outlined),
                label: const Text('Classement'),
              ),
          ]),
          if (!c.inscrit && !c.inscriptionsOuvertes(m))
            Text('Inscriptions closes.', style: TextStyle(color: schema.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _BlocCertificat extends StatelessWidget {
  const _BlocCertificat({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: schema.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.workspace_premium_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Certificat obtenu', style: TextStyle(fontWeight: FontWeight.w700)),
            SelectableText(code, key: const Key('certificat_code'), style: const TextStyle(fontFamily: 'monospace')),
            const Text('Vérifiable par tous sur $adresseVerificationCertificat', style: TextStyle(fontSize: 12)),
          ]),
        ),
        IconButton(
          key: const Key('certificat_copier'),
          tooltip: 'Copier',
          icon: const Icon(Icons.copy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(
              text: 'Certificat EcoShop $code — vérifiable sur https://$adresseVerificationCertificat/?code=$code',
            ));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié : à coller dans un message.')));
            }
          },
        ),
      ]),
    );
  }
}

/// Une manche : sujet reçu en ligne, chronomètre jusqu'à la limite, copie
/// ramassée à la fin du temps, correction par le serveur (cahier 23.4).
class EcranMancheConcours extends ConsumerStatefulWidget {
  const EcranMancheConcours({
    super.key,
    required this.ficheId,
    required this.concours,
    required this.manche,
    this.maintenant,
  });

  final String ficheId;
  final Concours concours;
  final MancheConcours manche;
  final DateTime Function()? maintenant;

  @override
  ConsumerState<EcranMancheConcours> createState() => _EcranMancheConcoursState();
}

class _EcranMancheConcoursState extends ConsumerState<EcranMancheConcours> {
  DateTime _maintenant() => (widget.maintenant ?? DateTime.now)();
  SujetManche? _sujet;
  ErreurConcours? _erreur;
  final Map<String, Object?> _reponses = {};
  final Set<String> _completes = {};
  int _index = 0;
  Timer? _minuteur;
  bool _envoi = false;
  ResultatManche? _resultat;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _erreur = null);
    try {
      final s = await ref.read(concoursRepositoryProvider).commencer(widget.manche.id, widget.ficheId);
      if (!mounted) return;
      setState(() => _sujet = s);
      _minuteur = Timer.periodic(const Duration(seconds: 1), (_) => _tic());
    } on ErreurConcours catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  int get _restantS => _sujet == null ? 0 : _sujet!.limite.difference(_maintenant()).inSeconds.clamp(0, 1 << 30);

  void _tic() {
    if (!mounted || _resultat != null || _envoi) return;
    if (_restantS == 0) {
      _remettre();
    } else {
      setState(() {});
    }
  }

  Future<void> _remettre() async {
    if (_envoi || _resultat != null || _sujet == null) return;
    _minuteur?.cancel();
    setState(() => _envoi = true);
    try {
      final r = await ref
          .read(concoursRepositoryProvider)
          .remettre(widget.manche.id, widget.ficheId, Map.of(_reponses), _sujet!.questions.length);
      if (mounted) setState(() => _resultat = r);
    } on ErreurConcours catch (e) {
      if (mounted) setState(() => _erreur = e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
    ref.invalidate(concoursEleveProvider(widget.ficheId));
  }

  Future<void> _confirmer() async {
    final reste = (_sujet?.questions.length ?? 0) - _completes.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remettre ta copie ?'),
        content: Text(reste <= 0
            ? 'Tu as répondu à tout. Après la remise, plus rien ne change.'
            : 'Il reste $reste question${reste > 1 ? 's' : ''} sans réponse. Après la remise, plus rien ne change.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Continuer')),
          FilledButton(key: const Key('manche_confirmer'), onPressed: () => Navigator.of(d).pop(true), child: const Text('Remettre')),
        ],
      ),
    );
    if (ok == true) await _remettre();
  }

  @override
  Widget build(BuildContext context) {
    final enCours = _sujet != null && _resultat == null;
    return PopScope(
      canPop: !enCours,
      onPopInvokedWithResult: (aQuitte, _) {
        if (!aQuitte && enCours) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Le chronomètre continue même si tu quittes : remets ta copie avant la fin.'),
          ));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_resultat != null ? 'Résultat' : widget.manche.titre),
          actions: [
            if (enCours)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(chrono(_restantS),
                      key: const Key('manche_chrono'),
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
      ),
    );
  }

  Widget _corps(BuildContext context) {
    if (_resultat case final r?) return _vueResultat(context, r);
    if (_erreur case final e? when _sujet == null) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        Text(e.message, key: const Key('manche_erreur'), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (e.code == 'HORS_LIGNE') FilledButton(onPressed: _charger, child: const Text('Réessayer')),
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
                  key: ValueKey('manche_aller_$i'),
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
          if (_erreur case final e?)
            Text(e.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Text('Question ${_index + 1} sur ${s.questions.length}'),
          const SizedBox(height: 8),
          Text(
            q.contenu.type == TypeQuestion.texteATrous
                ? q.contenu.enonce.replaceAllMapped(ContenuQuestion.motifTrou, (m) => '……(${m.group(1)})')
                : q.contenu.enonce,
            key: const Key('manche_enonce'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          ChampReponse(
            key: ValueKey('manche_reponse_${q.id}'),
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
          OutlinedButton(
            onPressed: _index == 0 ? null : () => setState(() => _index--),
            child: const Text('Précédente'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _index < s.questions.length - 1
                ? FilledButton.tonal(
                    key: const Key('manche_suivante'),
                    onPressed: () => setState(() => _index++),
                    child: const Text('Suivante'),
                  )
                : FilledButton(key: const Key('manche_remettre'), onPressed: _confirmer, child: const Text('Remettre ma copie')),
          ),
        ]),
      ),
    ]);
  }

  Widget _vueResultat(BuildContext context, ResultatManche r) {
    final schema = Theme.of(context).colorScheme;
    final questions = _sujet?.questions ?? const <QuestionQuiz>[];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 32), children: [
      if (r.enAttente)
        Text('Pas de réseau : ta copie est gardée sur ce téléphone et part dès le retour du réseau. '
            'Le résultat arrivera ensuite.',
            key: const Key('manche_en_attente'), textAlign: TextAlign.center)
      else ...[
        Text('${_note(r.score)} / ${r.questions}',
            key: const Key('manche_score'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        if (r.horsDelai)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Copie arrivée après la fin du temps : elle n’entre pas au classement.',
                textAlign: TextAlign.center, style: TextStyle(color: schema.error)),
          ),
        const SizedBox(height: 16),
        Text('Correction', style: Theme.of(context).textTheme.titleSmall),
        for (final (i, q) in questions.indexed)
          if (r.contenuCorrige(q) case final c?)
            Card(
              key: ValueKey('manche_correction_$i'),
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
      ],
      const SizedBox(height: 16),
      FilledButton(key: const Key('manche_terminer'), onPressed: () => Navigator.of(context).pop(), child: const Text('Terminer')),
    ]);
  }
}

enum _Echelle { tous, pays, ecole }

class EcranClassementConcours extends ConsumerStatefulWidget {
  const EcranClassementConcours({super.key, required this.concours, required this.ficheId});

  final Concours concours;
  final String ficheId;

  @override
  ConsumerState<EcranClassementConcours> createState() => _EcranClassementConcoursState();
}

class _EcranClassementConcoursState extends ConsumerState<EcranClassementConcours> {
  _Echelle _echelle = _Echelle.tous;
  ClassementConcours? _general;

  @override
  Widget build(BuildContext context) {
    final cleGenerale = (concours: widget.concours.id, fiche: widget.ficheId, pays: null, etablissement: null);
    final general = ref.watch(classementConcoursProvider(cleGenerale)).valueOrNull;
    _general = general ?? _general;
    final cle = switch (_echelle) {
      _Echelle.tous => cleGenerale,
      _Echelle.pays => (concours: widget.concours.id, fiche: widget.ficheId, pays: _general?.monPays, etablissement: null),
      _Echelle.ecole => (
          concours: widget.concours.id,
          fiche: widget.ficheId,
          pays: null,
          etablissement: _general?.monEtablissement
        ),
    };
    final classement = ref.watch(classementConcoursProvider(cle));
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.concours.titre)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<_Echelle>(
            segments: [
              ButtonSegment(value: _Echelle.tous, label: Text(widget.concours.international ? 'Tous pays' : 'Tous')),
              if (widget.concours.international && _general?.monPays != null)
                ButtonSegment(value: _Echelle.pays, label: Text('Pays (${_general!.monPays})')),
              if (widget.concours.type != TypeConcours.concoursInterne && _general?.monEtablissement != null)
                const ButtonSegment(value: _Echelle.ecole, label: Text('Mon école')),
            ],
            selected: {_echelle},
            onSelectionChanged: (s) => setState(() => _echelle = s.first),
          ),
        ),
        Expanded(
          child: classement.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(e is ErreurConcours ? e.message : 'Classement indisponible.')),
            data: (c) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              Text('${c.participants} participant${c.participants > 1 ? 's' : ''} · à égalité, le plus rapide passe devant',
                  style: TextStyle(color: schema.onSurfaceVariant)),
              for (final l in c.lignes)
                ListTile(
                  key: ValueKey('classement_concours_${l.rang}_${l.nom}'),
                  tileColor: l.moi ? schema.primaryContainer : null,
                  leading: CircleAvatar(child: Text('${l.rang}')),
                  title: Text(l.nom, style: TextStyle(fontWeight: l.moi ? FontWeight.w700 : null)),
                  subtitle: Text([if (l.ecole != null) l.ecole!, if (l.pays != null) l.pays!].join(' · ')),
                  trailing: Text(_note(l.score), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
