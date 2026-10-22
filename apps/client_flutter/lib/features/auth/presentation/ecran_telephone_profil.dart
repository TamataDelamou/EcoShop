import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/e164_validator.dart';
import '../application/connexion_controller.dart' show messageErreurAuth;
import '../application/telephone_profil_providers.dart';
import '../domain/auth_repository.dart';
import '../domain/telephone_profil.dart';

/// Étape « Votre numéro » après la première connexion (REG-16), et écran de
/// modification depuis « Mon profil » ([modification] vrai).
class EcranTelephoneProfil extends ConsumerStatefulWidget {
  const EcranTelephoneProfil({super.key, this.modification = false, this.actuel});

  final bool modification;
  final TelephoneProfil? actuel;

  @override
  ConsumerState<EcranTelephoneProfil> createState() => _EcranTelephoneProfilState();
}

class _EcranTelephoneProfilState extends ConsumerState<EcranTelephoneProfil> {
  final _indicatif = TextEditingController(text: '+224');
  final _numero = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final actuel = widget.actuel?.numero;
    if (actuel != null && actuel.startsWith('+224')) _numero.text = actuel.substring(4);
  }

  @override
  void dispose() {
    _indicatif.dispose();
    _numero.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final tel = Validators.normalizeE164(indicatifPays: _indicatif.text, numeroLocal: _numero.text);
    if (tel == null) {
      setState(() => _erreur = 'TELEPHONE_INVALIDE');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final r = await ref.read(etapeTelephoneProvider.notifier).enregistrer(tel);
      if (!mounted) return;
      if (widget.modification) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.enAttenteEnvoi
              ? 'Numéro gardé : il sera envoyé au retour de la connexion.'
              : 'Numéro enregistré. Faites-le confirmer à l’école lors de votre prochain passage.'),
        ));
        Navigator.of(context).pop();
      }
    } on ErreurAuth catch (e) {
      if (mounted) setState(() => _erreur = e.code);
    } catch (_) {
      if (mounted) setState(() => _erreur = 'ERREUR_INATTENDUE');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contenu = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.phone_iphone, size: 48),
        const SizedBox(height: 16),
        Text(
          widget.modification ? 'Changer de numéro' : 'Votre numéro de téléphone',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'L’école s’en sert pour vous joindre : absence, paiement, urgence. '
          'Il n’est jamais montré aux autres familles.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: TextField(
                controller: _indicatif,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Indicatif'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('champ_telephone_profil'),
                controller: _numero,
                autofocus: true,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                decoration: const InputDecoration(labelText: 'Numéro', hintText: '620 00 00 00'),
                onSubmitted: _enCours ? null : (_) => _enregistrer(),
              ),
            ),
          ],
        ),
        if (_erreur != null) ...[
          const SizedBox(height: 12),
          Text(messageErreurAuth(_erreur!), style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('bouton_enregistrer_telephone'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _enCours ? null : _enregistrer,
          child: _enCours
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
        if (!widget.modification) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const Key('bouton_plus_tard'),
            onPressed: _enCours ? null : () => ref.read(etapeTelephoneProvider.notifier).passer(),
            child: const Text('Plus tard'),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Votre numéro sera confirmé par l’école lors de votre prochain passage : '
          'aucun SMS ne vous est envoyé.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );

    return Scaffold(
      appBar: widget.modification ? AppBar(title: const Text('Téléphone')) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: contenu),
          ),
        ),
      ),
    );
  }
}
