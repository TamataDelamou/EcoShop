import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/audio/lecteur_vocal.dart';
import '../application/revision_providers.dart';
import '../domain/question.dart';
import '../domain/quiz.dart';
import 'champ_reponse.dart';

enum _Phase { repondre, corrige, fin }

/// Un quiz : une question à la fois, correction immédiate avec la bonne
/// réponse et l'explication (cahier 11.1), puis le résultat. Tout se passe
/// sur l'appareil ; l'envoi part dès que le réseau le permet.
class EcranQuiz extends ConsumerStatefulWidget {
  const EcranQuiz({super.key, required this.session, this.petitesClasses = false, this.prenom, this.hasard});

  final SessionQuiz session;
  final bool petitesClasses;

  /// Prénom de l'enfant quand le parent tient le téléphone.
  final String? prenom;
  final Random? hasard;

  @override
  ConsumerState<EcranQuiz> createState() => _EcranQuizState();
}

class _EcranQuizState extends ConsumerState<EcranQuiz> {
  late final Random _hasard = widget.hasard ?? Random();
  SessionQuiz get _s => widget.session;
  _Phase _phase = _Phase.repondre;
  Object? _donnee;
  ReponseQuiz? _derniere;
  String _message = '';
  int _serie = 0;
  DateTime _debutQuestion = DateTime.now();
  bool _enregistre = false;
  bool? _recu;

  bool _complete = false;

  void _preparer() {
    _donnee = null;
    _complete = false;
    _debutQuestion = DateTime.now();
  }

  void _valider() {
    final duree = DateTime.now().difference(_debutQuestion).inSeconds;
    final r = _s.repondre(_donnee, dureeS: duree);
    _serie = r.correction.juste ? _serie + 1 : 0;
    setState(() {
      _derniere = r;
      _message = messageApresReponse(r.correction, petitesClasses: widget.petitesClasses, serie: _serie, hasard: _hasard);
      _phase = _Phase.corrige;
    });
  }

  Future<void> _suivant() async {
    ref.read(lecteurVocalProvider).arreter();
    if (_s.fini) {
      setState(() => _phase = _Phase.fin);
      await _enregistrer(termine: true);
      return;
    }
    setState(() {
      _preparer();
      _phase = _Phase.repondre;
    });
  }

