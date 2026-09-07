import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/cached_rapports_repository.dart';
import '../data/supabase_rapports_repository.dart';
import '../domain/anomalie_statistique.dart';
import '../domain/enums_rapports.dart';
import '../domain/indicateur_cle.dart';
import '../domain/rapport.dart';
import '../domain/rapports_repository.dart';
import '../domain/recommandation_strategique.dart';

/// Port réseau seul — utilisé par le rejeu de la file `sync_queue`, qui doit
/// toujours viser le serveur directement (même convention que M6-M9).
final _rapportsReseauProvider = Provider<RapportsRepository>((ref) {
  return SupabaseRapportsRepository(ref.watch(supabaseClientProvider));
});

/// Port Rapports & Statistiques — réseau d'abord, repli cache Drift,
/// écriture tolérante hors-ligne via `sync_queue` (domaine `rapports`).
final rapportsRepositoryProvider = Provider<RapportsRepository>((ref) {
  final cache = CacheDocumentStore(ref.watch(databaseProvider), 'rapports');
  return CachedRapportsRepository(
    ref.watch(_rapportsReseauProvider),
    cache,
    ref.watch(syncRepositoryProvider),
  );
});

/// Fonction de rejeu — branchée sur le moteur de synchronisation composé à
/// la racine applicative (`features/coquille/application/sync_composition.dart`).
final rapportsRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_rapportsReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.demanderRapport(Rapport.depuisJsonEcriture(json));
  };
});

/// Rapports d'une fiche élève (vue parent/élève).
final rapportsDeFicheProvider = FutureProvider.family<List<Rapport>, String>((ref, ficheId) {
  return ref.watch(rapportsRepositoryProvider).rapportsDeFiche(ficheId);
});

/// Rapports de tout l'établissement (vue personnel).
final rapportsEtablissementProvider = FutureProvider.family<List<Rapport>, String>((ref, etablissementId) {
  return ref.watch(rapportsRepositoryProvider).rapportsEtablissement(etablissementId);
});

/// Indicateurs clés d'un établissement pour une année.
final indicateursEtablissementProvider =
    FutureProvider.family<List<IndicateurCle>, ({String etablissementId, String anneeId})>((ref, args) {
  return ref.watch(rapportsRepositoryProvider).indicateursEtablissement(args.etablissementId, args.anneeId);
});

/// Anomalies statistiques d'un établissement pour une année.
final anomaliesEtablissementProvider =
    FutureProvider.family<List<AnomalieStatistique>, ({String etablissementId, String anneeId})>((ref, args) {
  return ref.watch(rapportsRepositoryProvider).anomaliesEtablissement(args.etablissementId, args.anneeId);
});

/// Recommandations stratégiques d'un établissement pour une année.
final recommandationsEtablissementProvider =
    FutureProvider.family<List<RecommandationStrategique>, ({String etablissementId, String anneeId})>((ref, args) {
  return ref.watch(rapportsRepositoryProvider).recommandationsEtablissement(args.etablissementId, args.anneeId);
});

/// Score de risque d'une classe (IA prédictive).
final risqueClasseProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, classeId) {
  return ref.watch(rapportsRepositoryProvider).risqueClasse(classeId);
});

/// Construit un [Rapport] prêt à être demandé — un identifiant client
/// généré (uuid v4) sert de cible d'upsert hors-ligne (`rapports` n'a pas de
/// contrainte unique métier, l'upsert par id évite les doublons de retry).
Rapport construireDemandeRapport({
  required String etablissementId,
  required String anneeScolaireId,
  String? periodeId,
  String? classeId,
  String? ficheEleveId,
  required String type,
  TypeExport format = TypeExport.pdf,
  Map<String, dynamic> filtres = const {},
}) {
  return Rapport(
    id: const Uuid().v4(),
    etablissementId: etablissementId,
    anneeScolaireId: anneeScolaireId,
    periodeId: periodeId,
    classeId: classeId,
    ficheEleveId: ficheEleveId,
    type: type,
    format: format,
    filtres: filtres,
  );
}
