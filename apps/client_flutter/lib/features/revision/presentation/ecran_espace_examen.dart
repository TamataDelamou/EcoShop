import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/choisir_date.dart';
import '../application/revision_providers.dart';
import '../data/revision_repository.dart';
import '../domain/examen.dart';
import '../domain/examen_national.dart';
import '../domain/maitrise.dart';
import '../domain/quiz.dart';
import 'ecran_examen.dart';
import 'ecran_quiz.dart';
import 'progression.dart';

/// Espace de préparation à un examen national (cahier 13.2) : compte à
/// rebours, note prévisionnelle, épreuves blanches à la durée réelle,
/// annales, entraînement ciblé et plan pré-rempli.
class EcranEspaceExamen extends ConsumerWidget {
  const EcranEspaceExamen({
    super.key,
    required this.ficheId,
    required this.prenom,
    required this.parent,
    required this.examenId,
  });

  final String ficheId;
  final String prenom;
  final bool parent;
  final String examenId;

  void _quiz(BuildContext context, EspaceRevision e, ConfigQuiz config) {
    final questions = choisirQuestions(e.paquet, config, traces: e.traces);
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pas encore de questions ici. L’équipe pédagogique en prépare.')),
      );
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

  void _examen(
    BuildContext context,
    EspaceRevision e,
    EspaceExamen x, {
    required List<QuestionQuiz> questions,
    required int dureeS,
    String? matiereId,
    String? epreuveId,
  }) {
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pas encore assez de questions pour cette épreuve.')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EcranExamen(
        examen: SessionExamen(
          id: const Uuid().v4(),
          ficheId: ficheId,
          matiereId: matiereId,
          examenId: x.id,
          epreuveId: epreuveId,
          remiseAutomatique: x.remiseAutomatique,
          questions: questions,
          dureeLimiteS: dureeS,
        ),
        competences: {for (final k in e.paquet.competences) k.id: k.libelle},
      ),
    ));
  }

  void _epreuveBlanche(BuildContext context, EspaceRevision e, EspaceExamen x, EpreuveExamen ep) {
    final questions = ep.matiereId == null
        ? <QuestionQuiz>[]
        : (choisirQuestions(e.paquet, ConfigQuiz(mode: ModeQuiz.examen, matiereId: ep.matiereId, nombre: ep.questionsBlanc),
            traces: e.traces)
          ..shuffle());
    _examen(context, e, x, questions: questions, dureeS: ep.dureeMin * 60, matiereId: ep.matiereId, epreuveId: ep.id);
  }

  void _annaleInteractive(BuildContext context, EspaceRevision e, EspaceExamen x, AnnaleExamen a) {
    final parId = {for (final q in e.paquet.questions) q.id: q};
    final questions = [for (final id in a.questionIds) ?parId[id]];
    final ep = x.epreuves.where((p) => p.id == a.epreuveId).firstOrNull;
    _examen(context, e, x,
        questions: questions,
        dureeS: ep == null ? dureeConseilleeS(questions) : ep.dureeMin * 60,
        matiereId: ep?.matiereId,
        epreuveId: ep?.id);
  }

  Future<void> _ouvrir(BuildContext context, WidgetRef ref, String chemin) async {
    try {
      final lien = await ref.read(revisionRepositoryProvider).lienAnnale(chemin);
      await launchUrl(lien, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document visible avec le réseau.')));
      }
    }
  }

  Future<void> _plan(BuildContext context, WidgetRef ref, EspaceRevision e, EspaceExamen x) async {
    final date = x.dateExamen(DateTime.now())?.date ?? DateTime.now().add(const Duration(days: 60));
    final plan = await showDialog<PlanRevision>(
      context: context,
      builder: (_) => DialoguePlan(
        espace: e,
        actuel: PlanRevision(titre: x.code, echeance: date, matieres: x.matieres),
      ),
    );
    if (plan == null) return;
    try {
      await ref.read(revisionRepositoryProvider).definirPlan(ficheId, plan);
      ref.invalidate(progressionRevisionProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plan enregistré : la mission du jour apparaît dans « Réviser ».')),
        );
      }
    } on ErreurRevision catch (err) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final espace = ref.watch(espaceRevisionProvider(ficheId)).valueOrNull;
    final examens = ref.watch(espacesExamensProvider(ficheId)).valueOrNull;
    final x = examens?.where((e) => e.id == examenId).firstOrNull;
    if (espace == null || x == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final progression =
        ref.watch(progressionRevisionProvider((fiche: ficheId, petites: espace.niveau.petitesClasses))).valueOrNull;
    final profil = progression?.profil ?? const ProfilMaitrise();
    final schema = Theme.of(context).colorScheme;
    final maintenant = DateTime.now();
    final date = x.dateExamen(maintenant);
    final jours = x.joursRestants(maintenant);
    final prevision = x.notePrevisionnelle(profil, espace.paquet);
    final prioritaire = x.epreuvePrioritaire(profil, espace.paquet);
    String note(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2).replaceAll('.', ',');

    return Scaffold(
      appBar: AppBar(title: Text(parent ? '${x.code} de $prenom' : 'Préparer le ${x.code}')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(espacesExamensProvider(ficheId)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(x.nom, style: Theme.of(context).textTheme.titleMedium),
            if (x.organisme != null) Text(x.organisme!, style: TextStyle(color: schema.onSurfaceVariant)),
            const SizedBox(height: 12),
            if (date != null && jours != null && jours >= 0)
              Card(
                color: schema.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Text('J-$jours', key: const Key('examen_compte_rebours'),
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(date.estimee
                          ? 'Session vers le ${formaterDate(date.date)} (date estimée, à confirmer)'
                          : 'Session le ${formaterDate(date.date)}'),
                    ),
                  ]),
                ),
              ),
            // Préparation (RG-013-02)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Préparation', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  if (prevision == null)
                    const Text('Fais une première épreuve blanche pour estimer ton niveau.', key: Key('examen_prevision_vide'))
                  else ...[
                    Text('${note(prevision.note)} / 20', key: const Key('examen_prevision'),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text('Note estimée, pondérée par les coefficients · '
                        '${(prevision.couverture * 100).round()} % des coefficients évalués'),
                  ],
                  const SizedBox(height: 4),
                  Text('Indication d’entraînement : ce n’est ni une note de l’école ni un résultat officiel.',
                      style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
                ]),
              ),
            ),
            if (prioritaire != null)
              FilledButton.icon(
                key: const Key('examen_entrainement_cible'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(14)),
                onPressed: () {
                  final faible = profil.faibles().where((c) => espace.paquet.competences
                      .any((k) => k.id == c.competenceId && k.matiereId == prioritaire.matiereId)).firstOrNull;
                  _quiz(
                    context,
                    espace,
                    faible == null
                        ? ConfigQuiz(mode: ModeQuiz.matiere, matiereId: prioritaire.matiereId)
                        : ConfigQuiz(mode: ModeQuiz.competence, competenceId: faible.competenceId),
                  );
                },
                icon: const Icon(Icons.track_changes),
                label: Text('S’entraîner en priorité : ${prioritaire.libelle}'),
              ),
            if (x.matieres.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  key: const Key('examen_plan'),
                  onPressed: () => _plan(context, ref, espace, x),
                  icon: const Icon(Icons.event_note_outlined),
                  label: Text('Plan de révision jusqu’au ${x.code}'),
                ),
              ),
            if (x.finPrimaire && parent)
              SwitchListTile(
                key: const Key('examen_chrono_strict'),
                contentPadding: EdgeInsets.zero,
                value: x.chronoStrict,
                title: const Text('Ramasser la copie à la fin du temps'),
                subtitle: Text('À activer dans les dernières semaines : jusque-là, le chronomètre reste indicatif pour '
                    '$prenom (conseil du cahier pour la fin du primaire).'),
                onChanged: (v) async {
                  try {
                    await ref.read(revisionRepositoryProvider).definirChronoStrict(ficheId, v);
                    ref.invalidate(espacesExamensProvider(ficheId));
                  } on ErreurRevision catch (err) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
                  }
                },
              ),
            const SizedBox(height: 16),
            Text('Épreuves blanches', style: Theme.of(context).textTheme.titleMedium),
            Text(x.remiseAutomatique
                ? 'À la durée réelle : la copie est ramassée à la fin du temps, la correction arrive ensuite.'
                : 'Chronomètre indicatif : prends le temps de finir, la correction arrive après la remise.',
                style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
            if (x.epreuves.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Les épreuves de cet examen seront bientôt décrites par l’équipe pédagogique.'),
              ),
            for (final ep in x.epreuves)
              Card(
                key: ValueKey('epreuve_${ep.id}'),
                child: ListTile(
                  title: Text(ep.libelle),
                  subtitle: Text([
                    '${ep.dureeMin ~/ 60 > 0 ? '${ep.dureeMin ~/ 60} h ' : ''}${ep.dureeMin % 60 > 0 ? '${ep.dureeMin % 60} min' : ''}'.trim(),
                    'coefficient ${note(ep.coefficient)}',
                    if (x.blancs[ep.id] case final b?)
                      '${b.nombre} blanc${b.nombre > 1 ? 's' : ''} · dernier ${note(b.derniere ?? 0)}/20 · meilleur ${note(b.meilleure ?? 0)}/20',
                  ].join(' · ')),
                  trailing: const Icon(Icons.timer_outlined),
                  onTap: () => _epreuveBlanche(context, espace, x, ep),
                ),
              ),
            const SizedBox(height: 16),
            Text('Annales', style: Theme.of(context).textTheme.titleMedium),
            if (x.annales.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Pas encore d’annales : elles ne sont publiées qu’avec l’accord de leur source officielle.'),
              ),
            for (final a in x.annales)
              Card(
                key: ValueKey('annale_${a.id}'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.titre, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Session ${a.annee}${a.session == 'normale' ? '' : ' (${a.session})'} · source : ${a.source}',
                        style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
                    Wrap(spacing: 4, children: [
                      if (a.interactive)
                        TextButton.icon(
                          key: ValueKey('annale_faire_${a.id}'),
                          onPressed: () => _annaleInteractive(context, espace, x, a),
                          icon: const Icon(Icons.edit_note),
                          label: const Text('Faire en conditions réelles'),
                        ),
                      if (a.sujetChemin != null)
                        TextButton.icon(
                          onPressed: () => _ouvrir(context, ref, a.sujetChemin!),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Sujet'),
                        ),
                      if (a.corrigeChemin != null)
                        TextButton.icon(
                          onPressed: () => _ouvrir(context, ref, a.corrigeChemin!),
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Corrigé'),
                        ),
                    ]),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Carte d'entrée dans l'espace, en haut de « Réviser ».
class CartesEspacesExamens extends ConsumerWidget {
  const CartesEspacesExamens({super.key, required this.ficheId, required this.prenom, required this.parent});

  final String ficheId;
  final String prenom;
  final bool parent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final examens = ref.watch(espacesExamensProvider(ficheId)).valueOrNull ?? const <EspaceExamen>[];
    if (examens.isEmpty) return const SizedBox.shrink();
    final maintenant = DateTime.now();
    return Column(children: [
      for (final x in examens)
        Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: ListTile(
            key: ValueKey('espace_examen_${x.id}'),
            leading: const Icon(Icons.school_outlined),
            title: Text(parent ? '$prenom prépare le ${x.code}' : 'Préparer le ${x.code}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              if (x.joursRestants(maintenant) case final j? when j >= 0) 'J-$j',
              'épreuves blanches, annales, plan',
            ].join(' · ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => EcranEspaceExamen(ficheId: ficheId, prenom: prenom, parent: parent, examenId: x.id),
            )),
          ),
        ),
    ]);
  }
}
