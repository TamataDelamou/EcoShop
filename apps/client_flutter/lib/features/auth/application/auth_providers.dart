import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../etablissement/domain/etablissement.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';
import '../domain/destination_session.dart';
import '../domain/profil.dart';

/// Port d'authentification. Surchargé par un double en test — aucun test ne
/// touche le réseau.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

/// Vrai si une session est ouverte. Recalculé à chaque événement Auth.
final sessionOuverteProvider = Provider<bool>((ref) {
  // On dépend du flux d'événements pour être invalidé à la connexion et à la
  // déconnexion ; la valeur elle-même est lue sur le client (source de vérité
  // locale de la session, restaurée au démarrage).
  ref.watch(authStateProvider);
  return ref.watch(sessionProvider) != null;
});

/// Profil du compte connecté.
final profilProvider = FutureProvider<Profil?>((ref) async {
  if (!ref.watch(sessionOuverteProvider)) return null;
  return ref.watch(authRepositoryProvider).profilCourant();
});

/// Fiche élève revendiquée ?
final ficheLieeProvider = FutureProvider<bool>((ref) async {
  final profil = await ref.watch(profilProvider.future);
  // Seul l'élève a une fiche à revendiquer : on évite une requête inutile
  // pour tous les autres rôles.
  if (profil == null || !profil.exigeLiaisonFiche) return true;
  return ref.watch(authRepositoryProvider).ficheLiee();
});

/// Établissements dont le compte est membre actif.
final mesEtablissementsProvider = FutureProvider<List<Etablissement>>((ref) async {
  if (!ref.watch(sessionOuverteProvider)) return const [];
  return ref.watch(authRepositoryProvider).mesEtablissements();
});

/// Établissement actif résolu, ou null.
final etablissementActifProvider = Provider<Etablissement?>((ref) {
  final profil = ref.watch(profilProvider).value;
  final etablissements = ref.watch(mesEtablissementsProvider).value ?? const [];
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

  final profil = ref.watch(profilProvider);
  final fiche = ref.watch(ficheLieeProvider);
  final etablissements = ref.watch(mesEtablissementsProvider);

  // Tant qu'une des trois lectures est en cours, on n'oriente pas : afficher
  // l'écran de connexion pendant le chargement ferait clignoter le parcours.
  if (profil.isLoading || fiche.isLoading || etablissements.isLoading) {
    return DestinationSession.chargement;
  }

  return GardeSession.resoudre(
    sessionOuverte: true,
    profil: profil.value,
    ficheLiee: fiche.value ?? false,
    nombreEtablissements: etablissements.value?.length ?? 0,
  );
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
}

extension RafraichirSessionRef on Ref {
  void rafraichirSession() => _invaliderSession(invalidate);
}

extension RafraichirSessionWidgetRef on WidgetRef {
  void rafraichirSession() => _invaliderSession(invalidate);
}
