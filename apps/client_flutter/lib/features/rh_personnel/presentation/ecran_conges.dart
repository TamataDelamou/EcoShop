import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../application/rh_providers.dart';
import '../domain/conge.dart';
import '../domain/employe.dart';
import '../domain/enums_rh.dart';
import 'widgets/pastille_statut_conge.dart';

/// Congés d'un employé (M8) — demande hors-ligne possible (file `sync_queue`,
/// même politique que le pointage de présence en M7), validation RH toujours
/// en ligne (le trigger serveur l'impose de toute façon).
class EcranConges extends ConsumerWidget {
  const EcranConges({super.key, required this.employe, required this.estRh});

  final Employe employe;
  final bool estRh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conges = ref.watch(congesDeEmployeProvider(employe.id));
    final profil = ref.watch(profilProvider).value;
    final peutDemander = profil != null && profil.id == employe.profileId;

    return Scaffold(
      appBar: AppBar(title: Text('Congés — ${employe.nomAffiche ?? employe.matricule}')),
      floatingActionButton: peutDemander
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Demander un congé'),
              onPressed: () => _ouvrirFormulaire(context, ref),
            )
          : null,
      body: conges.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Congés indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucune demande de congé.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) => EntreeAnimee(
                  index: i,
                  enfant: _CarteConge(conge: liste[i], peutValider: estRh),
                ),
              ),
      ),
    );
  }

  Future<void> _ouvrirFormulaire(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(context: context, builder: (_) => _FormulaireConge(employe: employe));
    ref.invalidate(congesDeEmployeProvider(employe.id));
  }
}

class _CarteConge extends ConsumerWidget {
  const _CarteConge({required this.conge, required this.peutValider});

  final Conge conge;
  final bool peutValider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(conge.type.libelle, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                PastilleStatutConge(statut: conge.statut),
              ],
            ),
            const SizedBox(height: 6),
            Text('Du ${_formatDate(conge.dateDebut)} au ${_formatDate(conge.dateFin)} · ${conge.nbJours} j'),
            if (conge.motif != null && conge.motif!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(conge.motif!, style: TextStyle(color: context.palette.encreSecondaire, fontSize: 13)),
            ],
            if (peutValider && conge.statut == StatutConge.demande) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _valider(ref, 'refuse'),
                    icon: Icon(Icons.close, color: context.palette.erreur),
                    label: Text('Refuser', style: TextStyle(color: context.palette.erreur)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _valider(ref, 'valide'),
                    icon: const Icon(Icons.check),
                    label: const Text('Valider'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _valider(WidgetRef ref, String statut) async {
    final profil = ref.read(profilProvider).value;
    if (profil == null) return;
    await ref.read(rhRepositoryProvider).validerConge(conge.id, statut: statut, valideePar: profil.id);
    ref.invalidate(congesDeEmployeProvider(conge.employeId));
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _FormulaireConge extends ConsumerStatefulWidget {
  const _FormulaireConge({required this.employe});

  final Employe employe;

  @override
  ConsumerState<_FormulaireConge> createState() => _FormulaireCongeState();
}

class _FormulaireCongeState extends ConsumerState<_FormulaireConge> {
  TypeConge _type = TypeConge.annuel;
  DateTime _dateDebut = DateTime.now();
  DateTime _dateFin = DateTime.now();
  final _motifCtrl = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _motifCtrl.dispose();
    super.dispose();
  }

  int get _nbJours => _dateFin.difference(_dateDebut).inDays + 1;

  Future<void> _choisirDate({required bool debut}) async {
    final choisie = await showDatePicker(
      context: context,
      initialDate: debut ? _dateDebut : _dateFin,
      firstDate: DateTime(_dateDebut.year - 1),
      lastDate: DateTime(_dateDebut.year + 2),
    );
    if (choisie == null) return;
    setState(() {
      if (debut) {
        _dateDebut = choisie;
        if (_dateFin.isBefore(_dateDebut)) _dateFin = _dateDebut;
      } else {
        _dateFin = choisie;
      }
    });
  }

  Future<void> _enregistrer() async {
    if (_nbJours <= 0) {
      setState(() => _erreur = 'La date de fin doit suivre la date de début.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final conge = construireCongeDemande(
        etablissementId: widget.employe.etablissementId,
        employeId: widget.employe.id,
        type: _type,
        dateDebut: _dateDebut,
        dateFin: _dateFin,
        nbJours: _nbJours,
        motif: _motifCtrl.text.trim().isEmpty ? null : _motifCtrl.text.trim(),
      );
      await ref.read(rhRepositoryProvider).demanderConge(conge);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = 'Envoi impossible : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Demander un congé'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<TypeConge>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type de congé'),
              items: [
                for (final type in TypeConge.values)
                  DropdownMenuItem(value: type, child: Text(type.libelle)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Du'),
              subtitle: Text(_formatDate(_dateDebut)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () => _choisirDate(debut: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Au'),
              subtitle: Text(_formatDate(_dateFin)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () => _choisirDate(debut: false),
            ),
            Text('$_nbJours jour(s)', style: TextStyle(color: context.palette.encreSecondaire)),
            const SizedBox(height: 12),
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
              : const Text('Envoyer'),
        ),
      ],
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
