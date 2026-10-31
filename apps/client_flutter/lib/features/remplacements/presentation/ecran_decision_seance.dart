import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/choisir_date.dart';
import '../data/remplacements_repository.dart';
import '../domain/remplacement.dart';
import 'elements_remplacements.dart';

/// Décider pour un cours dont l'enseignant est absent (REG-41) :
/// remplaçant (classés comme Untis : libres, même matière, connaissent la
/// classe, moins sollicités), étude surveillée, déplacement ou annulation.
/// Élèves (et parents si annulé, en étude ou déplacé) sont prévenus.
class EcranDecisionSeance extends ConsumerStatefulWidget {
  const EcranDecisionSeance({super.key, required this.cours});

  final CoursARemplacer cours;

  @override
  ConsumerState<EcranDecisionSeance> createState() => _EcranDecisionSeanceState();
}

class _EcranDecisionSeanceState extends ConsumerState<EcranDecisionSeance> {
  late SolutionSeance _solution = widget.cours.modification?.solution ?? SolutionSeance.remplacement;
  late String? _personne = widget.cours.modification?.remplacantId;
  late DateTime _deplaceLe = widget.cours.modification?.deplaceLe ?? widget.cours.date.add(const Duration(days: 1));
  TimeOfDay _deplaceDebut = const TimeOfDay(hour: 15, minute: 0);
  late final _note = TextEditingController(text: widget.cours.modification?.note ?? '');
  List<RemplacantPossible>? _candidats;
  ErreurRemplacement? _erreurCandidats;
  bool _enCours = false;
  String? _erreur;

