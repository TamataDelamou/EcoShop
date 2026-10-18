import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/device_id_provider.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/inscription_hors_ligne_repository.dart';
import '../data/supabase_inscription_en_ligne_repository.dart';
import '../domain/inscription_en_ligne.dart';

/// Lecture hors connexion des écrans d'inscription (domaine de cache dédié,
/// purgé à la déconnexion : données d'élèves et de familles).
final lectureInscriptionsProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'inscriptions_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});

final inscriptionEnLigneRepositoryProvider = Provider<InscriptionHorsLigneRepository>((ref) {
  final distant = SupabaseInscriptionEnLigneRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(lectureInscriptionsProvider),
  );
  return InscriptionHorsLigneRepository(
    distant,
    ref.watch(syncRepositoryProvider),
    CacheDocumentStore(ref.watch(databaseProvider), 'inscriptions_hl'),
    () => ref.read(deviceIdProvider.future),
  );
});

/// Enfants (ou soi-même dès le collège) à réinscrire.
final reinscriptionsPossiblesProvider = FutureProvider.autoDispose<List<ReinscriptionPossible>>((ref) {
  ref.watch(suiviSyncProvider);
  return ref.watch(inscriptionEnLigneRepositoryProvider).reinscriptionsPossibles();
});

/// Dossiers de la famille, y compris ceux qui attendent l'envoi.
final mesDemandesInscriptionProvider = FutureProvider.autoDispose<List<DemandeInscription>>((ref) {
  ref.watch(suiviSyncProvider);
  return ref.watch(inscriptionEnLigneRepositoryProvider).mesDemandes();
});

/// Écoles dont les inscriptions sont ouvertes (recherche par nom ou ville).
final campagnesOuvertesProvider = FutureProvider.autoDispose.family<List<CampagneOuverte>, String>((ref, recherche) {
  return ref.watch(inscriptionEnLigneRepositoryProvider).campagnesOuvertes(recherche: recherche);
});

/// Campagne d'une année (Direction).
final campagneInscriptionProvider = FutureProvider.autoDispose
    .family<CampagneInscription?, ({String etablissementId, String anneeScolaireId})>((ref, cle) {
  return ref.watch(inscriptionEnLigneRepositoryProvider).campagne(cle.etablissementId, cle.anneeScolaireId);
});

/// Dossiers d'une campagne (Direction).
final dossiersCampagneProvider = FutureProvider.autoDispose.family<List<DemandeInscription>, String>((ref, campagneId) {
  ref.watch(suiviSyncProvider);
  return ref.watch(inscriptionEnLigneRepositoryProvider).dossiers(campagneId);
});

/// Tableau de bord d'une campagne (Direction).
final tableauCampagneProvider = FutureProvider.autoDispose.family<TableauCampagne, String>((ref, campagneId) {
  ref.watch(suiviSyncProvider);
  return ref.watch(inscriptionEnLigneRepositoryProvider).tableau(campagneId);
});

/// Dossiers dont une décision ou un paiement au guichet attend l'envoi.
final dossiersActionEnAttenteProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  ref.watch(suiviSyncProvider);
  return ref.watch(inscriptionEnLigneRepositoryProvider).dossiersAvecActionEnAttente();
});
