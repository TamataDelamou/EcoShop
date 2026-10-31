import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../appareil/application/appareil_providers.dart';
import '../../cgu/application/cgu_providers.dart';
import '../../coquille/application/verrou_controller.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../invitations/application/invitations_providers.dart';
import '../../regionalisation/application/regionalisation_providers.dart';
import '../data/connexion_google.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';
import '../domain/destination_session.dart';
import '../domain/profil.dart';
import 'inscription_providers.dart';
import 'session_locale.dart';
import 'telephone_profil_providers.dart';

/// Port d'authentification. Surchargé par un double en test — aucun test ne
/// touche le réseau.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

/// Compte Google du téléphone (REG-16). Surchargé par un double en test.
final connexionGoogleProvider = Provider<ConnexionGoogle>((ref) => ConnexionGooglePlugin());

/// Vrai si une session est ouverte. Recalculé à chaque événement Auth.
final sessionOuverteProvider = Provider<bool>((ref) {
  // On dépend du flux d'événements pour être invalidé à la connexion et à la
  // déconnexion ; la valeur elle-même est lue sur le client (source de vérité
  // locale de la session, restaurée au démarrage).
  ref.watch(authStateProvider);
  return ref.watch(sessionProvider) != null;
});

/// Compte de la session ouverte (identifiant Supabase), ou null s'il n'est
/// pas lisible (tests qui figent la session).
String? _compteSession(Ref ref) {
  try {
    return ref.watch(sessionProvider.select((s) => s?.user.id));
  } catch (_) {
    return null;
  }
}

/// Profil du compte connecté. Copie locale affichée tout de suite à
/// l'ouverture, même sans réseau ; serveur relu en arrière-plan
/// (`session_locale.dart`).
final profilProvider = FutureProvider<Profil?>((ref) async {
  if (!ref.watch(sessionOuverteProvider)) return null;
  final repo = ref.watch(authRepositoryProvider);
  final compte = _compteSession(ref);
  if (compte == null) return repo.profilCourant();
  return lireAvecCopieLocale<Profil?>(
    ref,
    type: 'profil',
    compteId: compte,
    serveur: repo.profilCourant,
    versJson: (p) => p?.versJson(),
    depuisJson: (j) => j == null ? null : Profil.depuisJson((j as Map).cast<String, dynamic>()),
  );
});

/// Fiche élève revendiquée ?
final ficheLieeProvider = FutureProvider<bool>((ref) async {
  final profil = await ref.watch(profilProvider.future);
  // Seul l'élève a une fiche à revendiquer : on évite une requête inutile
  // pour tous les autres rôles.
  if (profil == null || !profil.exigeLiaisonFiche) return true;
  final repo = ref.watch(authRepositoryProvider);
  return lireAvecCopieLocale<bool>(
    ref,
    type: 'fiche_liee',
    compteId: profil.id,
    serveur: repo.ficheLiee,
    versJson: (v) => v,
    depuisJson: (j) => j == true,
  );
});

/// Établissements dont le compte est membre actif (copie locale comme le
/// profil).
final mesEtablissementsProvider = FutureProvider<List<Etablissement>>((ref) async {
  if (!ref.watch(sessionOuverteProvider)) return const [];
  final repo = ref.watch(authRepositoryProvider);
  final compte = _compteSession(ref);
  if (compte == null) return repo.mesEtablissements();
  return lireAvecCopieLocale<List<Etablissement>>(
    ref,
    type: 'etablissements',
    compteId: compte,
    serveur: repo.mesEtablissements,
    versJson: (l) => [for (final e in l) e.versJson()],
    depuisJson: (j) => [
      for (final e in (j as List? ?? const [])) Etablissement.depuisJson((e as Map).cast<String, dynamic>()),
    ],
  );
});

/// Établissement actif résolu, ou null.
final etablissementActifProvider = Provider<Etablissement?>((ref) {
  final profil = ref.watch(profilProvider).valueOrNull;
  final etablissements = ref.watch(mesEtablissementsProvider).valueOrNull ?? const [];
  if (profil?.etablissementActifId == null) {
    // Rattachement unique : il est implicitement actif, l'écran de sélection
    // n'a pas lieu d'être (cohérent avec GardeSession).
    return etablissements.length == 1 ? etablissements.first : null;
  }
  for (final e in etablissements) {
    if (e.id == profil!.etablissementActifId) return e;
  }
  return null;
});

