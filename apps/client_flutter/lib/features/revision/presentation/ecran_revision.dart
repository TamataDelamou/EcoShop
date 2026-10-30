import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/audio/lecteur_vocal.dart';
import '../application/revision_providers.dart';
import '../data/revision_repository.dart';
import '../domain/classement.dart';
import '../domain/conseils.dart';
import '../domain/examen.dart';
import '../domain/question.dart';
import '../domain/quiz.dart';
import 'ecran_examen.dart';
import 'ecran_quiz.dart';

/// Révisions d'un élève (REG-37 lot R2). Pour l'élève : « Mes révisions ».
/// Pour le parent : ce que fait son enfant, un conseil concret, et « Réviser
/// avec » sur son propre téléphone (les quiz comptent pour l'enfant).
class EcranRevision extends ConsumerWidget {
  const EcranRevision({super.key, required this.ficheId, required this.prenom, this.parent = false});

  final String ficheId;
  final String prenom;
  final bool parent;

  void _lancer(BuildContext context, WidgetRef ref, EspaceRevision e, ConfigQuiz config) {
    final questions = choisirQuestions(e.paquet, config, traces: e.traces);
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(config.mode == ModeQuiz.erreurs
            ? 'Aucune erreur à refaire : bravo !'
            : 'Pas encore de questions ici. L’équipe pédagogique en prépare.'),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EcranQuiz(
        session: SessionQuiz(id: const Uuid().v4(), ficheId: ficheId, config: config, questions: questions),
        petitesClasses: e.niveau.petitesClasses,
        prenom: parent ? prenom : null,
      ),
    ));
  }

  Future<void> _choisirDansMatiere(BuildContext context, WidgetRef ref, EspaceRevision e, MatiereRevision m) async {
    final chapitres = [for (final c in e.paquet.chapitres) if (c.matiereId == m.id && e.paquet.questionsDe(m.id, chapitreId: c.id) > 0) c];
    final choix = await showModalBottomSheet<ConfigQuiz>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.75),
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text(m.nom, style: Theme.of(c).textTheme.titleMedium)),
            ListTile(
              key: const Key('matiere_toute'),
              leading: const Icon(Icons.all_inclusive),
              title: const Text('Toute la matière'),
              subtitle: Text('${e.paquet.questionsDe(m.id)} questions'),
              onTap: () => Navigator.of(c).pop(ConfigQuiz(
                mode: ModeQuiz.matiere,
                matiereId: m.id,
                petitesClasses: e.niveau.petitesClasses,
              )),
            ),
            if (chapitres.length > 1)
              ListTile(
                key: const Key('matiere_melee'),
                leading: const Icon(Icons.shuffle),
                title: const Text('Révision mêlée'),
                subtitle: const Text('Un peu de chaque chapitre : on retient mieux'),
                onTap: () => Navigator.of(c).pop(ConfigQuiz(
                  mode: ModeQuiz.melange,
                  matiereId: m.id,
                  petitesClasses: e.niveau.petitesClasses,
                )),
              ),
            for (final ch in chapitres)
              ListTile(
                key: ValueKey('chapitre_${ch.id}'),
                leading: const Icon(Icons.bookmark_outline),
                title: Text(ch.titre),
                subtitle: Text('${e.paquet.questionsDe(m.id, chapitreId: ch.id)} questions'),
                onTap: () => Navigator.of(c).pop(ConfigQuiz(
                  mode: ModeQuiz.chapitre,
                  matiereId: m.id,
                  chapitreId: ch.id,
                  petitesClasses: e.niveau.petitesClasses,
                )),
              ),
          ]),
        ),
      ),
    );
    if (choix != null && context.mounted) _lancer(context, ref, e, choix);
  }

  Future<void> _personnaliser(BuildContext context, WidgetRef ref, EspaceRevision e) async {
    final config = await showDialog<ConfigQuiz>(
      context: context,
      builder: (_) => _DialoguePersonnalise(espace: e),
    );
    if (config != null && context.mounted) _lancer(context, ref, e, config);
  }

  Future<void> _preparerExamen(BuildContext context, WidgetRef ref, EspaceRevision e) async {
    final reglage = await showDialog<({String? matiereId, int nombre, int? minutes})>(
      context: context,
      builder: (_) => _DialogueExamen(espace: e),
    );
    if (reglage == null || !context.mounted) return;
    final questions = choisirQuestions(
      e.paquet,
      ConfigQuiz(mode: ModeQuiz.examen, matiereId: reglage.matiereId, nombre: reglage.nombre),
      traces: e.traces,
    )..shuffle();
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pas encore assez de questions ici. L’équipe pédagogique en prépare.')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EcranExamen(
        examen: SessionExamen(
          id: const Uuid().v4(),
          ficheId: ficheId,
          matiereId: reglage.matiereId,
          questions: questions,
          dureeLimiteS: reglage.minutes == null ? dureeConseilleeS(questions) : reglage.minutes! * 60,
        ),
        competences: {for (final k in e.paquet.competences) k.id: k.libelle},
      ),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final espace = ref.watch(espaceRevisionProvider(ficheId));
    return Scaffold(
      appBar: AppBar(title: Text(parent ? 'Révisions de $prenom' : 'Mes révisions')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(espaceRevisionProvider(ficheId)),
        child: espace.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(err is ErreurRevision ? err.message : const ErreurRevision('ERREUR_SERVEUR').message,
                  key: const Key('revision_erreur')),
            ),
          ]),
          data: (e) => _contenu(context, ref, e),
        ),
      ),
    );
  }

  Widget _contenu(BuildContext context, WidgetRef ref, EspaceRevision e) {
    final schema = Theme.of(context).colorScheme;
    final r = e.resume;
    final petites = e.niveau.petitesClasses;
    final erreurs = e.traces.values.where((t) => t.dernierScore < 1).length;
    final conseils = parent
        ? conseilsParent(prenom: prenom, resume: r, paquet: e.paquet, maintenant: DateTime.now())
        : const <ConseilParent>[];
    final aRevoir = [
      for (final id in r.competencesARevoir())
        ?e.paquet.competences.where((k) => k.id == id).firstOrNull,
    ];

    Widget bouton(String cle, IconData icone, String titre, String sous, ConfigQuiz config, {bool principal = false}) {
      final contenu = Row(children: [
        Icon(icone),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(sous, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ]);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: principal
            ? FilledButton(
                key: Key(cle),
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(16), alignment: Alignment.centerLeft),
                onPressed: () => _lancer(context, ref, e, config),
                child: contenu,
              )
            : OutlinedButton(
                key: Key(cle),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16), alignment: Alignment.centerLeft),
                onPressed: () => _lancer(context, ref, e, config),
                child: contenu,
              ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text('${e.niveau.nom} · ${e.paquet.questions.length} questions sur ce téléphone',
            style: TextStyle(color: schema.onSurfaceVariant)),
        if (parent)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Les quiz faits ici, avec $prenom, comptent pour $prenom.',
                style: TextStyle(color: schema.onSurfaceVariant)),
          ),
        const SizedBox(height: 12),
        _CarteResume(resume: r, paquet: e.paquet),
        if (parent) _CarteBilan(ficheId: ficheId),
        for (final c in conseils)
          Card(
            color: schema.secondaryContainer,
            child: ListTile(
              key: const Key('conseil_parent'),
              leading: const Icon(Icons.tips_and_updates_outlined),
              title: Text(c.texte),
              trailing: IconButton(
                tooltip: 'Écouter',
                onPressed: () => ref.read(lecteurVocalProvider).lire(c.texte),
                icon: const Icon(Icons.volume_up_outlined),
              ),
              onTap: c.matiereId == null
                  ? null
                  : () => _lancer(context, ref, e, ConfigQuiz(mode: ModeQuiz.matiere, matiereId: c.matiereId, petitesClasses: petites)),
            ),
          ),
        if (e.paquet.vide)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Pas encore de questions pour ce niveau. L’équipe pédagogique de GSG les prépare ; '
                'elles arriveront ici automatiquement.', key: Key('revision_vide')),
          )
        else ...[
          const SizedBox(height: 12),
          Text(parent ? 'Réviser avec $prenom' : 'S’entraîner', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          bouton('quiz_rapide', Icons.bolt, 'Quiz rapide', '5 questions, moins de 5 minutes',
              ConfigQuiz(mode: ModeQuiz.rapide, petitesClasses: petites),
              principal: true),
          if (!petites) ...[
            bouton('quiz_standard', Icons.quiz_outlined, 'Quiz standard', '10 questions',
                ConfigQuiz(mode: ModeQuiz.standard, petitesClasses: petites)),
            bouton('quiz_intensif', Icons.fitness_center, 'Quiz intensif', '20 questions',
                ConfigQuiz(mode: ModeQuiz.intensif, petitesClasses: petites)),
          ],
          if (erreurs > 0)
            bouton('quiz_erreurs', Icons.replay, 'Refaire mes erreurs', '$erreurs question${erreurs > 1 ? 's' : ''} à retenir',
                ConfigQuiz(mode: ModeQuiz.erreurs, petitesClasses: petites)),
          if (!petites)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('quiz_personnalise'),
                onPressed: () => _personnaliser(context, ref, e),
                icon: const Icon(Icons.tune),
                label: const Text('Quiz personnalisé'),
              ),
            ),
          if (!petites) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('examen_blanc'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16), alignment: Alignment.centerLeft),
              onPressed: () => _preparerExamen(context, ref, e),
              icon: const Icon(Icons.timer_outlined),
              label: const Text('Examen blanc : chronométré, corrigé à la fin'),
            ),
          ],
          if (aRevoir.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('À revoir', style: Theme.of(context).textTheme.titleMedium),
            for (final k in aRevoir.take(3))
              ListTile(
                key: ValueKey('a_revoir_${k.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.flag_outlined, color: schema.tertiary),
                title: Text(k.libelle),
                subtitle: Text(e.paquet.matieres.where((m) => m.id == k.matiereId).firstOrNull?.nom ?? ''),
                trailing: const Icon(Icons.play_arrow),
                onTap: () => _lancer(context, ref, e, ConfigQuiz(mode: ModeQuiz.matiere, matiereId: k.matiereId, petitesClasses: petites)),
              ),
          ],
          if (!petites) _SectionClassement(ficheId: ficheId, parent: parent, prenom: prenom),
          const SizedBox(height: 12),
          Text('Par matière', style: Theme.of(context).textTheme.titleMedium),
          for (final m in e.paquet.matieres)
            if (e.paquet.questionsDe(m.id) > 0) _LigneMatiere(
              matiere: m,
              paquet: e.paquet,
              resume: r,
              onTap: () => _choisirDansMatiere(context, ref, e, m),
            ),
        ],
        const SizedBox(height: 16),
        Text('Entraînement : ces résultats ne comptent jamais dans les notes de l’école.',
            style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }
}

