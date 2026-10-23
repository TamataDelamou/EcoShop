import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../domain/inscription_en_cours.dart';
import 'auth_providers.dart';

/// Inscription en étapes (REG-18, partie B) : saisies gardées sur le
/// téléphone avant la vérification, récapitulatif après.

final _storeInscriptionProvider = Provider<CacheDocumentStore>(
  (ref) => CacheDocumentStore(ref.watch(databaseProvider), 'preferences'),
);

const _typeInscription = 'inscription_en_cours';
const _typeRecapitulatif = 'recapitulatif_inscription';

/// Heure courante (surchargée en test).
final horlogeInscriptionProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Saisies de « Créer un compte » pas encore appliquées, ou null.
final inscriptionEnCoursProvider =
    AsyncNotifierProvider<InscriptionEnCoursNotifier, InscriptionEnCours?>(InscriptionEnCoursNotifier.new);

class InscriptionEnCoursNotifier extends AsyncNotifier<InscriptionEnCours?> {
  CacheDocumentStore get _store => ref.read(_storeInscriptionProvider);

  @override
  Future<InscriptionEnCours?> build() async {
    try {
      final doc = await ref.watch(_storeInscriptionProvider).lireDocument(_typeInscription, CacheDocumentStore.cleUnique);
      if (doc == null) return null;
      final inscription = InscriptionEnCours.depuisJson(doc);
      return inscription.estValide(ref.read(horlogeInscriptionProvider)()) ? inscription : null;
    } catch (_) {
      // Base locale indisponible : rien de gardé.
      return null;
    }
  }

  Future<void> enregistrer({required EspaceInscription espace, String? prenom, String? nom}) async {
    // Première lecture de la base terminée : elle n'écrasera pas la saisie.
    await future;
    final inscription = InscriptionEnCours(
      espace: espace,
      prenom: prenom?.trim(),
      nom: nom?.trim(),
      creeLe: ref.read(horlogeInscriptionProvider)(),
    );
    state = AsyncData(inscription);
    try {
      await _store.ecrireDocument(_typeInscription, CacheDocumentStore.cleUnique, inscription.versJson());
    } catch (_) {
      // Gardée en mémoire seulement.
    }
  }

  /// Après application, ou quand la personne choisit « Se connecter ».
  Future<void> effacer() async {
    await future;
    state = const AsyncData(null);
    try {
      await _store.supprimerDocument(_typeInscription, CacheDocumentStore.cleUnique);
    } catch (_) {
      // Rien à effacer.
    }
  }
}

/// Prénom et nom fournis par Google pour la session ouverte.
final nomsGoogleProvider = Provider<({String? prenom, String? nom})>((ref) {
  try {
    return nomsDepuisGoogle(ref.watch(sessionProvider.select((s) => s?.user.userMetadata)));
  } catch (_) {
    return (prenom: null, nom: null);
  }
});

/// Vrai quand le récapitulatif (bienvenue, identifiant EcoShop, prochaine
/// étape) doit s'afficher : une fois, après la création d'un compte.
final recapitulatifAMontrerProvider =
    AsyncNotifierProvider<RecapitulatifNotifier, bool>(RecapitulatifNotifier.new);

class RecapitulatifNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final id = ref.watch(profilProvider.select((p) => p.valueOrNull?.id));
    if (id == null) return false;
    try {
      return await ref.watch(_storeInscriptionProvider).lireDocument(_typeRecapitulatif, id) != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> aMontrer(String profilId) async {
    try {
      await ref.read(_storeInscriptionProvider).ecrireDocument(_typeRecapitulatif, profilId, {'a_montrer': true});
    } catch (_) {
      // Sans base locale, pas de récapitulatif : rien de bloquant.
    }
    ref.invalidateSelf();
  }

  Future<void> vu() async {
    final id = ref.read(profilProvider).valueOrNull?.id;
    state = const AsyncData(false);
    if (id == null) return;
    try {
      await ref.read(_storeInscriptionProvider).supprimerDocument(_typeRecapitulatif, id);
    } catch (_) {
      // Rien à effacer.
    }
  }
}
