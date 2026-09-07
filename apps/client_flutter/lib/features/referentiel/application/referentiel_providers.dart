import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/providers.dart';
import '../data/cached_referentiel_repository.dart';
import '../data/referentiel_cache_store.dart';
import '../data/supabase_referentiel_repository.dart';
import '../data/telechargement_paquet_service.dart';
import '../domain/arborescence_niveau.dart';
import '../domain/arborescence_pays.dart';
import '../domain/paquet_referentiel.dart';
import '../domain/pays_pedagogique.dart';
import '../domain/referentiel_repository.dart';
import '../domain/systeme_educatif.dart';

final _cacheStoreProvider = Provider<ReferentielCacheStore>((ref) {
  return ReferentielCacheStore(ref.watch(databaseProvider));
});

/// Port du référentiel pédagogique — réseau d'abord, repli cache Drift.
final referentielRepositoryProvider = Provider<ReferentielRepository>((ref) {
  final distant = SupabaseReferentielRepository(ref.watch(supabaseClientProvider));
  return CachedReferentielRepository(distant, ref.watch(_cacheStoreProvider));
});

final telechargementPaquetServiceProvider =
    Provider<TelechargementPaquetService>((ref) {
  return const TelechargementPaquetService();
});

/// Les 4 familles de systèmes éducatifs (invariant du modèle).
final systemesEducatifsProvider = FutureProvider<List<SystemeEducatif>>((ref) {
  return ref.watch(referentielRepositoryProvider).systemesEducatifs();
});

/// Pays pédagogiques déployés, triés par nom (public, aucune session requise).
final paysPedagogiquesProvider = FutureProvider<List<PaysPedagogique>>((ref) {
  return ref.watch(referentielRepositoryProvider).paysPedagogiques();
});

/// Arborescence (cycles + niveaux + examens) d'un pays sélectionné.
final arborescencePaysProvider =
    FutureProvider.family<ArborescencePays, String>((ref, paysCode) {
  return ref.watch(referentielRepositoryProvider).arborescencePays(paysCode);
});

/// Arborescence (filières + programmes + matières) d'un niveau sélectionné.
final arborescenceNiveauProvider =
    FutureProvider.family<ArborescenceNiveau, String>((ref, niveauId) {
  return ref.watch(referentielRepositoryProvider).arborescenceNiveau(niveauId);
});

/// Paquets de téléchargement hors-ligne disponibles pour un pays.
final paquetsDisponiblesProvider =
    FutureProvider.family<List<PaquetReferentiel>, String>((ref, paysCode) {
  return ref
      .watch(referentielRepositoryProvider)
      .paquetsDisponibles(paysCode: paysCode);
});
