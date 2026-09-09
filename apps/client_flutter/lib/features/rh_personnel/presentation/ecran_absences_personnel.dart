import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/rh_providers.dart';
import '../domain/absence_personnel.dart';
import '../domain/employe.dart';
import '../domain/enums_rh.dart';

/// Absences pointées d'un employé (M8) — pointage RH, hors-ligne possible
/// (file `sync_queue`, même politique que l'appel de classe en M7).
class EcranAbsencesPersonnel extends ConsumerWidget {
  const EcranAbsencesPersonnel({super.key, required this.employe, required this.estRh});

  final Employe employe;
  final bool estRh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final absences = ref.watch(absencesDeEmployeProvider(employe.id));

    return Scaffold(
      appBar: AppBar(title: Text('Absences — ${employe.nomAffiche ?? employe.matricule}')),
      floatingActionButton: estRh
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Pointer une absence'),
              onPressed: () => _ouvrirFormulaire(context, ref),
            )
          : null,
      body: absences.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Absences indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucune absence pointée.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) =>
                    EntreeAnimee(index: i, enfant: _CarteAbsence(absence: liste[i])),
              ),
      ),
    );
  }

  Future<void> _ouvrirFormulaire(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(context: context, builder: (_) => _FormulaireAbsence(employe: employe));
    ref.invalidate(absencesDeEmployeProvider(employe.id));
  }
}

class _CarteAbsence extends StatelessWidget {
  const _CarteAbsence({required this.absence});

  final AbsencePersonnel absence;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          absence.justifie ? Icons.check_circle_outline : Icons.warning_amber_outlined,
          color: absence.justifie ? context.palette.succes : context.palette.accent,
        ),
        title: Text('${absence.type.libelle} — ${_formatDate(absence.dateAbsence)}'),
        subtitle: absence.motif != null ? Text(absence.motif!) : null,
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _FormulaireAbsence extends ConsumerStatefulWidget {
  const _FormulaireAbsence({required this.employe});

  final Employe employe;

  @override
  ConsumerState<_FormulaireAbsence> createState() => _FormulaireAbsenceState();
}

class _FormulaireAbsenceState extends ConsumerState<_FormulaireAbsence> {
  DateTime _date = DateTime.now();
  TypeAbsencePersonnel _type = TypeAbsencePersonnel.injustifiee;
  bool _justifie = false;
  final _motifCtrl = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _motifCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final choisie = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime.now(),
    );
    if (choisie != null) setState(() => _date = choisie);
  }

  Future<void> _enregistrer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final absence = construireAbsencePointage(
        etablissementId: widget.employe.etablissementId,
        employeId: widget.employe.id,
        dateAbsence: _date,
        type: _type,
        justifie: _justifie,
        motif: _motifCtrl.text.trim().isEmpty ? null : _motifCtrl.text.trim(),
      );
      await ref.read(rhRepositoryProvider).pointerAbsence(absence);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = 'Enregistrement impossible : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pointer une absence'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_formatDate(_date)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _choisirDate,
            ),
            DropdownButtonFormField<TypeAbsencePersonnel>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: "Type d'absence"),
              items: [
                for (final type in TypeAbsencePersonnel.values)
                  DropdownMenuItem(value: type, child: Text(type.libelle)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Justifiée'),
              value: _justifie,
              onChanged: (v) => setState(() => _justifie = v),
            ),
            TextField(
              controller: _motifCtrl,
              decoration: const InputDecoration(labelText: 'Motif (optionnel)'),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(_erreur!, style: TextStyle(color: context.palette.erreur)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _enCours ? null : _enregistrer,
          child: _enCours
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
