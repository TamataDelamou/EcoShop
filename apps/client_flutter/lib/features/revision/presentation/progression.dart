import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/choisir_date.dart';
import '../application/revision_providers.dart';
import '../data/revision_repository.dart';
import '../domain/maitrise.dart';
import '../domain/quiz.dart';

/// Recommandation du jour, révisions espacées et plan, en haut de l'écran
/// des révisions (lot R4).
class SectionProgression extends ConsumerWidget {
  const SectionProgression({
    super.key,
    required this.ficheId,
    required this.prenom,
    required this.parent,
    required this.espace,
    required this.lancer,
    required this.lancerExamen,
  });

  final String ficheId;
  final String prenom;
  final bool parent;
  final EspaceRevision espace;
  final void Function(ConfigQuiz config) lancer;
  final void Function(String? matiereId, int nombre) lancerExamen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final petites = espace.niveau.petitesClasses;
    final p = ref.watch(progressionRevisionProvider((fiche: ficheId, petites: petites))).valueOrNull;
    if (p == null || espace.paquet.vide) return const SizedBox.shrink();
    final schema = Theme.of(context).colorScheme;
    final reco = recommandationDuJour(paquet: espace.paquet, profil: p.profil, revisions: p.revisions, petitesClasses: petites);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (reco != null)
        Card(
          color: schema.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.auto_awesome),
                const SizedBox(width: 8),
                Text(parent ? 'Conseillé aujourd’hui pour $prenom' : 'Conseillé pour toi aujourd’hui',
                    style: Theme.of(context).textTheme.labelLarge),
              ]),
              const SizedBox(height: 8),
              Text(reco.titre, key: const Key('reco_titre'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(reco.raison),
              const SizedBox(height: 12),
              FilledButton(key: const Key('reco_lancer'), onPressed: () => lancer(reco.config), child: const Text('Commencer')),
            ]),
          ),
        ),
      if (p.revisions.suivies > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${p.revisions.suivies} question${p.revisions.suivies > 1 ? 's' : ''} suivie${p.revisions.suivies > 1 ? 's' : ''} en '
            'révision espacée · ${p.revisions.retenues} bien retenue${p.revisions.retenues > 1 ? 's' : ''}',
            key: const Key('repetition_suivi'),
            style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12),
          ),
        ),
      if (!petites) _CartePlan(ficheId: ficheId, progression: p, espace: espace, lancer: lancer, lancerExamen: lancerExamen),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('ouvrir_progression'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => EcranProfilMaitrise(
              espace: espace,
              profil: p.profil,
              voirChiffres: parent || !petites,
              titre: parent ? 'Progression de $prenom' : 'Ma progression',
              lancer: lancer,
            ),
          )),
          icon: const Icon(Icons.insights_outlined),
          label: Text(parent ? 'Progression de $prenom par compétence' : 'Ma progression par compétence'),
        ),
      ),
    ]);
  }
}

class _CartePlan extends ConsumerWidget {
  const _CartePlan({
    required this.ficheId,
    required this.progression,
    required this.espace,
    required this.lancer,
    required this.lancerExamen,
  });

  final String ficheId;
  final ProgressionRevision progression;
  final EspaceRevision espace;
  final void Function(ConfigQuiz config) lancer;
  final void Function(String? matiereId, int nombre) lancerExamen;

  Future<void> _creer(BuildContext context, WidgetRef ref) async {
    final plan = await showDialog<PlanRevision>(
      context: context,
      builder: (_) => DialoguePlan(espace: espace, actuel: progression.plan),
    );
    if (plan == null) return;
    try {
      await ref.read(revisionRepositoryProvider).definirPlan(ficheId, plan);
      ref.invalidate(progressionRevisionProvider);
    } on ErreurRevision catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = progression.plan;
    final maintenant = DateTime.now();
    if (plan == null || plan.joursRestants(maintenant) <= 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton.icon(
          key: const Key('plan_creer'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(14), alignment: Alignment.centerLeft),
          onPressed: () => _creer(context, ref),
          icon: const Icon(Icons.event_note_outlined),
          label: const Text('Préparer un examen : un plan jour par jour'),
        ),
      );
    }
    final missions = missionsDuPlan(
      plan: plan,
      maintenant: maintenant,
      coefficients: progression.coefficients,
      faiblesParMatiere: _faiblesParMatiere(),
    );
    final aujourdhui = missions.firstOrNull;
    String nom(String? m) =>
        m == null ? 'Examen blanc' : espace.paquet.matieres.where((x) => x.id == m).firstOrNull?.nom ?? 'Matière';
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${plan.titre} · J-${plan.joursRestants(maintenant)}',
                  key: const Key('plan_titre'), style: Theme.of(context).textTheme.titleSmall),
            ),
            IconButton(tooltip: 'Modifier le plan', onPressed: () => _creer(context, ref), icon: const Icon(Icons.edit_outlined)),
          ]),
          if (aujourdhui != null) ...[
            Text('Mission du jour : ${nom(aujourdhui.matiereId)}'
                '${aujourdhui.examenBlanc ? '' : ' — ${aujourdhui.nombre} questions'}',
                key: const Key('plan_mission')),
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('plan_lancer'),
              onPressed: () => aujourdhui.examenBlanc
                  ? lancerExamen(null, aujourdhui.nombre)
                  : lancer(ConfigQuiz(mode: ModeQuiz.plan, matiereId: aujourdhui.matiereId, nombre: aujourdhui.nombre)),
              child: const Text('Faire la mission'),
            ),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            key: const Key('plan_calendrier'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Les 14 prochains jours'),
            children: [
              for (final m in missions.skip(1))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(m.examenBlanc ? Icons.timer_outlined : Icons.circle_outlined, size: 18),
                  title: Text(nom(m.matiereId)),
                  trailing: Text(formaterDate(m.jour)),
                ),
            ],
          ),
          Text('En cas de retard, le plan se répartit tout seul sur les jours restants.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ]),
      ),
    );
  }

  Map<String, int> _faiblesParMatiere() {
    final r = <String, int>{};
    for (final c in progression.profil.faibles()) {
      final m = espace.paquet.competences.where((k) => k.id == c.competenceId).firstOrNull?.matiereId;
      if (m != null) r[m] = (r[m] ?? 0) + 1;
    }
    return r;
  }
}

