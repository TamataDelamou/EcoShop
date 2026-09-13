import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_providers.dart';
import '../data/langue_preference_store.dart';
import '../data/onboarding_regionalisation_store.dart';

final _langueStoreProvider = Provider<LanguePreferenceStore>((ref) {
  final store = CacheDocumentStore(ref.watch(databaseProvider), 'preferences');
  return LanguePreferenceStore(store);
});

/// Préférence de langue (D3) — un seul code opérant pour l'instant (`fr`,
/// voir [languesDisponibles]), mais persistée et relue dès maintenant :
/// poser la fondation sans attendre la traduction réelle de l'app.
final langueProvider =
    AsyncNotifierProvider<LangueNotifier, String>(LangueNotifier.new);

class LangueNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() => ref.watch(_langueStoreProvider).lire();

  Future<void> definir(String code) async {
    state = AsyncData(code);
    await ref.read(_langueStoreProvider).ecrire(code);
  }
}

/// Langues proposées par le sélecteur — une seule entrée opérante
/// aujourd'hui (D3) ; le widget qui la consomme (`SectionLangue`) est déjà
/// conçu pour en accueillir d'autres sans être reconstruit.
const languesDisponibles = <(String code, String libelle)>[
  ('fr', 'Français'),
];

final _onboardingRegionalisationStoreProvider =
    Provider<OnboardingRegionalisationStore>((ref) {
  final store = CacheDocumentStore(ref.watch(databaseProvider), 'preferences');
  return OnboardingRegionalisationStore(store);
});

/// `true` une fois que le profil courant a vu l'étape d'onboarding
/// Langue/Région (D3) — tant que le profil n'est pas encore résolu, `true`
/// par défaut : ce provider ne doit jamais être la raison d'un blocage,
/// `destinationProvider` gère déjà l'attente via `DestinationSession.chargement`.
final onboardingRegionalisationVuProvider =
    AsyncNotifierProvider<OnboardingRegionalisationNotifier, bool>(
  OnboardingRegionalisationNotifier.new,
);

class OnboardingRegionalisationNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final profilId = ref.watch(profilProvider).value?.id;
    if (profilId == null) return true;
    return ref.watch(_onboardingRegionalisationStoreProvider).lireVu(profilId);
  }

  Future<void> marquerVu() async {
    final profilId = ref.read(profilProvider).value?.id;
    if (profilId == null) return;
    state = const AsyncData(true);
    await ref.read(_onboardingRegionalisationStoreProvider).ecrireVu(profilId);
  }
}