/// Destination courante de la garde de session.
final destinationProvider = Provider<DestinationSession>((ref) {
  final sessionOuverte = ref.watch(sessionOuverteProvider);
  if (!sessionOuverte) return DestinationSession.connexion;

  // Code du compte (REG-22) : avant tout le reste sur un nouvel appareil.
  final appareil = ref.watch(etatAppareilProvider);
  if (appareil.isLoading && !appareil.hasValue) return DestinationSession.chargement;
  if (appareil.valueOrNull?.aVerifier ?? false) return DestinationSession.codeCompte;
  final codeCompteAConfirmer = ref.watch(codeCompteAConfirmerProvider).valueOrNull ?? false;

  final profil = ref.watch(profilProvider);
  final fiche = ref.watch(ficheLieeProvider);
  final etablissements = ref.watch(mesEtablissementsProvider);
  final cguStatut = ref.watch(cguStatutProvider);
  final regionalisationVue = ref.watch(onboardingRegionalisationVuProvider);
  final etapeTelephone = ref.watch(etapeTelephoneProvider);
  final verrou = ref.watch(verrouControllerProvider.select((e) => e.phase));
  final recapitulatif = ref.watch(recapitulatifAMontrerProvider);
  final invitations = ref.watch(invitationsAPresenterProvider);

  // Tant qu'une de ces lectures n'a encore jamais abouti, on n'oriente pas :
  // afficher l'écran de connexion pendant le chargement ferait clignoter le
  // parcours. Une **relecture** (relance toutes les 30 s sur un réseau lent,
  // retour du réseau, rafraîchissement) garde la valeur connue : l'accueil
  // n'est plus démonté puis remonté — il remontait en haut de la page à
  // chaque relance (retour du porteur de projet, 2026-10-28).
  bool premierChargement(AsyncValue<Object?> v) => v.isLoading && !v.hasValue && !v.hasError;
  // Lecture impossible (sans réseau, et rien de gardé sur le téléphone) : on
  // ne devine pas (fiche non liée, CGU acceptées…), on le dit. La relance
  // au retour du réseau relit tout (`relance_reseau.dart`).
  bool inconnu(AsyncValue<Object?> v) => v.hasError && !v.hasValue;

  final compte = profil.valueOrNull?.id;
  final memoire = ref.read(_derniereDestinationProvider);
  // Accueil déjà atteint pour ce compte depuis le lancement : une relecture
  // en cours ou en échec (réseau coupé, serveur muet) ne le retire plus.
  // Le compte reste orienté par le serveur dès qu'une réponse arrive.
  // Hors connexion, un compte qui a déjà atteint l'accueil sur ce téléphone
  // n'est plus arrêté sur « Pas de connexion » parce qu'une lecture n'a pas
  // de copie : l'accueil s'ouvre avec ce qui est gardé, et la relance au
  // retour du réseau complète (retour du porteur de projet, 2026-10-31).
  final dejaAtteint = ref.watch(accueilDejaAtteintProvider).valueOrNull ?? false;
  bool garderAccueil() => memoire.compte != null && memoire.compte == compte && memoire.destination == DestinationSession.accueil;

  if (premierChargement(profil) ||
      premierChargement(fiche) ||
      premierChargement(etablissements) ||
      premierChargement(cguStatut) ||
      premierChargement(regionalisationVue) ||
      premierChargement(etapeTelephone) ||
      premierChargement(recapitulatif) ||
      // Compte sans rôle : attendre ses invitations, pour ne pas choisir
      // « Élève » ou « Parent » à la place du rôle prévu par l'école.
      (premierChargement(invitations) && profil.valueOrNull?.roleDefini == false) ||
      verrou == PhaseVerrou.chargement) {
    return garderAccueil() ? DestinationSession.accueil : DestinationSession.chargement;
  }

  if (inconnu(profil) || inconnu(fiche) || inconnu(etablissements) || inconnu(cguStatut)) {
    return garderAccueil() || dejaAtteint ? DestinationSession.accueil : DestinationSession.horsLigneSansCopie;
  }

  final statutCgu = cguStatut.valueOrNull;
  final destination = GardeSession.resoudre(
    sessionOuverte: true,
    profil: profil.valueOrNull,
    ficheLiee: fiche.valueOrNull ?? false,
    nombreEtablissements: etablissements.valueOrNull?.length ?? 0,
    cguAcceptee: statutCgu == null || statutCgu.acceptee,
    regionalisationVue: regionalisationVue.valueOrNull ?? true,
    telephoneAFournir: etapeTelephone.valueOrNull ?? false,
    codeSecretACreer: verrou == PhaseVerrou.codeACreer,
    recapitulatifAMontrer: recapitulatif.valueOrNull ?? false,
    invitationsAPresenter: (invitations.valueOrNull ?? const []).isNotEmpty,
    codeCompteAConfirmer: codeCompteAConfirmer,
  );
  if (destination == DestinationSession.accueil && !dejaAtteint && compte != null) {
    unawaited(marquerAccueilAtteint(ref, compte));
  }
  memoire
    ..compte = compte
    ..destination = destination;
  return destination;
});

/// Dernière destination calculée (et son compte) : voir [destinationProvider].
class _MemoireDestination {
  String? compte;
  DestinationSession? destination;
}

final _derniereDestinationProvider = Provider<_MemoireDestination>((ref) {
  // Remise à zéro à l'ouverture et à la fermeture de session.
  ref.watch(sessionOuverteProvider);
  return _MemoireDestination();
});

/// Invalide l'ensemble des lectures dépendant du compte.
///
/// Appelée après chaque action qui modifie l'état serveur du compte (choix de
/// rôle, liaison de fiche, sélection d'établissement) : c'est le serveur qui
/// vient d'être modifié, on relit plutôt que de recopier localement.
///
/// Deux extensions plutôt qu'une fonction : `Ref` (providers) et `WidgetRef`
/// (widgets) n'ont pas de supertype commun en Riverpod 2, mais les appelants
/// écrivent la même chose des deux côtés.
void _invaliderSession(void Function(ProviderOrFamily) invalider) {
  invalider(profilProvider);
  invalider(ficheLieeProvider);
  invalider(mesEtablissementsProvider);
  // Le statut CGU ne dépend que du compte : relu pour le compte qui vient
  // d'ouvrir sa session, jamais hérité du précédent.
  invalider(cguStatutProvider);
}

extension RafraichirSessionRef on Ref {
  void rafraichirSession() => _invaliderSession(invalidate);
}

extension RafraichirSessionWidgetRef on WidgetRef {
  void rafraichirSession() => _invaliderSession(invalidate);
}