  Future<void> _lireAVoixHaute(String texte) async {
    final ok = await ref.read(lecteurVocalProvider).lire(texte);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Lecture à voix haute indisponible : installez une voix française dans les réglages du téléphone.'),
      ));
    }
  }

  Future<void> _enregistrer({required bool termine}) async {
    if (_enregistre) return;
    _enregistre = true;
    try {
      final recu = await ref.read(revisionRepositoryProvider).enregistrer(_s, termine: termine);
      if (mounted) setState(() => _recu = recu);
    } catch (_) {
      if (mounted) setState(() => _recu = false);
    }
    ref.invalidate(espaceRevisionProvider(_s.ficheId));
  }

  Future<void> _quitter() async {
    if (_phase == _Phase.fin) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Arrêter le quiz ?'),
        content: const Text('Le temps de travail est gardé. Le quiz ne compte pas dans la réussite tant qu’il n’est pas fini.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Continuer')),
          FilledButton(key: const Key('quiz_arreter'), onPressed: () => Navigator.of(d).pop(true), child: const Text('Arrêter')),
        ],
      ),
    );
    if (ok != true) return;
    await _enregistrer(termine: false);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _signaler(QuestionQuiz q) async {
    const motifs = {
      'reponse_fausse': 'La bonne réponse est fausse',
      'enonce_confus': 'La question n’est pas claire',
      'faute': 'Il y a une faute',
      'hors_programme': 'Hors du programme',
      'autre': 'Autre chose',
    };
    final motif = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Signaler cette question')),
          for (final e in motifs.entries)
            ListTile(key: ValueKey('motif_${e.key}'), title: Text(e.value), onTap: () => Navigator.of(c).pop(e.key)),
        ]),
      ),
    );
    if (motif == null) return;
    try {
      await ref.read(revisionRepositoryProvider).signaler(q.id, motif);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Merci, l’équipe pédagogique va vérifier.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signalement impossible pour le moment.')));
      }
    }
  }

  void _refaireErreurs() {
    final erreurs = [for (final r in _s.reponses) if (!r.correction.juste) r.question];
    if (erreurs.isEmpty) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => EcranQuiz(
        session: SessionQuiz(
          id: const Uuid().v4(),
          ficheId: _s.ficheId,
          config: ConfigQuiz(mode: ModeQuiz.erreurs, matiereId: _s.config.matiereId, petitesClasses: widget.petitesClasses),
          questions: melanger(erreurs, _hasard),
        ),
        petitesClasses: widget.petitesClasses,
        prenom: widget.prenom,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final titre = _phase == _Phase.fin
        ? 'Résultat'
        : 'Question ${min(_s.index + (_phase == _Phase.corrige ? 0 : 1), _s.questions.length)} sur ${_s.questions.length}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (aQuitte, _) {
        if (!aQuitte) _quitter();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(titre),
          leading: IconButton(key: const Key('quiz_fermer'), icon: const Icon(Icons.close), onPressed: _quitter),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(value: _s.questions.isEmpty ? 0 : _s.reponses.length / _s.questions.length),
          ),
        ),
        body: SafeArea(child: _phase == _Phase.fin ? _resultat(context) : _question(context)),
      ),
    );
  }

  Widget _question(BuildContext context) {
    final q = _phase == _Phase.corrige ? _derniere!.question : _s.courante!;
    final c = q.contenu;
    final schema = Theme.of(context).colorScheme;
    final enonce = c.type == TypeQuestion.texteATrous
        ? c.enonce.replaceAllMapped(ContenuQuestion.motifTrou, (m) => '……(${m.group(1)})')
        : c.enonce;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (widget.prenom != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Avec ${widget.prenom}', style: TextStyle(color: schema.onSurfaceVariant)),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(enonce, key: const Key('quiz_enonce'), style: Theme.of(context).textTheme.titleMedium)),
          // Petites classes : lire la question à voix haute (enfant qui lit
          // encore peu) ; disponible pour tous.
          IconButton(
            key: const Key('quiz_ecouter'),
            tooltip: 'Écouter la question',
            iconSize: widget.petitesClasses ? 36 : 24,
            onPressed: () => _lireAVoixHaute(texteQuestionALire(c)),
            icon: const Icon(Icons.volume_up_outlined),
          ),
        ]),
        if (c.mediaChemin != null) _ImageQuestion(chemin: c.mediaChemin!),
        const SizedBox(height: 16),
        if (_phase == _Phase.repondre) ...[
          ChampReponse(
            key: ValueKey('reponse_${q.id}_${_s.index}'),
            question: q,
            petitesClasses: widget.petitesClasses,
            hasard: _hasard,
            onChanged: (d, complete) => setState(() {
              _donnee = d;
              _complete = complete;
            }),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('quiz_valider'),
            onPressed: _complete ? _valider : null,
            child: const Text('Valider'),
          ),
        ] else
          _correction(context, q),
      ],
    );
  }

  Widget _correction(BuildContext context, QuestionQuiz q) {
    final r = _derniere!;
    final schema = Theme.of(context).colorScheme;
    final juste = r.correction.juste;
    final couleur = juste
        ? Colors.green.shade700
        : (widget.petitesClasses || r.correction.score > 0 ? schema.tertiary : schema.error);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        color: couleur.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(juste ? Icons.check_circle : (widget.petitesClasses ? Icons.lightbulb : Icons.info_outline), color: couleur),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_message,
                    key: const Key('quiz_message'), style: TextStyle(fontWeight: FontWeight.w700, color: couleur)),
              ),
            ]),
            if (!juste) ...[
              const SizedBox(height: 8),
              Text('Bonne réponse : ${q.contenu.bonneReponseLisible()}', key: const Key('quiz_bonne_reponse')),
            ],
            const SizedBox(height: 8),
            Text(q.contenu.explication, key: const Key('quiz_explication')),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('quiz_ecouter_explication'),
                onPressed: () => _lireAVoixHaute(
                    '$_message. ${juste ? '' : 'La bonne réponse est : ${q.contenu.bonneReponseLisible()}. '}${q.contenu.explication}'),
                icon: const Icon(Icons.volume_up_outlined, size: 18),
                label: const Text('Écouter'),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const Key('quiz_suivant'),
        onPressed: _suivant,
        child: Text(_s.fini ? 'Voir mon résultat' : 'Question suivante'),
      ),
      TextButton.icon(
        key: const Key('quiz_signaler'),
        onPressed: () => _signaler(q),
        icon: const Icon(Icons.flag_outlined, size: 18),
        label: const Text('Signaler une erreur dans la question'),
      ),
    ]);
  }

  Widget _resultat(BuildContext context) {
    final erreurs = [for (final r in _s.reponses) if (!r.correction.juste) r];
    final note = _s.points;
    final total = _s.reponses.length;
    final schema = Theme.of(context).colorScheme;
    String fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Text('${fmt(note)} sur $total', key: const Key('quiz_score'), textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(messageFin(_s.reussite, petitesClasses: widget.petitesClasses),
            key: const Key('quiz_message_fin'), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Temps : ${dureeLisible(_s.dureeTotaleS(_s.termineLe ?? DateTime.now()))}', textAlign: TextAlign.center),
        if (_recu == false)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Gardé sur ce téléphone, envoyé au retour du réseau.',
                textAlign: TextAlign.center, style: TextStyle(color: schema.onSurfaceVariant)),
          ),
        const SizedBox(height: 16),
        Text('C’est un entraînement : il ne compte pas dans les notes de l’école.',
            textAlign: TextAlign.center, style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 16),
        if (erreurs.isNotEmpty) ...[
          Text('À retenir', style: Theme.of(context).textTheme.titleSmall),
          for (final r in erreurs)
            Card(
              child: ListTile(
                title: Text(r.question.contenu.enonce, maxLines: 3, overflow: TextOverflow.ellipsis),
                subtitle: Text('Bonne réponse : ${r.question.contenu.bonneReponseLisible()}'),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const Key('quiz_refaire_erreurs'),
            onPressed: _refaireErreurs,
            icon: const Icon(Icons.replay),
            label: Text('Refaire mes ${erreurs.length} erreur${erreurs.length > 1 ? 's' : ''}'),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton(key: const Key('quiz_terminer'), onPressed: () => Navigator.of(context).pop(), child: const Text('Terminer')),
      ],
    );
  }
}

class _ImageQuestion extends ConsumerWidget {
  const _ImageQuestion({required this.chemin});

  final String chemin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Uri>(
      future: ref.read(revisionRepositoryProvider).lienMedia(chemin),
      builder: (context, lien) {
        if (lien.hasError) {
          return const Padding(padding: EdgeInsets.only(top: 8), child: Text('Image visible avec le réseau.'));
        }
        if (!lien.hasData) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              lien.data.toString(),
              errorBuilder: (_, _, _) => const Text('Image visible avec le réseau.'),
            ),
          ),
        );
      },
    );
  }
}