  int get _dureeMinutes {
    int m(String hm) {
      final p = hm.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    try {
      return m(widget.cours.fin) - m(widget.cours.debut);
    } catch (_) {
      return 60;
    }
  }

  @override
  void initState() {
    super.initState();
    _chargerCandidats();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _chargerCandidats() async {
    try {
      final c = await ref.read(remplacementsRepositoryProvider).remplacants(widget.cours.emploiId, widget.cours.date);
      if (mounted) setState(() => _candidats = c);
    } on ErreurRemplacement catch (e) {
      if (mounted) setState(() => _erreurCandidats = e);
    }
  }

  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _enregistrer() async {
    if ((_solution == SolutionSeance.remplacement || _solution == SolutionSeance.etude) && _personne == null) {
      setState(() => _erreur = _solution == SolutionSeance.remplacement ? 'Choisissez le remplaçant.' : 'Choisissez qui surveille.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final fin = _deplaceDebut.hour * 60 + _deplaceDebut.minute + _dureeMinutes;
    try {
      final envoye = await ref.read(remplacementsRepositoryProvider).decider(
            id: widget.cours.modification?.id ?? const Uuid().v4(),
            emploiId: widget.cours.emploiId,
            date: widget.cours.date,
            solution: _solution,
            remplacantId: _personne,
            deplaceLe: _solution == SolutionSeance.deplace ? _deplaceLe : null,
            deplaceDebut: _solution == SolutionSeance.deplace ? _hhmm(_deplaceDebut) : null,
            deplaceFin: _solution == SolutionSeance.deplace
                ? '${(fin ~/ 60).clamp(0, 23).toString().padLeft(2, '0')}:${(fin % 60).toString().padLeft(2, '0')}'
                : null,
            note: _note.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(envoye
            ? 'Décision enregistrée : ${_solution == SolutionSeance.remplacement ? 'le remplaçant et les élèves sont prévenus' : 'élèves et parents sont prévenus'}.'
            : 'Sans réseau : la décision partira au retour de la connexion.'),
      ));
      Navigator.of(context).pop(true);
    } on ErreurRemplacement catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _annulerDecision() async {
    try {
      await ref.read(remplacementsRepositoryProvider).annulerDecision(widget.cours.modification!.id);
      if (mounted) Navigator.of(context).pop(true);
    } on ErreurRemplacement catch (e) {
      setState(() => _erreur = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cours;
    final schema = Theme.of(context).colorScheme;
    final pourEtude = _solution == SolutionSeance.etude;
    final candidats = [
      for (final x in _candidats ?? const <RemplacantPossible>[])
        if (pourEtude || x.enseignant) x,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('${c.matiere ?? 'Cours'} — ${c.classe}'),
        actions: [
          if (c.modification != null)
            TextButton(onPressed: _annulerDecision, child: const Text('Revenir sur la décision')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        Text('${jourLisible(c.date)} · ${c.debut} – ${c.fin}${c.salle == null ? '' : ' · salle ${c.salle}'}'),
        if (c.enseignant != null) Text('Enseignant absent : ${c.enseignant}'),
        const SizedBox(height: 12),
        SegmentedButton<SolutionSeance>(
          key: const Key('choix_solution'),
          showSelectedIcon: false,
          segments: [
            for (final s in SolutionSeance.values) ButtonSegment(value: s, label: Text(s.libelle, textAlign: TextAlign.center)),
          ],
          selected: {_solution},
          onSelectionChanged: (v) => setState(() {
            _solution = v.first;
            if (_solution == SolutionSeance.remplacement && !(candidats.any((x) => x.profileId == _personne && x.enseignant))) {
              _personne = null;
            }
          }),
        ),
        const SizedBox(height: 12),
        if (_solution == SolutionSeance.remplacement || pourEtude) ...[
          Text(pourEtude ? 'Qui surveille ?' : 'Remplaçants libres à cette heure', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          if (_erreurCandidats != null)
            Text(_erreurCandidats!.message)
          else if (_candidats == null)
            const LinearProgressIndicator()
          else if (candidats.isEmpty)
            const Text('Personne n’est libre à cette heure : choisissez l’étude, le déplacement ou l’annulation.')
          else
            RadioGroup<String>(
              groupValue: _personne,
              onChanged: (v) => setState(() => _personne = v),
              child: Column(children: [
            for (final (i, x) in candidats.indexed)
              RadioListTile<String>(
                key: Key('candidat_${x.profileId}'),
                contentPadding: EdgeInsets.zero,
                value: x.profileId,
                title: Row(children: [
                  Flexible(child: Text(x.nom)),
                  if (i == 0 && !pourEtude) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: schema.primaryContainer, borderRadius: BorderRadius.circular(6)),
                      child: Text('conseillé', style: TextStyle(fontSize: 11, color: schema.onPrimaryContainer)),
                    ),
                  ],
                ]),
                subtitle: Text([
                  if (x.memeMatiere) 'même matière',
                  if (x.connaitClasse) 'connaît la classe',
                  if (!x.enseignant) 'personnel',
                  x.ceMois == 0 ? 'aucun remplacement ce mois' : '${x.ceMois} remplacement${x.ceMois > 1 ? 's' : ''} ce mois',
                ].join(' · ')),
              ),
              ]),
            ),
        ],
        if (_solution == SolutionSeance.deplace) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text('Le ${jourLisible(_deplaceLe).toLowerCase()}'),
            onTap: () async {
              final d = await choisirDate(
                context: context,
                initialDate: _deplaceLe,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 60)),
              );
              if (d != null) setState(() => _deplaceLe = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text('À ${_hhmm(_deplaceDebut)} (${minutesEnHeures(_dureeMinutes)})'),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: _deplaceDebut);
              if (t != null) setState(() => _deplaceDebut = t);
            },
          ),
        ],
        if (_solution == SolutionSeance.annule)
          const Text('Les élèves et les parents sont prévenus. Le cours compte comme perdu dans « Cours assurés ».'),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Message (facultatif)',
            hintText: 'Ex. : apporter le cahier d’exercices, salle 3',
            border: OutlineInputBorder(),
          ),
        ),
        if (_erreur != null) ...[
          const SizedBox(height: 8),
          Text(_erreur!, style: TextStyle(color: schema.error)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('enregistrer_decision'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _enCours ? null : _enregistrer,
          child: const Text('Enregistrer et prévenir'),
        ),
      ]),
    );
  }
}
