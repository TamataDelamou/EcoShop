import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/connexion_controller.dart';
import '../application/inscription_providers.dart';
import 'ecran_connexion.dart';
import 'ecran_creation_compte.dart';

/// Accueil avant la connexion (REG-18, partie B) : « Se connecter » ou
/// « Créer un compte ».
///
/// Remplace les cinq cartes d'orientation (Marketplace, Établissement,
/// Enseignant, Parent/Élève, Administration), qui menaient toutes au même
/// écran de connexion. Chaque profil garde un chemin :
/// - élève, parent, client de la boutique : « Créer un compte » ;
/// - représentant d'un établissement ou d'un réseau : « Créer un compte »,
///   « Je représente un établissement » ;
/// - personnel, vendeur, administration : comptes ouverts par invitation ou
///   par GSG, « Se connecter » avec l'adresse fournie.
///
/// Les écrans se remplacent ici sans navigation empilée : dès que la session
/// s'ouvre, la garde de session prend la main sans page restée par-dessus.
class EcranChoixEspace extends ConsumerStatefulWidget {
  const EcranChoixEspace({super.key});

  @override
  ConsumerState<EcranChoixEspace> createState() => _EcranChoixEspaceState();
}

enum _Vue { accueil, connexion, creation }

class _EcranChoixEspaceState extends ConsumerState<EcranChoixEspace> {
  _Vue _vue = _Vue.accueil;

  void _aller(_Vue vue) {
    // Repartir d'un parcours de connexion vierge.
    ref.read(connexionControllerProvider.notifier).recommencer();
    setState(() => _vue = vue);
  }

  Future<void> _seConnecter() async {
    // « Se connecter » : une saisie de « Créer un compte » restée sur le
    // téléphone ne s'appliquera pas au compte qui va s'ouvrir.
    await ref.read(inscriptionEnCoursProvider.notifier).effacer();
    _aller(_Vue.connexion);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_vue) {
      _Vue.connexion => EcranConnexion(surRetour: () => _aller(_Vue.accueil)),
      _Vue.creation => EcranCreationCompte(surRetour: () => _aller(_Vue.accueil)),
      _Vue.accueil => _Accueil(
          surSeConnecter: _seConnecter,
          surCreerCompte: () => _aller(_Vue.creation),
        ),
    };
  }
}

class _Accueil extends StatelessWidget {
  const _Accueil({required this.surSeConnecter, required this.surCreerCompte});

  final VoidCallback surSeConnecter;
  final VoidCallback surCreerCompte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.school_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('EcoShop', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'La scolarité, la révision et la boutique de votre école.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  FilledButton(
                    key: const Key('bouton_se_connecter'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: surSeConnecter,
                    child: const Text('Se connecter'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('bouton_creer_compte'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: surCreerCompte,
                    child: const Text('Créer un compte'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Personnel d’une école ou vendeur : votre compte est ouvert pour vous. '
                    'Choisissez « Se connecter » avec l’adresse que vous avez donnée.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
