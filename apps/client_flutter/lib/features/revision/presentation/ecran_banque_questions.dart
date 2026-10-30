import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/banque_providers.dart';
import '../domain/question.dart';
import 'ecran_editeur_question.dart';

/// Questions d'une matière (Administrateur de contenu pédagogique).
class EcranQuestionsMatiere extends ConsumerStatefulWidget {
  const EcranQuestionsMatiere({
    super.key,
    required this.matiereId,
    required this.titre,
    this.petitesClasses = false,
  });

  final String matiereId;

  /// « Guinée · 7e · Mathématiques ».
  final String titre;
  final bool petitesClasses;

  @override
  ConsumerState<EcranQuestionsMatiere> createState() => _EcranQuestionsMatiereState();
}

class _EcranQuestionsMatiereState extends ConsumerState<EcranQuestionsMatiere> {
  StatutContenu? _filtre;

  void _ouvrir(Question? q) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EcranEditeurQuestion(
          matiereId: widget.matiereId,
          titreMatiere: widget.titre,
          question: q,
          petitesClasses: widget.petitesClasses,
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final liste = ref.watch(questionsMatiereProvider(widget.matiereId));
    final structure = ref.watch(structureMatiereProvider(widget.matiereId)).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Banque de questions'),
        actions: [
          IconButton(
            key: const Key('ouvrir_structure'),
            tooltip: 'Chapitres et compétences',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => EcranStructureMatiere(matiereId: widget.matiereId, titre: widget.titre),
            )),
            icon: const Icon(Icons.account_tree_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('nouvelle_question'),
        onPressed: () => _ouvrir(null),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle question'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref
          ..invalidate(questionsMatiereProvider(widget.matiereId))
          ..invalidate(structureMatiereProvider(widget.matiereId)),
        child: liste.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: const [
            Padding(padding: EdgeInsets.all(16), child: Text('Questions indisponibles pour le moment. Tirez pour réessayer.')),
          ]),
          data: (questions) {
            final visibles = [for (final q in questions) if (_filtre == null || q.statut == _filtre) q];
            final competences = {for (final c in structure?.competences ?? const <Competence>[]) c.id: c};
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text(widget.titre, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text('${questions.length} question${questions.length > 1 ? 's' : ''}'
                    ' · ${questions.where((q) => q.versionPubliee != null).length} diffusée(s)'),
                if (structure != null && structure.competences.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Commencez par les chapitres et compétences (bouton en haut à droite).'),
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  ChoiceChip(label: const Text('Toutes'), selected: _filtre == null, onSelected: (_) => setState(() => _filtre = null)),
                  for (final s in StatutContenu.values)
                    ChoiceChip(
                      key: ValueKey('filtre_${s.code}'),
                      label: Text('${s.libelle} (${questions.where((q) => q.statut == s).length})'),
                      selected: _filtre == s,
                      onSelected: (v) => setState(() => _filtre = v ? s : null),
                    ),
                ]),
                const SizedBox(height: 8),
                if (visibles.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune question.')),
                for (final q in visibles)
                  CarteQuestion(question: q, competence: competences[q.travail.competenceId], onTap: () => _ouvrir(q)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Une question dans une liste.
class CarteQuestion extends StatelessWidget {
  const CarteQuestion({super.key, required this.question, this.competence, this.onTap, this.trailing});

  final Question question;
  final Competence? competence;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final q = question;
    final schema = Theme.of(context).colorScheme;
    final etat = q.enAttenteEnvoi
        ? 'Sur cet appareil'
        : [
            q.statut.libelle,
            if (q.diffuseePendantModification) 'v${q.versionPubliee} diffusée',
            if (q.suspendue) 'suspendue',
            if (q.signalements > 0) '${q.signalements} signalement${q.signalements > 1 ? 's' : ''}',
          ].join(' · ');
    return Card(
      key: ValueKey('question_${q.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(q.travail.enonce, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          '${q.travail.type.libelle} · ${q.travail.difficulte.libelle}',
          if (competence != null) competence!.libelle,
          etat,
        ].join('\n')),
        isThreeLine: true,
        trailing: trailing ??
            Icon(
              q.suspendue
                  ? Icons.report_outlined
                  : q.statut == StatutContenu.publiee
                      ? Icons.public
                      : Icons.edit_note,
              color: q.suspendue ? schema.error : null,
            ),
      ),
    );
  }
}

/// Chapitres, leçons et compétences d'une matière.
class EcranStructureMatiere extends ConsumerWidget {
  const EcranStructureMatiere({super.key, required this.matiereId, required this.titre});

  final String matiereId;
  final String titre;

  Future<void> _ajouter(
    BuildContext context,
    WidgetRef ref,
    String titreDialogue,
    List<String> champs,
    Future<void> Function(List<String> valeurs) action,
  ) async {
    final controleurs = [for (final _ in champs) TextEditingController()];
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(titreDialogue),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (i, c) in champs.indexed)
            TextField(
              key: ValueKey('champ_$i'),
              controller: controleurs[i],
              autofocus: i == 0,
              decoration: InputDecoration(labelText: c),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
          FilledButton(key: const Key('valider_ajout'), onPressed: () => Navigator.of(d).pop(true), child: const Text('Ajouter')),
        ],
      ),
    );
    final valeurs = [for (final c in controleurs) c.text.trim()];
    if (ok != true || valeurs.any((v) => v.isEmpty)) return;
    try {
      await action(valeurs);
      ref.invalidate(structureMatiereProvider(matiereId));
    } on ErreurBanque catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final depot = ref.read(banqueQuestionsRepositoryProvider);
    final structure = ref.watch(structureMatiereProvider(matiereId));
    return Scaffold(
      appBar: AppBar(title: const Text('Chapitres et compétences')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(structureMatiereProvider(matiereId)),
        child: structure.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: const [
            Padding(padding: EdgeInsets.all(16), child: Text('Indisponible pour le moment. Tirez pour réessayer.')),
          ]),
          data: (s) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(titre, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text('Compétences', style: Theme.of(context).textTheme.titleMedium)),
                TextButton.icon(
                  key: const Key('ajouter_competence'),
                  onPressed: () => _ajouter(context, ref, 'Nouvelle compétence', ['Code (ex. FRAC-1)', 'Libellé'],
                      (v) => depot.ajouterCompetence(matiereId, v[0], v[1])),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                ),
              ]),
              if (s.competences.isEmpty) const Text('Aucune compétence. Une question en demande une.'),
              for (final c in s.competences)
                ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Text(c.code), title: Text(c.libelle)),
              const Divider(height: 32),
              Row(children: [
                Expanded(child: Text('Chapitres et leçons', style: Theme.of(context).textTheme.titleMedium)),
                TextButton.icon(
                  key: const Key('ajouter_chapitre'),
                  onPressed: () => _ajouter(context, ref, 'Nouveau chapitre', ['Titre du chapitre'],
                      (v) => depot.ajouterChapitre(matiereId, v[0], s.chapitres.length + 1)),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                ),
              ]),
              if (s.chapitres.isEmpty) const Text('Aucun chapitre.'),
              for (final c in s.chapitres)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${c.ordre}. ${c.titre}', style: const TextStyle(fontWeight: FontWeight.w600))),
                        IconButton(
                          tooltip: 'Ajouter une leçon',
                          onPressed: () => _ajouter(context, ref, 'Nouvelle leçon', ['Titre de la leçon'],
                              (v) => depot.ajouterLecon(c.id, v[0], c.lecons.length + 1)),
                          icon: const Icon(Icons.playlist_add),
                        ),
                      ]),
                      for (final l in c.lecons) Text('   ${l.ordre}. ${l.titre}'),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// File de validation : questions à valider ou à publier (cahier 30.5).
