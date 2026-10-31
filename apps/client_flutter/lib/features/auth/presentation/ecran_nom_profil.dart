import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_providers.dart';
import '../application/connexion_controller.dart';
import '../application/inscription_providers.dart';
import '../domain/auth_repository.dart';
import '../domain/inscription_en_cours.dart';

/// Nom et prénoms, une fois, pour un compte ouvert par invitation (personnel
/// d'une école) qui ne les a pas encore donnés (REG-18, partie B : « mêmes
/// étapes 2 à 6 » que l'inscription, sans choix d'espace). Pré-remplis
/// depuis Google quand c'est possible.
class EcranNomProfil extends ConsumerStatefulWidget {
  const EcranNomProfil({super.key, this.modification = false});

  /// Depuis « Mes informations » : changer son nom à tout moment (REG-39).
  /// L'écran se referme une fois le nom enregistré.
  final bool modification;

  @override
  ConsumerState<EcranNomProfil> createState() => _EcranNomProfilState();
}

class _EcranNomProfilState extends ConsumerState<EcranNomProfil> {
  final _prenom = TextEditingController();
  final _nom = TextEditingController();
  final _formulaire = GlobalKey<FormState>();
  bool _enCours = false;
  String? _codeErreur;

  @override
  void initState() {
    super.initState();
    final profil = ref.read(profilProvider).valueOrNull;
    final google = ref.read(nomsGoogleProvider);
    _prenom.text = (profil?.prenom ?? '').trim().isNotEmpty ? profil!.prenom! : (google.prenom ?? '');
    _nom.text = (profil?.nom ?? '').trim().isNotEmpty ? profil!.nom! : (google.nom ?? '');
  }

  @override
  void dispose() {
    _prenom.dispose();
    _nom.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (!(_formulaire.currentState?.validate() ?? false)) return;
    setState(() {
      _enCours = true;
      _codeErreur = null;
    });
    try {
      await ref.read(authRepositoryProvider).definirMonNom(prenom: _prenom.text.trim(), nom: _nom.text.trim());
      ref.rafraichirSession();
      if (widget.modification && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nom enregistré.')));
        Navigator.of(context).pop(true);
      }
    } on ErreurAuth catch (e) {
      if (mounted) setState(() => _codeErreur = e.code);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.modification ? 'Modifier mon nom' : 'Votre nom')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formulaire,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Comment vous appelez-vous ?', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text('Tels qu’ils figurent à l’école.', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const Key('champ_prenom'),
                      controller: _prenom,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Prénom(s)'),
                      validator: verifierNom,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('champ_nom'),
                      controller: _nom,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nom'),
                      validator: verifierNom,
                      onFieldSubmitted: (_) => _valider(),
                    ),
                    if (_codeErreur != null) ...[
                      const SizedBox(height: 12),
                      Text(messageErreurAuth(_codeErreur!), style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('bouton_valider_nom'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: _enCours ? null : _valider,
                      child: Text(widget.modification ? 'Enregistrer' : 'Continuer'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
