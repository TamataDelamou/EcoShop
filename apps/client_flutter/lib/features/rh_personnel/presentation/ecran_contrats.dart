import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/rh_providers.dart';
import '../domain/contrat.dart';
import '../domain/employe.dart';
import '../domain/enums_rh.dart';

/// Contrats d'un employé (M8, gestion RH). Toujours en ligne — un contrat
/// engage juridiquement l'établissement (cf. `RhRepository.creerContrat`).
class EcranContrats extends ConsumerWidget {
  const EcranContrats({super.key, required this.employe});

  final Employe employe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contrats = ref.watch(contratsDeEmployeProvider(employe.id));

    return Scaffold(
      appBar: AppBar(title: Text('Contrats — ${employe.nomAffiche ?? employe.matricule}')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nouveau contrat'),
        onPressed: () => _ouvrirFormulaire(context, ref),
      ),
      body: contrats.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Contrats indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucun contrat enregistré.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) =>
                    EntreeAnimee(index: i, enfant: _CarteContrat(contrat: liste[i])),
              ),
      ),
    );
  }

  Future<void> _ouvrirFormulaire(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FormulaireContrat(employe: employe),
    );
    ref.invalidate(contratsDeEmployeProvider(employe.id));
  }
}

class _CarteContrat extends StatelessWidget {
  const _CarteContrat({required this.contrat});

  final Contrat contrat;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          contrat.estEnCours ? Icons.check_circle_outline : Icons.history,
          color: contrat.estEnCours ? AppColors.vertMenthe : AppColors.encreSecondaire,
        ),
        title: Text(contrat.type.libelle),
        subtitle: Text(
          contrat.dateFin == null
              ? 'Depuis le ${_formatDate(contrat.dateDebut)}'
              : 'Du ${_formatDate(contrat.dateDebut)} au ${_formatDate(contrat.dateFin!)}',
        ),
        trailing: Text(contrat.salaireBase.toStringAsFixed(0)),
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _FormulaireContrat extends ConsumerStatefulWidget {
  const _FormulaireContrat({required this.employe});

  final Employe employe;

  @override
  ConsumerState<_FormulaireContrat> createState() => _FormulaireContratState();
}

class _FormulaireContratState extends ConsumerState<_FormulaireContrat> {
  TypeContrat _type = TypeContrat.cdd;
  DateTime _dateDebut = DateTime.now();
  DateTime? _dateFin;
  bool _renouvellementAuto = false;
  final _salaireCtrl = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _salaireCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirDate({required bool debut}) async {
    final choisie = await showDatePicker(
      context: context,
      initialDate: debut ? _dateDebut : (_dateFin ?? _dateDebut),
      firstDate: DateTime(_dateDebut.year - 5),
      lastDate: DateTime(_dateDebut.year + 10),
    );
    if (choisie == null) return;
    setState(() => debut ? _dateDebut = choisie : _dateFin = choisie);
  }

  Future<void> _enregistrer() async {
    final salaire = double.tryParse(_salaireCtrl.text.replaceAll(',', '.'));
    if (salaire == null || salaire < 0) {
      setState(() => _erreur = 'Salaire de base invalide.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      await ref.read(rhRepositoryProvider).creerContrat(
            Contrat(
              id: '',
              etablissementId: widget.employe.etablissementId,
              employeId: widget.employe.id,
              type: _type,
              dateDebut: _dateDebut,
              dateFin: _dateFin,
              salaireBase: salaire,
              renouvellementAuto: _renouvellementAuto,
            ),
          );
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
      title: const Text('Nouveau contrat'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<TypeContrat>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type de contrat'),
              items: [
                for (final type in TypeContrat.values)
                  DropdownMenuItem(value: type, child: Text(type.libelle)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _salaireCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Salaire de base'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date de début'),
              subtitle: Text(_formatDate(_dateDebut)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () => _choisirDate(debut: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date de fin'),
              subtitle: Text(_dateFin == null ? 'Indéterminée (CDI)' : _formatDate(_dateFin!)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_dateFin != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dateFin = null),
                    ),
                  const Icon(Icons.calendar_today_outlined),
                ],
              ),
              onTap: () => _choisirDate(debut: false),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Renouvellement automatique'),
              value: _renouvellementAuto,
              onChanged: (v) => setState(() => _renouvellementAuto = v),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(_erreur!, style: const TextStyle(color: AppColors.erreur)),
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
