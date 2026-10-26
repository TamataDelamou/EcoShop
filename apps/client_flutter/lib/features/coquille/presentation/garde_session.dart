import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../auth/domain/destination_session.dart';
import '../../auth/presentation/ecran_choix_espace.dart';
import '../../auth/presentation/ecran_choix_role.dart';
import '../../auth/presentation/ecran_liaison_fiche.dart';
import '../../auth/presentation/ecran_telephone_profil.dart';
import '../../cgu/presentation/ecran_cgu.dart';
import '../../etablissement/presentation/ecran_selection_etablissement.dart';
import '../../regionalisation/presentation/ecran_onboarding_regionalisation.dart';
import '../application/session_logout.dart';
import 'coquille_app.dart';
import 'ecran_creation_code.dart';
import '../../invitations/presentation/ecran_invitations.dart';
import '../../auth/presentation/ecran_nom_profil.dart';
import '../../auth/presentation/ecran_recapitulatif.dart';
import '../../auth/application/relance_reseau.dart';
import '../../auth/application/session_locale.dart';
import '../../appareil/application/appareil_providers.dart';
import '../../appareil/presentation/ecran_code_compte.dart';
import '../../../core/securite/surveillance_session.dart';

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
    // Relecture au retour du réseau, sans relancer l'application (REG-18).
    ref.watch(relanceReseauProvider);

    // Refus du serveur pour toute la session (REG-22).
    ref.listen(refusSessionProvider, (_, refus) {
      switch (refus.valueOrNull) {
        case RefusSession.sessionRevoquee:
          ref.read(appareilControllerProvider).sessionRevoquee();
        case RefusSession.appareilAVerifier:
          ref.invalidate(etatAppareilProvider);
        case null:
          break;
      }
    });
    // Appareil tout juste vérifié (code, autre appareil, récupération,
    // école) : les lectures refusées jusque-là sont relancées.
    ref.listen(etatAppareilProvider.select((e) => e.valueOrNull?.aVerifier), (avant, maintenant) {
      if (avant == true && maintenant == false) ref.rafraichirSession();
    });

    return switch (destination) {
      DestinationSession.chargement => const _EcranChargement(),
      DestinationSession.horsLigneSansCopie => const _EcranSansConnexion(),
      DestinationSession.connexion => const EcranChoixEspace(),
      DestinationSession.codeCompte => const EcranCodeCompte(),
      DestinationSession.codeCompteAConfirmer => const EcranCodeCompteAConfirmer(),
      DestinationSession.compteBloque => const _EcranCompteBloque(),
      DestinationSession.invitations => const EcranInvitations(),
      DestinationSession.choixRole => const EcranChoixRole(),
      DestinationSession.nomACompleter => const EcranNomProfil(),
      DestinationSession.liaisonFiche => const EcranLiaisonFiche(),
      DestinationSession.selectionEtablissement =>
        const EcranSelectionEtablissement(),
      DestinationSession.cguNonAcceptees => const EcranCgu(),
      DestinationSession.telephoneProfil => const EcranTelephoneProfil(),
      DestinationSession.codeSecret => const EcranCreationCode(),
      DestinationSession.recapitulatif => const EcranRecapitulatif(),
      DestinationSession.regionalisation =>
        const EcranOnboardingRegionalisation(),
      DestinationSession.accueil => const CoquilleApp(),
    };
  }
}

/// Ouverture en cours : jamais un chargement sans message. Les lectures ont
/// un délai maximum ([delaiLectureServeurProvider]) ; au-delà, l'écran
/// « Pas de connexion » prend le relais.
class _EcranChargement extends StatelessWidget {
  const _EcranChargement();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                'Ouverture de votre espace…',
                key: const Key('message_chargement'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aucune connexion et rien de gardé sur ce téléphone pour ce compte
/// (première ouverture sans réseau). L'application s'ouvre seule au retour
/// du réseau ; « Réessayer » relance tout de suite.
class _EcranSansConnexion extends ConsumerWidget {
  const _EcranSansConnexion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            key: const Key('ecran_sans_connexion'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 56),
              const SizedBox(height: 16),
              Text(
                'Pas de connexion. Vos informations s’afficheront dès le retour du réseau.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('bouton_reessayer_connexion'),
                onPressed: () {
                  ref.read(donneesSessionPerimeesProvider.notifier).state = false;
                  ref.rafraichirSession();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
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
