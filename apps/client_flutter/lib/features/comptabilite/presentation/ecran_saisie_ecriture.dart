import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/device_id_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../application/comptabilite_providers.dart';
import '../domain/comptabilite_repository.dart';
import '../domain/journal.dart';
import '../domain/plan_comptable.dart';

/// Saisie d'une écriture comptable (M14) — partie double : un débit et un
/// crédit de même montant. Le garde-fou mono-compte (débit ≠ crédit) est
/// vérifié ici côté client avant envoi, et de toute façon rejeté par le
/// trigger serveur `ecritures_verifie_tenant` (`ECRITURE_COMPTES_IDENTIQUES`)
/// si contourné. Tolérant hors-ligne : la saisie est mise en file
/// `sync_queue` sur panne réseau et rejouée au retour de la connexion.
class EcranSaisieEcriture extends ConsumerStatefulWidget {
  const EcranSaisieEcriture({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranSaisieEcriture> createState() => _EcranSaisieEcritureState();
}

class _EcranSaisieEcritureState extends ConsumerState<EcranSaisieEcriture> {
  final _libelleCtrl = TextEditingController();
  final _montantCtrl = TextEditingController();
  final _pieceCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  Journal? _journal;
  PlanComptable? _compteDebit;
  PlanComptable? _compteCredit;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _libelleCtrl.dispose();
    _montantCtrl.dispose();
    _pieceCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final journal = _journal;
    final debit = _compteDebit;
    final credit = _compteCredit;
    final montant = double.tryParse(_montantCtrl.text.replaceAll(',', '.'));

    if (journal == null || debit == null || credit == null || montant == null || montant <= 0) {
      setState(() => _erreur = 'Renseignez le journal, les deux comptes et un montant positif.');
      return;
    }
    if (debit.id == credit.id) {
      setState(() => _erreur = 'Le compte débité doit être différent du compte crédité.');
      return;
    }
    if (_libelleCtrl.text.trim().isEmpty) {
      setState(() => _erreur = 'Le libellé est obligatoire.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      final profil = ref.read(profilProvider).value;
      final ecriture = construireEcriture(
        etablissementId: widget.etablissementId,
        journalId: journal.id,
        dateEcriture: _date,
        libelle: _libelleCtrl.text.trim(),
        compteDebitId: debit.id,
        compteCreditId: credit.id,
        montant: montant,
        pieceJustificative: _pieceCtrl.text.trim().isEmpty ? null : _pieceCtrl.text.trim(),
        userId: profil?.id,
        deviceId: deviceId,
      );
      final synchronisee = await ref.read(comptabiliteRepositoryProvider).enregistrerEcriture(ecriture);
      if (!mounted) return;
      ref.invalidate(ecrituresRecentesProvider(widget.etablissementId));
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(synchronisee ? 'Écriture enregistrée.' : 'Écriture mise en file — sera synchronisée.')),
      );
    } on ErreurComptabilite catch (e) {
      setState(() => _erreur = _messageErreur(e.code));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  String _messageErreur(String code) => switch (code) {
        'ECRITURE_TENANT_INCOHERENT' => "Un des comptes n'appartient pas à cet établissement.",
        'ECRITURE_COMPTES_IDENTIQUES' => 'Le compte débité doit être différent du compte crédité.',
        _ => 'Enregistrement impossible pour le moment.',
      };

  @override
  Widget build(BuildContext context) {
    final journaux = ref.watch(journauxProvider(widget.etablissementId));
    final comptes = ref.watch(planComptableProvider(widget.etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle écriture')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text('${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final choisie = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (choisie != null) setState(() => _date = choisie);
              },
            ),
            journaux.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const Text('Journaux indisponibles hors connexion.'),
              data: (liste) => DropdownButtonFormField<Journal>(
                initialValue: _journal,
                decoration: const InputDecoration(labelText: 'Journal'),
                items: liste.map((j) => DropdownMenuItem(value: j, child: Text(j.libelle))).toList(),
                onChanged: (v) => setState(() => _journal = v),
              ),
            ),
            const SizedBox(height: 12),
            comptes.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const Text('Comptes indisponibles hors connexion.'),
              data: (liste) => Column(
                children: [
                  DropdownButtonFormField<PlanComptable>(
                    initialValue: _compteDebit,
                    decoration: const InputDecoration(labelText: 'Compte débité'),
                    items: liste.map((c) => DropdownMenuItem(value: c, child: Text(c.libelle))).toList(),
                    onChanged: (v) => setState(() => _compteDebit = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PlanComptable>(
                    initialValue: _compteCredit,
                    decoration: const InputDecoration(labelText: 'Compte crédité'),
                    items: liste.map((c) => DropdownMenuItem(value: c, child: Text(c.libelle))).toList(),
                    onChanged: (v) => setState(() => _compteCredit = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _montantCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Montant'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _libelleCtrl, decoration: const InputDecoration(labelText: 'Libellé')),
            const SizedBox(height: 12),
            TextField(
              controller: _pieceCtrl,
              decoration: const InputDecoration(labelText: 'Pièce justificative (optionnel)'),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _enCours ? null : _enregistrer,
              child: _enCours
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
