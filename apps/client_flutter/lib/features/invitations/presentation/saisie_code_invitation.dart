import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../application/invitations_providers.dart';
import '../domain/invitation.dart';

/// Saisie du code d'invitation : majuscules, tiret après 4 caractères
/// (« k7q2m9xd » → « K7Q2-M9XD »).
class FormateurCodeInvitation extends TextInputFormatter {
  const FormateurCodeInvitation();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue ancien, TextEditingValue nouveau) {
    var c = nouveau.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (c.length > 8) c = c.substring(0, 8);
    final texte = c.length > 4 ? '${c.substring(0, 4)}-${c.substring(4)}' : c;
    return TextEditingValue(text: texte, selection: TextSelection.collapsed(offset: texte.length));
  }
}

/// Bouton « J'ai un code d'invitation » (REG-27).
class BoutonCodeInvitation extends StatelessWidget {
  const BoutonCodeInvitation({super.key});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: const Key('bouton_code_invitation'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: () => afficherSaisieCodeInvitation(context),
        icon: const Icon(Icons.vpn_key_outlined),
        label: const Text('J’ai un code d’invitation'),
      );
}

/// Code remis par l'école (enseignant, personnel, vendeur) : rattache le
/// compte connecté à l'école, même s'il est déjà parent ou élève.
Future<void> afficherSaisieCodeInvitation(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _DialogueCode(),
    );

class _DialogueCode extends ConsumerStatefulWidget {
  const _DialogueCode();

  @override
  ConsumerState<_DialogueCode> createState() => _DialogueCodeState();
}

class _DialogueCodeState extends ConsumerState<_DialogueCode> {
  final _code = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final brut = _code.text.replaceAll('-', '');
    if (brut.length != 8) {
      setState(() => _erreur = const ErreurInvitations('CODE_INVALIDE').message);
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final r = await ref.read(invitationsRepositoryProvider).accepterParCode(brut);
      ref.invalidate(mesInvitationsProvider);
      // Nouveau rattachement : établissements, rôle et accueil relus.
      ref.rafraichirSession();
      if (!mounted) return;
      final messager = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messager.showSnackBar(SnackBar(
        content: Text('Bienvenue : vous êtes ${libelleRoleInvitation(r.role).toLowerCase()} à ${r.etablissement}.'),
      ));
    } on ErreurInvitations catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Code d’invitation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saisissez le code de 8 caractères que l’école vous a remis.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('champ_code_invitation'),
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: const [FormateurCodeInvitation()],
            style: const TextStyle(fontSize: 22, letterSpacing: 3, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'K7Q2-M9XD',
              errorText: _erreur,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _valider(),
          ),
          const SizedBox(height: 8),
          Text(
            'Votre compte actuel est gardé : un parent devient aussi enseignant, et passe d’un espace à l’autre.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _enCours ? null : () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          key: const Key('valider_code_invitation'),
          onPressed: _enCours ? null : _valider,
          child: _enCours
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Valider'),
        ),
      ],
    );
  }
}
