import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../data/contraste_eleve_store.dart';
import '../data/echelle_texte_store.dart';
import '../domain/echelle_texte.dart';

final _contrasteEleveStoreProvider = Provider<ContrasteEleveStore>((ref) {
  final store = CacheDocumentStore(ref.watch(databaseProvider), 'preferences');
  return ContrasteEleveStore(store);
});

/// Contraste élevé (D4, §34.9) — bascule vers une palette alternative dédiée
/// (`AppPalettes.hauteVisibilite`), jamais un curseur continu qui casserait
/// la vérification WCAG AA déjà faite palette par palette (voir
/// `app_palettes_test.dart`).
final contrasteEleveProvider =
    AsyncNotifierProvider<ContrasteEleveNotifier, bool>(ContrasteEleveNotifier.new);

class ContrasteEleveNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(_contrasteEleveStoreProvider).lire();

  Future<void> definir(bool actif) async {
    state = AsyncData(actif);
    await ref.read(_contrasteEleveStoreProvider).ecrire(actif);
  }
}

final _echelleTexteStoreProvider = Provider<EchelleTexteStore>((ref) {
  final store = CacheDocumentStore(ref.watch(databaseProvider), 'preferences');
  return EchelleTexteStore(store);
});

/// Taille du texte (D4, §34.9) — échelle discrète appliquée globalement via
/// le `textScaler` du `MaterialApp` racine (voir `main.dart`).
final echelleTexteProvider =
    AsyncNotifierProvider<EchelleTexteNotifier, EchelleTexte>(EchelleTexteNotifier.new);

class EchelleTexteNotifier extends AsyncNotifier<EchelleTexte> {
  @override
  Future<EchelleTexte> build() => ref.watch(_echelleTexteStoreProvider).lire();

  Future<void> definir(EchelleTexte echelle) async {
    state = AsyncData(echelle);
    await ref.read(_echelleTexteStoreProvider).ecrire(echelle);
  }
}