class _CarteResume extends StatelessWidget {
  const _CarteResume({required this.resume, required this.paquet});

  final ResumeRevision resume;
  final PaquetRevision paquet;

  @override
  Widget build(BuildContext context) {
    final r = resume;
    final reussite = r.reussite;
    Widget chiffre(String valeur, String libelle, String cle) => Expanded(
          child: Column(children: [
            Text(valeur, key: Key(cle), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(libelle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ces ${r.jours} derniers jours', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
          Row(children: [
            chiffre(dureeLisible(r.tempsS), 'de travail', 'resume_temps'),
            chiffre('${r.quizTermines}', 'quiz terminés', 'resume_quiz'),
            chiffre(reussite == null ? '—' : '${(reussite * 100).round()} %', 'de réussite', 'resume_reussite'),
          ]),
        ]),
      ),
    );
  }
}

class _LigneMatiere extends StatelessWidget {
  const _LigneMatiere({required this.matiere, required this.paquet, required this.resume, required this.onTap});

  final MatiereRevision matiere;
  final PaquetRevision paquet;
  final ResumeRevision resume;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stats = resume.parMatiere[matiere.id];
    final reussite = stats == null || stats.reponses == 0 ? null : stats.points / stats.reponses;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        key: ValueKey('matiere_${matiere.id}'),
        onTap: onTap,
        title: Text(matiere.nom),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${paquet.questionsDe(matiere.id)} questions'
              '${reussite == null ? '' : ' · ${(reussite * 100).round()} % de réussite'}'),
          if (reussite != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: reussite, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            ),
        ]),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _DialoguePersonnalise extends StatefulWidget {
  const _DialoguePersonnalise({required this.espace});

  final EspaceRevision espace;

  @override
  State<_DialoguePersonnalise> createState() => _DialoguePersonnaliseState();
}