/// Créer ou modifier le plan : nom, date, matières, questions par jour.
class DialoguePlan extends StatefulWidget {
  const DialoguePlan({super.key, required this.espace, this.actuel});

  final EspaceRevision espace;
  final PlanRevision? actuel;

  @override
  State<DialoguePlan> createState() => _DialoguePlanState();
}

class _DialoguePlanState extends State<DialoguePlan> {
  late final _titre = TextEditingController(text: widget.actuel?.titre ?? 'BEPC');
  late DateTime _echeance = widget.actuel?.echeance ?? DateTime.now().add(const Duration(days: 60));
  late final Set<String> _matieres = {...?widget.actuel?.matieres};
  late int _parJour = widget.actuel?.questionsParJour ?? 10;

  @override
  void dispose() {
    _titre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.espace.paquet;
    return AlertDialog(
      title: const Text('Préparer un examen'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            key: const Key('plan_nom'),
            controller: _titre,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Examen (ex. : BEPC, composition)'),
          ),
          OutlinedButton.icon(
            key: const Key('plan_date'),
            onPressed: () async {
              final d = await choisirDate(
                context: context,
                initialDate: _echeance,
                firstDate: DateTime.now().add(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 400)),
                helpText: 'Date de l’examen',
              );
              if (d != null) setState(() => _echeance = d);
            },
            icon: const Icon(Icons.event),
            label: Text('Le ${formaterDate(_echeance)}'),
          ),
          const SizedBox(height: 12),
          const Text('Matières'),
          for (final m in p.matieres)
            if (p.questionsDe(m.id) > 0)
              CheckboxListTile(
                key: ValueKey('plan_matiere_${m.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _matieres.contains(m.id),
                title: Text(m.nom),
                onChanged: (v) => setState(() => v == true ? _matieres.add(m.id) : _matieres.remove(m.id)),
              ),
          const SizedBox(height: 8),
          Text('$_parJour questions par jour'),
          Slider(value: _parJour.toDouble(), min: 5, max: 30, divisions: 5, onChanged: (v) => setState(() => _parJour = v.round())),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          key: const Key('plan_valider'),
          onPressed: _matieres.isEmpty
              ? null
              : () => Navigator.of(context).pop(PlanRevision(
                    titre: _titre.text.trim().isEmpty ? 'Mon examen' : _titre.text.trim(),
                    echeance: _echeance,
                    matieres: _matieres.toList(),
                    questionsParJour: _parJour,
                  )),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}

/// Profil de maîtrise par matière puis par compétence (14.1). Du CP1 au
/// CE2, l'enfant ne voit ni pourcentage ni barre chiffrée : seulement des
/// mots ; le parent voit les chiffres.
class EcranProfilMaitrise extends StatelessWidget {
  const EcranProfilMaitrise({
    super.key,
    required this.espace,
    required this.profil,
    required this.voirChiffres,
    required this.titre,
    required this.lancer,
  });

  final EspaceRevision espace;
  final ProfilMaitrise profil;
  final bool voirChiffres;
  final String titre;
  final void Function(ConfigQuiz config) lancer;

  String _mot(CompetenceMaitrise? c) {
    if (c == null || c.reponses == 0) return 'Pas encore travaillée';
    if (c.reponses < 2) return 'Tout juste commencée';
    if (c.acquise) return 'Acquise';
    if (c.faible) return 'À renforcer';
    return 'En progrès';
  }

  @override
  Widget build(BuildContext context) {
    final p = espace.paquet;
    final schema = Theme.of(context).colorScheme;
    final faibles = profil.faibles();
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (faibles.isNotEmpty)
            Card(
              color: schema.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'À renforcer : ${[for (final f in faibles.take(3)) p.competences.where((k) => k.id == f.competenceId).firstOrNull?.libelle ?? ''].where((t) => t.isNotEmpty).join(', ')}.',
                  key: const Key('profil_a_renforcer'),
                ),
              ),
            ),
          for (final m in p.matieres)
            if (p.competences.any((k) => k.matiereId == m.id)) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text(m.nom, style: Theme.of(context).textTheme.titleMedium)),
                if (voirChiffres && profil.matiere(m.id, p) != null) Text('${(profil.matiere(m.id, p)! * 100).round()} %'),
              ]),
              for (final k in p.competences.where((k) => k.matiereId == m.id))
                ListTile(
                  key: ValueKey('profil_${k.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(k.libelle),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (voirChiffres && (profil.competences[k.id]?.reponses ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: LinearProgressIndicator(
                          value: profil.competences[k.id]!.maitrise,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                          color: profil.competences[k.id]!.faible ? schema.error : null,
                        ),
                      ),
                    Text(voirChiffres && (profil.competences[k.id]?.reponses ?? 0) > 0
                        ? '${_mot(profil.competences[k.id])} · ${(profil.competences[k.id]!.maitrise * 100).round()} %'
                        : _mot(profil.competences[k.id])),
                  ]),
                  trailing: p.questions.any((q) => q.contenu.competenceId == k.id)
                      ? IconButton(
                          tooltip: 'S’entraîner',
                          onPressed: () {
                            Navigator.of(context).pop();
                            lancer(ConfigQuiz(mode: ModeQuiz.competence, competenceId: k.id, petitesClasses: espace.niveau.petitesClasses));
                          },
                          icon: const Icon(Icons.play_arrow),
                        )
                      : null,
                ),
            ],
          const SizedBox(height: 16),
          Text('Calculé sur les quiz et examens blancs, les plus récents comptant davantage. '
              'Ce n’est pas une note de l’école.', style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Enseignant et direction : maîtrise des compétences par classe (14.1),
/// pour cibler une reprise de cours.
class EcranMaitriseClasses extends ConsumerWidget {
  const EcranMaitriseClasses({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(classesSuiviesProvider(etablissementId));
    return Scaffold(
      appBar: AppBar(title: const Text('Révisions des classes')),
      body: classes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(e is ErreurRevision ? e.message : 'Indisponible pour le moment.'),
        ),
        data: (l) => ListView(padding: const EdgeInsets.all(16), children: [
          if (l.isEmpty) const Text('Aucune classe suivie.', key: Key('classes_suivi_vide')),
          for (final c in l)
            Card(
              child: ListTile(
                key: ValueKey('classe_suivi_${c.id}'),
                title: Text(c.nom),
                subtitle: Text('${c.eleves} élèves'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => EcranMaitriseClasse(classeId: c.id, nom: c.nom),
                )),
              ),
            ),
        ]),
      ),
    );
  }
}

