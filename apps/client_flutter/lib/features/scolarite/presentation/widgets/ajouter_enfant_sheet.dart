import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/scolarite_providers.dart';
import '../../domain/enums_scolarite.dart';
import '../../domain/scolarite_repository.dart';

/// Ouvre la feuille de liaison d'un enfant (RPC `lier_parent_a_fiche`).
Future<void> afficherAjouterEnfant(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _FeuilleAjouterEnfant(),
  );
}

String _messageErreur(String code) => switch (code) {
      'ROLE_PARENT_REQUIS' => 'Seul un compte parent peut lier un enfant.',
      'TROP_DE_TENTATIVES' =>
        'Trop de tentatives : réessayez dans une heure.',
      'LIAISON_IMPOSSIBLE' =>
        'Aucune fiche ne correspond à ce matricule et cette date de naissance.',
      'AUTH_REQUISE' => 'Session expirée : reconnectez-vous.',
      _ => 'Impossible de lier cet enfant pour le moment.',
    };

class _FeuilleAjouterEnfant extends ConsumerStatefulWidget {
  const _FeuilleAjouterEnfant();

  @override
  ConsumerState<_FeuilleAjouterEnfant> createState() => _FeuilleAjouterEnfantState();
}

class _FeuilleAjouterEnfantState extends ConsumerState<_FeuilleAjouterEnfant> {
  final _matriculeCtrl = TextEditingController();
  DateTime? _dateNaissance;
  TypeRelationParentale _type = TypeRelationParentale.parent;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _matriculeCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final choisie = await showDatePicker(
      context: context,
      initialDate: DateTime(maintenant.year - 10),
      firstDate: DateTime(maintenant.year - 30),
      lastDate: maintenant,
      helpText: 'Date de naissance de l\'enfant',
    );
    if (choisie != null) setState(() => _dateNaissance = choisie);
  }

  Future<void> _valider() async {
    final matricule = _matriculeCtrl.text.trim();
    final date = _dateNaissance;
    if (matricule.isEmpty || date == null) {
      setState(() => _erreur = 'Renseignez le matricule et la date de naissance.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      await ref.read(scolariteRepositoryProvider).lierEnfant(
            matricule: matricule,
            dateNaissance: date,
            type: _type,
          );
      if (!mounted) return;
      ref.invalidate(mesEnfantsProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enfant lié avec succès.'),
          backgroundColor: AppColors.vertMenthe,
        ),
      );
    } on ErreurScolarite catch (e) {
      if (!mounted) return;
      setState(() => _erreur = _messageErreur(e.code));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.family_restroom, color: AppColors.bleuElectrique),
                const SizedBox(width: 10),
                Text('Lier un enfant', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Le matricule et la date de naissance sont fournis par '
              "l'établissement de votre enfant.",
              style: TextStyle(color: AppColors.encreSecondaire, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _matriculeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Matricule',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _choisirDate,
              icon: const Icon(Icons.cake_outlined),
              label: Text(
                _dateNaissance == null
                    ? 'Date de naissance'
                    : '${_dateNaissance!.day.toString().padLeft(2, '0')}/'
                        '${_dateNaissance!.month.toString().padLeft(2, '0')}/'
                        '${_dateNaissance!.year}',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TypeRelationParentale>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Votre lien avec l\'enfant',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: TypeRelationParentale.parent, child: Text('Parent')),
                DropdownMenuItem(
                    value: TypeRelationParentale.tuteurLegal, child: Text('Tuteur légal')),
                DropdownMenuItem(value: TypeRelationParentale.autre, child: Text('Autre')),
              ],
              onChanged: (v) => setState(() => _type = v ?? TypeRelationParentale.parent),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: const TextStyle(color: AppColors.erreur)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _enCours ? null : _valider,
              child: _enCours
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Lier cet enfant'),
            ),
          ],
        ),
      ),
    );
  }
}