class _DialoguePersonnaliseState extends State<_DialoguePersonnalise> {
  String? _matiere;
  String? _chapitre;
  final Set<Difficulte> _difficultes = {};
  double _nombre = 10;

  @override
  Widget build(BuildContext context) {
    final p = widget.espace.paquet;
    final chapitres = [for (final c in p.chapitres) if (c.matiereId == _matiere) c];
    return AlertDialog(
      title: const Text('Quiz personnalisé'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<String?>(
            key: const Key('perso_matiere'),
            initialValue: _matiere,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Matière'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Toutes')),
              for (final m in p.matieres) DropdownMenuItem<String?>(value: m.id, child: Text(m.nom)),
            ],
            onChanged: (v) => setState(() {
              _matiere = v;
              _chapitre = null;
            }),
          ),
          if (chapitres.isNotEmpty)
            DropdownButtonFormField<String?>(
              key: ValueKey('perso_chapitre_$_matiere'),
              initialValue: _chapitre,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Chapitre'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Tous')),
                for (final c in chapitres) DropdownMenuItem<String?>(value: c.id, child: Text(c.titre)),
              ],
              onChanged: (v) => setState(() => _chapitre = v),
            ),
          const SizedBox(height: 12),
          const Text('Difficulté'),
          Wrap(spacing: 6, children: [
            for (final d in Difficulte.values)
              FilterChip(
                label: Text(d.libelle),
                selected: _difficultes.contains(d),
                onSelected: (v) => setState(() => v ? _difficultes.add(d) : _difficultes.remove(d)),
              ),
          ]),
          const SizedBox(height: 12),
          Text('${_nombre.round()} questions'),
          Slider(value: _nombre, min: 5, max: 50, divisions: 9, onChanged: (v) => setState(() => _nombre = v)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          key: const Key('perso_lancer'),
          onPressed: () => Navigator.of(context).pop(ConfigQuiz(
            mode: ModeQuiz.personnalise,
            matiereId: _matiere,
            chapitreId: _chapitre,
            difficultes: {..._difficultes},
            nombre: max(5, _nombre.round()),
          )),
          child: const Text('Commencer'),
        ),
      ],
    );
  }
}