class EcranMaitriseClasse extends ConsumerWidget {
  const EcranMaitriseClasse({super.key, required this.classeId, required this.nom});

  final String classeId;
  final String nom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(maitriseClasseProvider(classeId));
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Révisions · $nom')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(maitriseClasseProvider(classeId)),
        child: m.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(e is ErreurRevision ? e.message : 'Indisponible pour le moment.')),
          ]),
          data: (v) {
            final reprendre = v.aReprendre();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              Text('${v.elevesActifs} élève${v.elevesActifs > 1 ? 's' : ''} sur ${v.eleves} ont révisé ces 30 derniers jours.',
                  key: const Key('classe_actifs')),
              if (reprendre.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  color: schema.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'À reprendre en classe : ${reprendre.map((c) => c.libelle).join(', ')} '
                      '(au moins un élève sur trois sous 50 %).',
                      key: const Key('classe_a_reprendre'),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (v.competences.isEmpty) const Text('Pas encore assez de réponses pour un diagnostic.'),
              for (final c in v.competences)
                ExpansionTile(
                  key: ValueKey('classe_competence_${c.competenceId}'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(c.libelle),
                  subtitle: Text('${c.sousSeuil} sur ${c.eleves} sous 50 % · moyenne ${(c.moyenne * 100).round()} %'),
                  children: [
                    if (c.elevesSousSeuil.isEmpty)
                      const ListTile(dense: true, title: Text('Aucun élève sous le seuil.'))
                    else
                      for (final n in c.elevesSousSeuil) ListTile(dense: true, leading: const Icon(Icons.person_outline), title: Text(n)),
                  ],
                ),
              const SizedBox(height: 16),
              Text('Résultats d’entraînement : ils ne remplacent ni les notes ni le risque d’échec.',
                  style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
            ]);
          },
        ),
      ),
    );
  }
}
