import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../application/auth_providers.dart';
import '../application/connexion_controller.dart';
import '../domain/auth_repository.dart';

/// Choix du rôle racine à la première connexion (cahier v4.1, ch. 5.2).
///
/// Seuls Élève et Parent sont proposés : ce sont les seuls rôles
/// auto-inscriptibles. Les rôles à privilège passent par invitation ou demande
/// validée — la RPC `choisir_role_racine` refuse tout autre rôle, l'écran ne
/// fait que refléter cette règle.
class EcranChoixRole extends ConsumerStatefulWidget {
  const EcranChoixRole({super.key});

  @override
  ConsumerState<EcranChoixRole> createState() => _EcranChoixRoleState();
}

class _EcranChoixRoleState extends ConsumerState<EcranChoixRole> {
  RoleRacine? _selection;
  bool _enCours = false;
  String? _codeErreur;

  static final List<RoleRacine> _rolesProposes = RoleRacine.values
      .where((r) => r.estAutoInscriptible)
      .toList(growable: false);

  Future<void> _valider() async {
    final role = _selection;
    if (role == null) return;

    setState(() {
      _enCours = true;
      _codeErreur = null;
    });

    try {
      await ref.read(authRepositoryProvider).choisirRole(role);
      if (!mounted) return;
      // Le rôle vient d'être fixé côté serveur : la garde relit le profil.
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
    return Scaffold(
      appBar: AppBar(title: const Text('Votre profil')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Qui êtes-vous ?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Ce choix est définitif. Un compte enseignant, de direction '
                  'ou vendeur s’obtient sur invitation de votre établissement.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                RadioGroup<RoleRacine>(
                  groupValue: _selection,
                  // La sélection est figée pendant l'envoi : RadioGroup exige
                  // un callback non nul, on ignore donc l'événement.
                  onChanged: (valeur) {
                    if (_enCours) return;
                    setState(() => _selection = valeur);
                  },
                  child: Column(
                    children: [
                      for (final role in _rolesProposes)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: RadioListTile<RoleRacine>(
                            value: role,
                            title: Text(_libelle(role)),
                            subtitle: Text(_description(role)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_codeErreur != null) ...[
                  Text(
                    messageErreurAuth(_codeErreur!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _selection == null || _enCours ? null : _valider,
                  child: _enCours
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continuer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _libelle(RoleRacine role) => switch (role) {
        RoleRacine.eleve => 'Élève',
        RoleRacine.parent => 'Parent',
        _ => role.code,
      };

  static String _description(RoleRacine role) => switch (role) {
        RoleRacine.eleve =>
          'Accéder à ma scolarité, mes notes et le moteur de révision.',
        RoleRacine.parent =>
          'Suivre la scolarité de mes enfants et régler leurs frais.',
        _ => '',
      };
}
