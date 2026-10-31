import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/choisir_date.dart';
import '../data/remplacements_repository.dart';
import '../domain/remplacement.dart';
import 'ecran_decision_seance.dart';
import 'elements_remplacements.dart';

/// Remplacements (REG-41), pour la direction : le plan du jour (absences,
/// cours à remplacer, décisions), les cours assurés et le compteur des
/// heures de remplacement.
class EcranRemplacements extends StatelessWidget {
  const EcranRemplacements({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Remplacements'),
          actions: [
            IconButton(
              tooltip: 'Réglages',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _Reglages(etablissementId: etablissementId),
              ),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Plan du jour'), Tab(text: 'Cours assurés'), Tab(text: 'Heures')]),
        ),
        body: TabBarView(children: [
          _PlanDuJour(etablissementId: etablissementId),
          _OngletCoursAssures(etablissementId: etablissementId),
          _OngletHeures(etablissementId: etablissementId),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan du jour
// ---------------------------------------------------------------------------

class _PlanDuJour extends ConsumerStatefulWidget {
  const _PlanDuJour({required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<_PlanDuJour> createState() => _PlanDuJourState();
}

class _PlanDuJourState extends ConsumerState<_PlanDuJour> {
  DateTime _date = jourSeul(DateTime.now());

  JourEcole get _jour => (etablissementId: widget.etablissementId, date: _date);
  PeriodeEcole get _periode =>
      (etablissementId: widget.etablissementId, du: _date, au: _date.add(const Duration(days: 30)));

  void _relire() {
    ref.invalidate(coursARemplacerProvider(_jour));
    ref.invalidate(absencesEnseignantsProvider(_periode));
  }

  Future<void> _declarer() async {
    final ok = await formulaireAbsence(context, etablissementId: widget.etablissementId);
    if (ok == true) _relire();
  }

  Future<void> _deciderAbsence(AbsenceEnseignant a, bool valider) async {
    try {
      await ref.read(remplacementsRepositoryProvider).deciderAbsence(a.id, valider);
      _relire();
    } on ErreurRemplacement catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _retirer(AbsenceEnseignant a) async {
    try {
      await ref.read(remplacementsRepositoryProvider).retirerAbsence(a.id);
      _relire();
    } on ErreurRemplacement catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cours = ref.watch(coursARemplacerProvider(_jour));
    final absences = ref.watch(absencesEnseignantsProvider(_periode)).valueOrNull ?? const <AbsenceEnseignant>[];
    final duJour = [for (final a in absences) if (!a.du.isAfter(_date) && !a.au.isBefore(_date) && !a.aValider) a];
    final aValider = [for (final a in absences) if (a.aValider) a];
    final schema = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('declarer_absence'),
        onPressed: _declarer,
        icon: const Icon(Icons.person_off_outlined),
        label: const Text('Déclarer une absence'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _relire(),
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
          Row(children: [
            IconButton(
              tooltip: 'Jour précédent',
              onPressed: () => setState(() => _date = _date.subtract(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton(
                onPressed: () async {
                  final d = await choisirDate(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now().subtract(const Duration(days: 120)),
                    lastDate: DateTime.now().add(const Duration(days: 120)),
                  );
                  if (d != null) setState(() => _date = jourSeul(d));
                },
                child: Text(jourLisible(_date), style: theme.textTheme.titleMedium),
              ),
            ),
            IconButton(
              tooltip: 'Jour suivant',
              onPressed: () => setState(() => _date = _date.add(const Duration(days: 1))),
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
          if (aValider.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Text('Absences signalées à valider', style: theme.textTheme.titleSmall),
            ),
            for (final a in aValider)
              Card(
                color: schema.tertiaryContainer,
                child: ListTile(
                  key: Key('absence_a_valider_${a.id}'),
                  title: Text(a.enseignant ?? 'Enseignant'),
                  subtitle: Text([
                    a.du == a.au ? jourLisible(a.du) : 'du ${jourLisible(a.du)} au ${jourLisible(a.au)}',
                    a.heures,
                    if (a.motif != null) a.motif!,
                  ].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Refuser', onPressed: () => _deciderAbsence(a, false), icon: const Icon(Icons.close)),
                    IconButton(
                      tooltip: 'Valider',
                      onPressed: () => _deciderAbsence(a, true),
                      icon: Icon(Icons.check, color: Colors.green.shade700),
                    ),
                  ]),
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text('Absents ce jour', style: theme.textTheme.titleSmall),
          ),
          if (duJour.isEmpty)
            const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text('Aucun enseignant absent.'))
          else
            for (final a in duJour)
              ListTile(
                dense: true,
                leading: const Icon(Icons.person_off_outlined),
                title: Text(a.enseignant ?? 'Enseignant'),
                subtitle: Text([a.heures, if (a.motif != null) a.motif!].join(' · ')),
                trailing: IconButton(tooltip: 'Retirer', onPressed: () => _retirer(a), icon: const Icon(Icons.delete_outline)),
              ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text('Cours à remplacer', style: theme.textTheme.titleSmall),
          ),
          cours.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(e is ErreurRemplacement ? e.message : 'Plan du jour indisponible pour le moment.'),
            data: (liste) {
              if (liste.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text('Aucun cours à remplacer ce jour-là.', key: Key('rien_a_remplacer')),
                );
              }
              final restants = liste.where((c) => !c.traite).length;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (restants > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                    child: Text('$restants cours sans solution', style: TextStyle(color: schema.error, fontWeight: FontWeight.w600)),
                  ),
                for (final c in liste)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      key: Key('cours_${c.emploiId}'),
                      leading: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(c.debut, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(c.fin, style: const TextStyle(fontSize: 12)),
                      ]),
                      title: Text('${c.matiere ?? 'Cours'} — ${c.classe}'),
                      subtitle: Text(
                        '${c.enseignant ?? ''}\n${texteSolution(c.modification)}',
                        style: TextStyle(color: couleurSolution(context, c.modification?.solution)),
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final ok = await Navigator.of(context)
                            .push<bool>(MaterialPageRoute(builder: (_) => EcranDecisionSeance(cours: c)));
                        if (ok == true) _relire();
                      },
                    ),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cours assurés
// ---------------------------------------------------------------------------

enum _Periode { semaine, mois, trenteJours }

PeriodeEcole _periodeDe(String etablissementId, _Periode p) {
  final aujourdhui = jourSeul(DateTime.now());
  final du = switch (p) {
    _Periode.semaine => aujourdhui.subtract(Duration(days: aujourdhui.weekday - 1)),
    _Periode.mois => DateTime(aujourdhui.year, aujourdhui.month, 1),
    _Periode.trenteJours => aujourdhui.subtract(const Duration(days: 30)),
  };
  return (etablissementId: etablissementId, du: du, au: aujourdhui);
}

class _ChoixPeriode extends StatelessWidget {
  const _ChoixPeriode({required this.valeur, required this.onChanged});

  final _Periode valeur;
  final ValueChanged<_Periode> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<_Periode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: _Periode.semaine, label: Text('Cette semaine')),
          ButtonSegment(value: _Periode.mois, label: Text('Ce mois')),
          ButtonSegment(value: _Periode.trenteJours, label: Text('30 jours')),
        ],
        selected: {valeur},
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

class _OngletCoursAssures extends ConsumerStatefulWidget {
  const _OngletCoursAssures({required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<_OngletCoursAssures> createState() => _OngletCoursAssuresState();
}

class _OngletCoursAssuresState extends ConsumerState<_OngletCoursAssures> {
  _Periode _periode = _Periode.mois;

  @override
  Widget build(BuildContext context) {
    final p = _periodeDe(widget.etablissementId, _periode);
    final assures = ref.watch(coursAssuresProvider(p));
    final schema = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(coursAssuresProvider(p)),
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        _ChoixPeriode(valeur: _periode, onChanged: (v) => setState(() => _periode = v)),
        const SizedBox(height: 12),
        assures.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text(e is ErreurRemplacement ? e.message : 'Indicateur indisponible pour le moment.'),
          data: (a) {
            if (a.prevus == 0) {
              return const Text('Aucun cours prévu sur la période (emploi du temps vide ou période à venir).');
            }
            final alertes = [for (final l in a.lignes) if (l.alerte) l];
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${(a.taux * 100).round()} %',
                  key: const Key('taux_cours_assures'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: a.taux < 0.9 ? schema.error : Colors.green.shade700,
                  )),
              Text('des cours prévus ont été assurés (${a.assures} sur ${a.prevus})', textAlign: TextAlign.center),
              Text('${minutesEnHeures(a.minutesPerdues)} de cours perdues', textAlign: TextAlign.center),
              const SizedBox(height: 6),
              const Text(
                'Un cours compte comme assuré quand l’appel ou le cahier de texte est fait, ou quand il a été remplacé.',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
              if (alertes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Plus de 10 % des heures perdues', style: theme.textTheme.titleSmall?.copyWith(color: schema.error)),
                for (final l in alertes) _LigneTaux(ligne: l),
              ],
              const SizedBox(height: 16),
              Text('Par enseignant', style: theme.textTheme.titleSmall),
              for (final e in a.enseignants)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.nom),
                  trailing: Text('${e.assures}/${e.prevus}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: LinearProgressIndicator(value: e.prevus == 0 ? 1 : e.assures / e.prevus),
                ),
              const SizedBox(height: 16),
              Text('Par classe et matière', style: theme.textTheme.titleSmall),
              for (final l in a.lignes) if (!l.alerte) _LigneTaux(ligne: l),
            ]);
          },
        ),
      ]),
    );
  }
}

class _LigneTaux extends StatelessWidget {
  const _LigneTaux({required this.ligne});

  final LigneCoursAssures ligne;

  @override
  Widget build(BuildContext context) {
    final l = ligne;
    final schema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${l.classe} · ${l.matiere ?? 'Cours'}${l.enseignant == null ? '' : ' · ${l.enseignant}'}')),
          Text('${l.assures}/${l.prevus}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 3),
        LinearProgressIndicator(value: l.taux, color: l.alerte ? schema.error : null, minHeight: 6),
        if (l.minutesPerdues > 0)
          Text('${minutesEnHeures(l.minutesPerdues)} perdues', style: TextStyle(fontSize: 12, color: schema.onSurfaceVariant)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Heures de remplacement
// ---------------------------------------------------------------------------

class _OngletHeures extends ConsumerStatefulWidget {
  const _OngletHeures({required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<_OngletHeures> createState() => _OngletHeuresState();
}

class _OngletHeuresState extends ConsumerState<_OngletHeures> {
  _Periode _periode = _Periode.mois;

  @override
  Widget build(BuildContext context) {
    final p = _periodeDe(widget.etablissementId, _periode);
    final compteur = ref.watch(compteurRemplacementsProvider(p));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(compteurRemplacementsProvider(p)),
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        _ChoixPeriode(valeur: _periode, onChanged: (v) => setState(() => _periode = v)),
        const SizedBox(height: 12),
        compteur.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text(e is ErreurRemplacement ? e.message : 'Compteur indisponible pour le moment.'),
          data: (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              c.payes
                  ? 'Remplacements payés : ${c.tarifHeure == null ? 'tarif à fixer dans les réglages' : '${c.tarifHeure!.round()} GNF de l’heure'}.'
                  : 'Remplacements non payés (réglage de l’école) : le compteur sert au suivi et à l’équité.',
            ),
            const SizedBox(height: 8),
            if (c.lignes.isEmpty)
              const Text('Aucun remplacement sur la période.')
            else
              for (final l in c.lignes)
                Card(
                  child: ListTile(
                    title: Text(l.nom),
                    subtitle: Text([
                      '${l.remplacements} remplacement${l.remplacements > 1 ? 's' : ''}',
                      '${l.etudes} étude${l.etudes > 1 ? 's' : ''}',
                      '${minutesEnHeures(l.minutes)} faites',
                      if (l.manques > 0) '${l.manques} cours manqué${l.manques > 1 ? 's' : ''}',
                    ].join(' · ')),
                    trailing: l.montant == null
                        ? null
                        : Text('${l.montant!.round()} GNF', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Réglages
// ---------------------------------------------------------------------------

class _Reglages extends ConsumerStatefulWidget {
  const _Reglages({required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<_Reglages> createState() => _ReglagesState();
}

class _ReglagesState extends ConsumerState<_Reglages> {
  bool _payes = false;
  final _tarif = TextEditingController();
  DateTime? _semaineA;
  bool _charge = false;
  bool _enCours = false;

  @override
  void dispose() {
    _tarif.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    setState(() => _enCours = true);
    try {
      await ref.read(remplacementsRepositoryProvider).regler(
            widget.etablissementId,
            payes: _payes,
            tarif: double.tryParse(_tarif.text),
            semaineA: _semaineA,
          );
      if (mounted) Navigator.of(context).pop();
    } on ErreurRemplacement catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Valeurs actuelles : lues du compteur du mois.
    if (!_charge) {
      final c = ref.watch(compteurRemplacementsProvider(_periodeDe(widget.etablissementId, _Periode.mois))).valueOrNull;
      if (c != null) {
        _payes = c.payes;
        _tarif.text = c.tarifHeure == null ? '' : c.tarifHeure!.round().toString();
        _charge = true;
      }
    }
    final bas = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bas),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Réglages des remplacements', style: Theme.of(context).textTheme.titleLarge),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Payer les heures de remplacement'),
            subtitle: const Text('Le compteur calcule le montant dû à chaque enseignant'),
            value: _payes,
            onChanged: (v) => setState(() => _payes = v),
          ),
          if (_payes)
            TextField(
              controller: _tarif,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Tarif de l’heure (GNF)', border: OutlineInputBorder()),
            ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Semaines A et B'),
            subtitle: Text(_semaineA == null
                ? 'Par défaut, la semaine de la rentrée est une semaine A. Touchez pour choisir une autre semaine A.'
                : 'Semaine A : celle du ${jourLisible(_semaineA!).toLowerCase()}'),
            onTap: () async {
              final d = await choisirDate(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                helpText: 'Un jour d’une semaine A',
              );
              if (d != null) setState(() => _semaineA = d);
            },
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _enCours ? null : _enregistrer,
            child: const Text('Enregistrer'),
          ),
        ]),
      ),
    );
  }
}
