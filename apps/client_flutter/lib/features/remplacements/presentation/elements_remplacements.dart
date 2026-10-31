import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/choisir_date.dart';
import '../../configuration/application/configuration_providers.dart';
import '../../configuration/domain/configuration.dart';
import '../data/remplacements_repository.dart';
import '../domain/remplacement.dart';

const _joursCourts = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];

DateTime jourSeul(DateTime d) => DateTime(d.year, d.month, d.day);

String jourLisible(DateTime d) {
  final ecart = jourSeul(d).difference(jourSeul(DateTime.now())).inDays;
  final base = '${_joursCourts[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  return switch (ecart) { 0 => 'Aujourd’hui ($base)', 1 => 'Demain ($base)', -1 => 'Hier ($base)', _ => base };
}

String minutesEnHeures(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

Color couleurSolution(BuildContext context, SolutionSeance? s) {
  final schema = Theme.of(context).colorScheme;
  return switch (s) {
    null => schema.error,
    SolutionSeance.remplacement => Colors.green.shade700,
    SolutionSeance.etude || SolutionSeance.deplace => Colors.orange.shade800,
    SolutionSeance.annule => schema.onSurfaceVariant,
  };
}

String texteSolution(ModificationSeance? m) {
  if (m == null) return 'À traiter';
  return switch (m.solution) {
    SolutionSeance.remplacement => 'Remplacé par ${m.remplacant ?? '—'}',
    SolutionSeance.etude => 'Étude surveillée${m.remplacant == null ? '' : ' (${m.remplacant})'}',
    SolutionSeance.deplace =>
      'Déplacé${m.deplaceLe == null ? '' : ' au ${jourLisible(m.deplaceLe!).toLowerCase()} à ${m.deplaceDebut ?? ''}'}',
    SolutionSeance.annule => 'Annulé',
  };
}

String? _heure(TimeOfDay? t) =>
    t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Déclarer une absence (direction) ou prévenir de la sienne (enseignant,
/// [enseignantId] fixé). Renvoie vrai si enregistrée.
Future<bool?> formulaireAbsence(BuildContext context, {required String etablissementId, String? enseignantId}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormulaireAbsence(etablissementId: etablissementId, enseignantFixe: enseignantId),
    );

class _FormulaireAbsence extends ConsumerStatefulWidget {
  const _FormulaireAbsence({required this.etablissementId, this.enseignantFixe});

  final String etablissementId;
  final String? enseignantFixe;

  @override
  ConsumerState<_FormulaireAbsence> createState() => _FormulaireAbsenceState();
}

class _FormulaireAbsenceState extends ConsumerState<_FormulaireAbsence> {
  late String? _enseignant = widget.enseignantFixe;
  late DateTime _du = jourSeul(DateTime.now().add(Duration(days: widget.enseignantFixe == null ? 0 : 1)));
  late DateTime _au = _du;
  bool _journee = true;
  TimeOfDay _debut = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _fin = const TimeOfDay(hour: 12, minute: 0);
  final _motif = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final enseignant = _enseignant;
    if (enseignant == null) {
      setState(() => _erreur = 'Choisissez l’enseignant.');
      return;
    }
    if (!_journee && (_fin.hour * 60 + _fin.minute) <= (_debut.hour * 60 + _debut.minute)) {
      setState(() => _erreur = 'L’heure de fin doit suivre l’heure de début.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final envoye = await ref.read(remplacementsRepositoryProvider).declarerAbsence(
            id: const Uuid().v4(),
            etablissementId: widget.etablissementId,
            enseignantId: enseignant,
            du: _du,
            au: _au.isBefore(_du) ? _du : _au,
            heureDebut: _journee ? null : _heure(_debut),
            heureFin: _journee ? null : _heure(_fin),
            motif: _motif.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(!envoye
            ? 'Sans réseau : l’absence partira au retour de la connexion.'
            : widget.enseignantFixe == null
                ? 'Absence enregistrée : ses cours apparaissent dans « Cours à remplacer ».'
                : 'La direction est prévenue.'),
      ));
      Navigator.of(context).pop(true);
    } on ErreurRemplacement catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<DateTime?> _date(DateTime initiale) => choisirDate(
        context: context,
        initialDate: initiale,
        firstDate: widget.enseignantFixe == null ? DateTime.now().subtract(const Duration(days: 30)) : DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 180)),
      );

  @override
  Widget build(BuildContext context) {
    final personnel = widget.enseignantFixe != null
        ? const <MembrePersonnel>[]
        : ref.watch(personnelProvider(widget.etablissementId)).valueOrNull ?? const <MembrePersonnel>[];
    final enseignants = [for (final p in personnel) if (p.actif && p.role == 'enseignant') p]
      ..sort((a, b) => a.nomComplet.compareTo(b.nomComplet));
    final bas = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bas),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.enseignantFixe == null ? 'Déclarer une absence' : 'Prévenir d’une absence',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (widget.enseignantFixe == null) ...[
            DropdownButtonFormField<String?>(
              key: const Key('absence_enseignant'),
              initialValue: _enseignant,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Enseignant', border: OutlineInputBorder()),
              items: [for (final e in enseignants) DropdownMenuItem<String?>(value: e.profileId, child: Text(e.nomComplet))],
              onChanged: (v) => setState(() => _enseignant = v),
            ),
            const SizedBox(height: 8),
          ] else
            const Text('La direction valide, puis organise les remplacements. Vos élèves sont prévenus des changements.'),
          Row(children: [
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Du'),
                subtitle: Text(jourLisible(_du)),
                onTap: () async {
                  final d = await _date(_du);
                  if (d != null) setState(() => _du = d);
                },
              ),
            ),
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Au'),
                subtitle: Text(jourLisible(_au.isBefore(_du) ? _du : _au)),
                onTap: () async {
                  final d = await _date(_au.isBefore(_du) ? _du : _au);
                  if (d != null) setState(() => _au = d);
                },
              ),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Toute la journée'),
            value: _journee,
            onChanged: (v) => setState(() => _journee = v),
          ),
          if (!_journee)
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _debut);
                    if (t != null) setState(() => _debut = t);
                  },
                  child: Text('De ${_heure(_debut)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _fin);
                    if (t != null) setState(() => _fin = t);
                  },
                  child: Text('À ${_heure(_fin)}'),
                ),
              ),
            ]),
          const SizedBox(height: 8),
          TextField(
            controller: _motif,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Motif (facultatif)', border: OutlineInputBorder()),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('enregistrer_absence'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _enCours ? null : _enregistrer,
            child: Text(widget.enseignantFixe == null ? 'Enregistrer l’absence' : 'Prévenir la direction'),
          ),
        ]),
      ),
    );
  }
}
