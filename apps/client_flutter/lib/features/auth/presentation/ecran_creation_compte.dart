import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_providers.dart';
import '../application/connexion_controller.dart';
import '../application/inscription_providers.dart';
import '../domain/inscription_en_cours.dart';
import 'bouton_google.dart';
import 'ecran_connexion.dart';

/// « Créer un compte » (REG-18, partie B), avant la vérification :
///
/// 1. **espace** : élève, parent (aussi client de la boutique), ou
///    représentant d'un établissement ;
/// 2. **nom et prénoms** — ou « Continuer avec Google », qui les fournit
///    (confirmés après) ;
/// 3. **vérification de l'adresse** (code par e-mail ou Google) : le compte
///    n'est créé qu'ici.
///
/// Les saisies restent sur le téléphone ([inscriptionEnCoursProvider]) ;
/// elles sont appliquées après la vérification, jamais à un compte existant.
/// La suite (téléphone, code secret, récapitulatif) est menée par la garde de
/// session.
class EcranCreationCompte extends ConsumerStatefulWidget {
  const EcranCreationCompte({super.key, required this.surRetour});

  final VoidCallback surRetour;

  @override
  ConsumerState<EcranCreationCompte> createState() => _EcranCreationCompteState();
}

enum _Etape { espace, nom, verification }

class _EcranCreationCompteState extends ConsumerState<EcranCreationCompte> {
  _Etape _etape = _Etape.espace;
  EspaceInscription? _espace;
  final _prenom = TextEditingController();
  final _nom = TextEditingController();
  final _formulaire = GlobalKey<FormState>();

  @override
  void dispose() {
    _prenom.dispose();
    _nom.dispose();
    super.dispose();
  }

  void _retour() {
    switch (_etape) {
      case _Etape.espace:
        widget.surRetour();
      case _Etape.nom:
        setState(() => _etape = _Etape.espace);
      case _Etape.verification:
        ref.read(connexionControllerProvider.notifier).recommencer();
        setState(() => _etape = _Etape.nom);
    }
  }

  Future<void> _enregistrer() => ref.read(inscriptionEnCoursProvider.notifier).enregistrer(
        espace: _espace!,
        prenom: _prenom.text.trim().isEmpty ? null : _prenom.text,
        nom: _nom.text.trim().isEmpty ? null : _nom.text,
      );

  Future<void> _suivant() async {
    if (!(_formulaire.currentState?.validate() ?? false)) return;
    await _enregistrer();
    if (mounted) setState(() => _etape = _Etape.verification);
  }

  /// Google fournit le nom : saisie facultative, confirmée après.
  Future<void> _google() async {
    await _enregistrer();
    await ref.read(connexionControllerProvider.notifier).connecterAvecGoogle();
  }

  @override
  Widget build(BuildContext context) {
    if (_etape == _Etape.verification) {
      return EcranConnexion(creationCompte: true, surRetour: _retour);
    }

    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (aQuitte, _) {
        if (!aQuitte) _retour();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(key: const Key('retour_creation'), onPressed: _retour),
          title: Text('Créer un compte · ${_etape == _Etape.espace ? 1 : 2}/3'),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _etape == _Etape.espace ? _choixEspace(theme) : _saisieNom(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _choixEspace(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Vous êtes…', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        ChoixEspaceInscription(
          valeur: _espace,
          surChoix: (e) => setState(() {
            _espace = e;
            _etape = _Etape.nom;
          }),
        ),
        const SizedBox(height: 16),
        Text(
          'Personnel d’une école ou vendeur : votre compte est ouvert pour vous, '
          'revenez en arrière et choisissez « Se connecter ».',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _saisieNom(ThemeData theme) {
    final etat = ref.watch(connexionControllerProvider);
    final google = ref.watch(connexionGoogleProvider).disponible;
    return Form(
      key: _formulaire,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _espace == EspaceInscription.etablissement ? 'Vos nom et prénoms' : 'Votre nom et vos prénoms',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text('Tels qu’ils figurent à l’école.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          TextFormField(
            key: const Key('champ_prenom'),
            controller: _prenom,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.givenName],
            decoration: const InputDecoration(labelText: 'Prénom(s)'),
            validator: verifierNom,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('champ_nom'),
            controller: _nom,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.familyName],
            decoration: const InputDecoration(labelText: 'Nom'),
            validator: verifierNom,
            onFieldSubmitted: (_) => _suivant(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('bouton_suivant_nom'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _suivant,
            child: const Text('Suivant'),
          ),
          if (google) ...[
            const SizedBox(height: 20),
            Text('ou, sans rien saisir :', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            BoutonGoogle(
              key: const Key('bouton_google_creation'),
              enCours: etat.enCours || etat.connecte,
              onPressed: _google,
            ),
          ],
          if (etat.codeErreur != null) ...[
            const SizedBox(height: 16),
            Text(messageErreurAuth(etat.codeErreur!), style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

/// Choix de l'espace, partagé par « Créer un compte » et la fin de
/// l'inscription après la connexion.
class ChoixEspaceInscription extends StatelessWidget {
  const ChoixEspaceInscription({super.key, required this.valeur, required this.surChoix});

  final EspaceInscription? valeur;
  final ValueChanged<EspaceInscription> surChoix;

  static String libelle(EspaceInscription e) => switch (e) {
        EspaceInscription.eleve => 'Élève',
        EspaceInscription.parent => 'Parent',
        EspaceInscription.etablissement => 'Je représente un établissement',
      };

  static String description(EspaceInscription e) => switch (e) {
        EspaceInscription.eleve => 'Ma scolarité, mes notes et la révision.',
        EspaceInscription.parent =>
          'Suivre mes enfants et régler leurs frais. Aussi pour acheter sur la boutique, sans enfant inscrit.',
        EspaceInscription.etablissement =>
          'Direction ou fondateur d’une école, ou d’un réseau d’écoles. Demande d’ouverture validée par Global Service Groupe.',
      };

  static IconData icone(EspaceInscription e) => switch (e) {
        EspaceInscription.eleve => Icons.backpack_outlined,
        EspaceInscription.parent => Icons.family_restroom_outlined,
        EspaceInscription.etablissement => Icons.apartment_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final e in EspaceInscription.values)
          Card(
            key: Key('espace_${e.code}'),
            margin: const EdgeInsets.only(bottom: 12),
            shape: valeur == e
                ? RoundedRectangleBorder(
                    side: BorderSide(color: theme.colorScheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: ListTile(
              leading: Icon(icone(e), color: theme.colorScheme.primary),
              title: Text(libelle(e), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(description(e)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => surChoix(e),
            ),
          ),
      ],
    );
  }
}
