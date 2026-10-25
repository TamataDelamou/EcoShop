import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/session_locale.dart';
import '../data/supabase_invitations_repository.dart';
import '../domain/invitation.dart';

final invitationsRepositoryProvider = Provider<InvitationsRepository>((ref) {
  return SupabaseInvitationsRepository(ref.watch(supabaseClientProvider));
});

/// Invitations reçues par le compte connecté. Jamais bloquant : sans réseau
/// (ou serveur indisponible), aucune invitation n'est montrée ; elles
/// reviennent à la prochaine relecture (retour du réseau, nouvelle session).
final mesInvitationsProvider = FutureProvider<List<InvitationRecue>>((ref) async {
  if (!ref.watch(sessionOuverteProvider)) return const [];
  // Relue avec le compte (même invalidation que le profil).
  final compte = ref.watch(profilProvider.select((p) => p.valueOrNull?.id));
  if (compte == null) return const [];
  if (!ref.read(estEnLigneProvider)) return const [];
  try {
    return await ref
        .watch(invitationsRepositoryProvider)
        .mesInvitations()
        .timeout(ref.read(delaiLectureServeurProvider));
  } catch (_) {
    return const [];
  }
});

/// Invitations remises à plus tard pendant cette ouverture de l'application
/// (« Plus tard ») : elles restent dans « Mon profil › Mes invitations ».
final invitationsRemisesProvider = StateProvider<Set<String>>((ref) => <String>{});

/// Invitations à présenter à l'ouverture : celles qui n'ont pas été remises.
final invitationsAPresenterProvider = Provider<AsyncValue<List<InvitationRecue>>>((ref) {
  final remises = ref.watch(invitationsRemisesProvider);
  return ref.watch(mesInvitationsProvider).whenData(
        (liste) => [for (final i in liste) if (!remises.contains(i.id)) i],
      );
});

final invitationsEtablissementProvider =
    FutureProvider.autoDispose.family<List<InvitationEnvoyee>, String>((ref, etablissementId) {
  return ref.watch(invitationsRepositoryProvider).invitationsEtablissement(etablissementId);
});

final postesInvitablesProvider = FutureProvider.autoDispose.family<List<PosteInvitable>, String>((ref, etablissementId) {
  return ref.watch(invitationsRepositoryProvider).postes(etablissementId);
});
