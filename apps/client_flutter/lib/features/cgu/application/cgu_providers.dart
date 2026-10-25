import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/session_locale.dart';
import '../../auth/domain/profil.dart';
import '../data/supabase_cgu_repository.dart';
import '../domain/cgu_repository.dart';
import '../domain/cgu_statut.dart';

final cguRepositoryProvider = Provider<CguRepository>((ref) {
  return SupabaseCguRepository(ref.watch(supabaseClientProvider));
});

/// Statut CGU du compte connecté — le serveur fait foi (l'acceptation doit
/// survivre une réinstallation, contrairement à
/// `onboardingRegionalisationVuProvider`, une simple préférence d'ergonomie).
/// La dernière réponse est gardée sur le téléphone pour ouvrir l'application
/// sans réseau (REG-18) ; elle n'est jamais une acceptation inventée.
final cguStatutProvider =
    AsyncNotifierProvider<CguStatutNotifier, CguStatut?>(CguStatutNotifier.new);

class CguStatutNotifier extends AsyncNotifier<CguStatut?> {
  @override
  Future<CguStatut?> build() async {
    final repo = ref.watch(cguRepositoryProvider);
    Profil? profil;
    try {
      profil = await ref.watch(profilProvider.future);
    } catch (e) {
      // Profil illisible faute de réseau : le statut ne le sera pas non
      // plus, inutile d'attendre le serveur (« Pas de connexion »).
      if (estErreurReseau(e)) rethrow;
      // Autre refus : pas de copie possible, le serveur seul.
    }
    if (profil == null) {
      if (!ref.read(estEnLigneProvider)) throw const HorsConnexion();
      return repo.statut().timeout(ref.read(delaiLectureServeurProvider));
    }
    return lireAvecCopieLocale<CguStatut?>(
      ref,
      type: 'cgu',
      compteId: profil.id,
      serveur: repo.statut,
      versJson: (s) => s?.versJson(),
      depuisJson: (j) => j == null ? null : CguStatut.depuisJson((j as Map).cast<String, dynamic>()),
    );
  }

  Future<void> accepter() async {
    final statut = state.valueOrNull;
    if (statut == null) return;
    await ref.read(cguRepositoryProvider).accepter(statut.cguVersionId);
    final acceptee = statut.copierAvecAcceptee(true);
    state = AsyncData(acceptee);
    final profilId = ref.read(profilProvider).valueOrNull?.id;
    if (profilId != null) {
      await ecrireCopieLocale(ref, type: 'cgu', compteId: profilId, json: acceptee.versJson());
    }
  }
}

extension on CguStatut {
  CguStatut copierAvecAcceptee(bool acceptee) => CguStatut(
        cguVersionId: cguVersionId,
        parcours: parcours,
        numeroVersion: numeroVersion,
        contenu: contenu,
        publieeLe: publieeLe,
        acceptee: acceptee,
      );
}