/// Bilan de la semaine pour le parent, à lire ou à écouter (le même que la
/// notification du dimanche soir).
class _CarteBilan extends ConsumerWidget {
  const _CarteBilan({required this.ficheId});

  final String ficheId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bilan = ref.watch(bilanRevisionProvider(ficheId)).valueOrNull;
    if (bilan == null || bilan.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bilan de la semaine', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(bilan, key: const Key('bilan_semaine')),
            ]),
          ),
          IconButton.filledTonal(
            key: const Key('bilan_ecouter'),
            tooltip: 'Écouter le bilan',
            onPressed: () async {
              final ok = await ref.read(lecteurVocalProvider).lire(bilan);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Lecture à voix haute indisponible : installez une voix française dans les réglages du téléphone.'),
                ));
              }
            },
            icon: const Icon(Icons.volume_up_outlined),
          ),
        ]),
      ),
    );
  }
}

/// Classement de la semaine (classe ou école), sur les points d'effort.
class _SectionClassement extends ConsumerStatefulWidget {
  const _SectionClassement({required this.ficheId, required this.parent, required this.prenom});

  final String ficheId;
  final bool parent;
  final String prenom;

  @override
  ConsumerState<_SectionClassement> createState() => _SectionClassementState();
}

class _SectionClassementState extends ConsumerState<_SectionClassement> {
  String _echelle = 'classe';