class EcranQuestionsATraiter extends ConsumerWidget {
  const EcranQuestionsATraiter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(questionsATraiterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Questions à valider')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(questionsATraiterProvider),
        child: liste.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: const [
            Padding(padding: EdgeInsets.all(16), child: Text('Liste indisponible pour le moment. Tirez pour réessayer.')),
          ]),
          data: (questions) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (questions.isEmpty) const Text('Rien à valider ni à publier.', key: Key('a_traiter_vide')),
              for (final q in questions)
                CarteQuestion(
                  question: q,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => EcranEditeurQuestion(matiereId: q.matiereId, titreMatiere: 'Validation', question: q),
                  )),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Questions signalées par les élèves ; suspendues au-delà du seuil (10.3).
class EcranQuestionsSignalees extends ConsumerWidget {
  const EcranQuestionsSignalees({super.key});

  Future<void> _retablir(BuildContext context, WidgetRef ref, Question q) async {
    try {
      await ref.read(banqueQuestionsRepositoryProvider).retablir(q.id);
      ref.invalidate(questionsSignaleesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Question rétablie, signalements traités.')));
      }
    } on ErreurBanque catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(questionsSignaleesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Questions signalées')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(questionsSignaleesProvider),
        child: liste.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: const [
            Padding(padding: EdgeInsets.all(16), child: Text('Liste indisponible pour le moment. Tirez pour réessayer.')),
          ]),
          data: (questions) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Corrigez la question si besoin (nouvelle version à publier), puis rétablissez-la.'),
              const SizedBox(height: 8),
              if (questions.isEmpty) const Text('Aucun signalement en attente.', key: Key('signalees_vide')),
              for (final q in questions)
                CarteQuestion(
                  question: q,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => EcranEditeurQuestion(matiereId: q.matiereId, titreMatiere: 'Signalement', question: q),
                  )),
                  trailing: TextButton(
                    key: ValueKey('retablir_${q.id}'),
                    onPressed: () => _retablir(context, ref, q),
                    child: const Text('Rétablir'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
