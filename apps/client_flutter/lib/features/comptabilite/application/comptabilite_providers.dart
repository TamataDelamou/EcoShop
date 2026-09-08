import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/cached_comptabilite_repository.dart';
import '../data/supabase_comptabilite_repository.dart';
import '../domain/comptabilite_repository.dart';
import '../domain/ecriture_comptable.dart';
import '../domain/journal.dart';
import '../domain/ligne_balance.dart';
import '../domain/ligne_journal.dart';
import '../domain/mouvement_grand_livre.dart';
import '../domain/plan_comptable.dart';
import '../domain/signaux_ia_comptables.dart';

/// Port réseau seul — utilisé par le rejeu de la file `sync_queue`, qui doit
/// toujours viser le serveur directement (même convention que M6-M13).
final _comptabiliteReseauProvider = Provider<ComptabiliteRepository>((ref) {
  return SupabaseComptabiliteRepository(ref.watch(supabaseClientProvider));
});

/// Port Comptabilité — réseau d'abord, repli cache Drift, écriture tolérante
/// hors-ligne des écritures via `sync_queue` (domaine `comptabilite`).
final comptabiliteRepositoryProvider = Provider<ComptabiliteRepository>((ref) {
  final cache = CacheDocumentStore(ref.watch(databaseProvider), 'comptabilite');
  return CachedComptabiliteRepository(
    ref.watch(_comptabiliteReseauProvider),
    cache,
    ref.watch(syncRepositoryProvider),
  );
});

/// Fonction de rejeu — branchée sur le moteur de synchronisation composé à
/// la racine applicative (`features/coquille/application/sync_composition.dart`).
final ecrituresRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_comptabiliteReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.enregistrerEcriture(EcritureComptable.depuisJsonEcriture(json));
  };
});

/// Plan comptable de l'établissement.
final planComptableProvider = FutureProvider.family<List<PlanComptable>, String>((ref, etablissementId) {
  return ref.watch(comptabiliteRepositoryProvider).planComptable(etablissementId);
});

/// Journaux de l'établissement.
final journauxProvider = FutureProvider.family<List<Journal>, String>((ref, etablissementId) {
  return ref.watch(comptabiliteRepositoryProvider).journaux(etablissementId);
});

/// Écritures récentes (toutes confondues, triées par date décroissante).
final ecrituresRecentesProvider = FutureProvider.family<List<EcritureComptable>, String>((ref, etablissementId) {
  return ref.watch(comptabiliteRepositoryProvider).ecrituresRecentes(etablissementId);
});

/// Journal comptable d'une période.
final journalComptableProvider = FutureProvider.family<List<LigneJournal>,
    ({String etablissementId, String journalId, DateTime debut, DateTime fin})>((ref, args) {
  return ref
      .watch(comptabiliteRepositoryProvider)
      .journalComptable(args.etablissementId, args.journalId, args.debut, args.fin);
});

/// Grand livre d'un compte sur une période.
final grandLivreProvider = FutureProvider.family<List<MouvementGrandLivre>,
    ({String etablissementId, String compteId, DateTime debut, DateTime fin})>((ref, args) {
  return ref.watch(comptabiliteRepositoryProvider).grandLivre(args.etablissementId, args.compteId, args.debut, args.fin);
});

/// Balance à une date donnée.
final balanceComptableProvider =
    FutureProvider.family<List<LigneBalance>, ({String etablissementId, DateTime date})>((ref, args) {
  return ref.watch(comptabiliteRepositoryProvider).balanceComptable(args.etablissementId, args.date);
});

/// Anomalies comptables (IA descriptive).
final anomaliesComptablesProvider = FutureProvider.family<List<AnomalieComptable>, String>((ref, etablissementId) {
  return ref.watch(comptabiliteRepositoryProvider).detecterAnomalies(etablissementId);
});

/// Prévision de trésorerie à 30 jours (IA prédictive).
final previsionTresorerieProvider = FutureProvider.family<List<ProjectionTresorerie>, String>((ref, etablissementId) {
  return ref.watch(comptabiliteRepositoryProvider).predireTresorerie(etablissementId);
});

/// Écritures récurrentes recommandées (IA descriptive).
final ecrituresRecommandeesProvider =
    FutureProvider.family<List<EcritureRecommandee>, String>((ref, etablissementId) {
  return ref.watch(comptabiliteRepositoryProvider).recommanderEcritures(etablissementId);
});

/// Tendances charges/produits sur 12 mois (IA descriptive).
final tendancesComptablesProvider = FutureProvider.family<List<TendanceMensuelle>, String>((ref, etablissementId) {
  return ref.watch(comptabiliteRepositoryProvider).analyserTendances(etablissementId);
});

/// Construit une [EcritureComptable] prête à être enregistrée — identifiant
/// client généré (uuid v4) servant de cible d'upsert (pas de contrainte
/// unique métier sur cette table, comme `evenements_agenda` en M11).
EcritureComptable construireEcriture({
  String? id,
  required String etablissementId,
  required String journalId,
  required DateTime dateEcriture,
  required String libelle,
  required String compteDebitId,
  required String compteCreditId,
  required double montant,
  String? pieceJustificative,
  String? numeroLot,
  String? userId,
  required String deviceId,
}) =>
    EcritureComptable(
      id: id ?? const Uuid().v4(),
      etablissementId: etablissementId,
      journalId: journalId,
      dateEcriture: dateEcriture,
      libelle: libelle,
      compteDebitId: compteDebitId,
      compteCreditId: compteCreditId,
      montant: montant,
      pieceJustificative: pieceJustificative,
      numeroLot: numeroLot,
      userId: userId,
      saisiHorsLigne: true,
      deviceId: deviceId,
      clientTs: DateTime.now(),
    );