  Future<void> _basculer(bool visible) async {
    try {
      await ref.read(revisionRepositoryProvider).definirClassementVisible(widget.ficheId, visible);
      ref
        ..invalidate(classementRevisionProvider((fiche: widget.ficheId, echelle: 'classe')))
        ..invalidate(classementRevisionProvider((fiche: widget.ficheId, echelle: 'etablissement')));
    } on ErreurRevision catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(classementRevisionProvider((fiche: widget.ficheId, echelle: _echelle))).valueOrNull;
    if (c == null || !c.actif) return const SizedBox.shrink();
    final schema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Classement de la semaine', style: Theme.of(context).textTheme.titleMedium)),
          SegmentedButton<String>(
            key: const Key('classement_echelle'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'classe', label: Text('Classe')),
              ButtonSegment(value: 'etablissement', label: Text('École')),
            ],
            selected: {_echelle},
            onSelectionChanged: (s) => setState(() => _echelle = s.first),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Points d’effort : $baremeEffort Nouveau classement chaque lundi.',
            style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            if (c.lignes.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Personne n’a encore de points cette semaine : à toi de commencer !')),
            for (final (i, l) in c.lignes.indexed) ...[
              if (i > 0 && l.rang > c.lignes[i - 1].rang + 1) const Divider(height: 1),
              ListTile(
                key: ValueKey('classement_${l.rang}_${l.nom}'),
                dense: true,
                tileColor: l.moi ? schema.primaryContainer : null,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: l.rang <= 3 ? schema.tertiaryContainer : schema.surfaceContainerHighest,
                  child: Text('${l.rang}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                title: Text(l.moi ? '${l.nom} (${widget.parent ? widget.prenom : 'toi'})' : l.nom,
                    style: TextStyle(fontWeight: l.moi ? FontWeight.w800 : FontWeight.w500)),
                trailing: Text('${l.points} pts'),
              ),
            ],
          ]),
        ),
        Text(c.encouragement(), key: const Key('classement_encouragement')),
        SwitchListTile(
          key: const Key('classement_visible'),
          contentPadding: EdgeInsets.zero,
          value: c.visible,
          onChanged: _basculer,
          title: Text(widget.parent ? 'Montrer ${widget.prenom} dans le classement' : 'Apparaître dans le classement'),
          subtitle: const Text('Seuls le prénom et l’initiale du nom sont montrés.'),
        ),
      ]),
    );
  }
}

class _DialogueExamen extends StatefulWidget {
  const _DialogueExamen({required this.espace});

  final EspaceRevision espace;

  @override
  State<_DialogueExamen> createState() => _DialogueExamenState();
}

class _DialogueExamenState extends State<_DialogueExamen> {
  String? _matiere;
  int _nombre = 20;
  int? _minutes;

  @override
  Widget build(BuildContext context) {
    final p = widget.espace.paquet;
    return AlertDialog(
      title: const Text('Examen blanc'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Comme le jour de l’examen : un temps limité, tu peux revenir en arrière, '
              'la correction arrive à la fin.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: const Key('examen_matiere'),
            initialValue: _matiere,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Matière'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Toutes les matières')),
              for (final m in p.matieres)
                if (p.questionsDe(m.id) > 0) DropdownMenuItem<String?>(value: m.id, child: Text(m.nom)),
            ],
            onChanged: (v) => setState(() => _matiere = v),
          ),
          const SizedBox(height: 12),
          const Text('Nombre de questions'),
          Wrap(spacing: 6, children: [
            for (final n in [10, 20, 30])
              ChoiceChip(label: Text('$n'), selected: _nombre == n, onSelected: (_) => setState(() => _nombre = n)),
          ]),
          const SizedBox(height: 12),
          const Text('Durée'),
          Wrap(spacing: 6, children: [
            ChoiceChip(label: const Text('Conseillée'), selected: _minutes == null, onSelected: (_) => setState(() => _minutes = null)),
            for (final m in [15, 30, 60])
              ChoiceChip(label: Text('$m min'), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m)),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          key: const Key('examen_commencer'),
          onPressed: () => Navigator.of(context).pop((matiereId: _matiere, nombre: _nombre, minutes: _minutes)),
          child: const Text('Commencer'),
        ),
      ],
    );
  }
}
