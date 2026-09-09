import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../auth/domain/destination_session.dart';
import '../../auth/presentation/ecran_choix_espace.dart';
import '../../auth/presentation/ecran_choix_role.dart';
import '../../auth/presentation/ecran_liaison_fiche.dart';
import '../../etablissement/presentation/ecran_selection_etablissement.dart';
import '../application/session_logout.dart';
import 'coquille_app.dart';

/// Racine de l'application : affiche l'écran correspondant à la destination
/// calculée par [GardeSession].
///
/// L'orientation est déclarative — l'arbre est reconstruit quand l'état du
/// compte change — plutôt qu'impérative (pousser/dépiler des routes), ce qui
/// évite qu'une session expirée laisse un écran authentifié affiché.
class RacineApp extends ConsumerWidget {
  const RacineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = ref.watch(destinationProvider);

    return switch (destination) {
      DestinationSession.chargement => const _EcranChargement(),
      DestinationSession.connexion => const EcranChoixEspace(),
      DestinationSession.compteBloque => const _EcranCompteBloque(),
      DestinationSession.choixRole => const EcranChoixRole(),
      DestinationSession.liaisonFiche => const EcranLiaisonFiche(),
      DestinationSession.selectionEtablissement =>
        const EcranSelectionEtablissement(),
      DestinationSession.accueil => const CoquilleApp(),
    };
  }
}

class _EcranChargement extends StatelessWidget {
  const _EcranChargement();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// Compte suspendu ou supprimé : la seule action possible est la déconnexion.
class _EcranCompteBloque extends ConsumerWidget {
  const _EcranCompteBloque();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 16),
              Text(
                'Compte indisponible',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Votre compte est suspendu. Rapprochez-vous de votre '
                'établissement ou du support GSG.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => ref.deconnecterEtPurgerDonneesLocales(),
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
