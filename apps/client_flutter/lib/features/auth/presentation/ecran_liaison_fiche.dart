import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coquille/application/session_logout.dart';
import '../application/auth_providers.dart';
import '../application/connexion_controller.dart';
import '../domain/auth_repository.dart';

/// Liaison compte ↔ fiche scolaire (cahier v4.1, ch. 5.8).
///
/// Double facteur **matricule + date de naissance**. La vérification est
/// entièrement serveur (RPC `lier_compte_a_fiche`), qui limite aussi le nombre
/// de tentatives : l'écran n'a aucun moyen de contourner ce plafond, et ne
/// distingue jamais « matricule inconnu » de « date incorrecte » — cette
/// indifférenciation est volontaire, elle empêche d'énumérer les matricules.
class EcranLiaisonFiche extends ConsumerStatefulWidget {
  const EcranLiaisonFiche({super.key});

  @override
  ConsumerState<EcranLiaisonFiche> createState() => _EcranLiaisonFicheState();
}

class _EcranLiaisonFicheState extends ConsumerState<EcranLiaisonFiche> {
  final _matriculeCtrl = TextEditingController();
  DateTime? _dateNaissance;
  bool _enCours = false;
  String? _codeErreur;

  @override
  void dispose() {
    _matriculeCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dateNaissance ?? DateTime(maintenant.year - 12),
      firstDate: DateTime(maintenant.year - 100),
      lastDate: maintenant,
      helpText: 'Date de naissance de l’élève',
    );
    if (date != null) setState(() => _dateNaissance = date);
  }

  Future<void> _valider() async {
    final date = _dateNaissance;
    if (date == null || _matriculeCtrl.text.trim().isEmpty) return;

    setState(() {
      _enCours = true;
      _codeErreur = null;
    });

    try {
      await ref.read(authRepositoryProvider).lierFiche(
            matricule: _matriculeCtrl.text,
            dateNaissance: date,
          );
      if (!mounted) return;
      ref.rafraichirSession();
    } on ErreurAuth catch (e) {
      if (!mounted) return;
      setState(() => _codeErreur = e.code);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = _dateNaissance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rattacher ma scolarité'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.deconnecterEtPurgerDonneesLocales(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Votre matricule',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Saisissez le matricule remis par votre établissement et la '
                  'date de naissance figurant sur votre fiche.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _matriculeCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Matricule',
                    hintText: 'ex. LIC-2026-0148',
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _enCours ? null : _choisirDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    date == null
                        ? 'Choisir la date de naissance'
                        : '${date.day.toString().padLeft(2, '0')}/'
                            '${date.month.toString().padLeft(2, '0')}/'
                            '${date.year}',
                  ),
                ),
                const SizedBox(height: 24),
                if (_codeErreur != null) ...[
                  Text(
                    messageErreurAuth(_codeErreur!),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  onPressed: _enCours || date == null ? null : _valider,
                  child: _enCours
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Rattacher'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
