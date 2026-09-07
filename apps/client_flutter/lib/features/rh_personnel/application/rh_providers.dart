import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/cached_rh_repository.dart';
import '../data/supabase_rh_repository.dart';
import '../domain/absence_personnel.dart';
import '../domain/bulletin_paie.dart';
import '../domain/conge.dart';
import '../domain/contrat.dart';
import '../domain/effectif_categorie.dart';
import '../domain/employe.dart';
import '../domain/enums_rh.dart';
import '../domain/recommandation_formation.dart';
import '../domain/remplacement_suggere.dart';
import '../domain/rh_repository.dart';

/// Port réseau seul — utilisé par le rejeu de la file `sync_queue`
/// ([congesRejeuProvider]/[absencesPersonnelRejeuProvider]), qui doit
/// toujours viser le serveur directement (même convention que Notes/Vie
/// scolaire, M6/M7).
final _rhReseauProvider = Provider<RhRepository>((ref) {
  return SupabaseRhRepository(ref.watch(supabaseClientProvider));
});

/// Port RH & Personnel — réseau d'abord, repli cache Drift, écriture
/// tolérante hors-ligne via `sync_queue` (domaine `rh_personnel`).
final rhRepositoryProvider = Provider<RhRepository>((ref) {
  final cache = CacheDocumentStore(ref.watch(databaseProvider), 'rh_personnel');
  return CachedRhRepository(
    ref.watch(_rhReseauProvider),
    cache,
    ref.watch(syncRepositoryProvider),
  );
});

/// Fonctions de rejeu — branchées sur le moteur de synchronisation composé à
/// la racine applicative (`features/coquille/application/sync_composition.dart`).
final congesRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_rhReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.demanderConge(Conge.depuisJsonEcriture(json));
  };
});

final absencesPersonnelRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_rhReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.pointerAbsence(AbsencePersonnel.depuisJsonEcriture(json));
  };
});

/// Annuaire du personnel d'un établissement (vue RH/direction).
final employesEtablissementProvider = FutureProvider.family<List<Employe>, String>((ref, etablissementId) {
  return ref.watch(rhRepositoryProvider).employesEtablissement(etablissementId);
});

/// Dossier employé lié au compte connecté (auto-consultation).
final monEmployeProvider = FutureProvider.family<Employe?, String>((ref, profileId) {
  return ref.watch(rhRepositoryProvider).employeParProfil(profileId);
});

/// Fiche employé par identifiant.
final employeProvider = FutureProvider.family<Employe?, String>((ref, employeId) {
  return ref.watch(rhRepositoryProvider).employe(employeId);
});

/// Historique des contrats d'un employé.
final contratsDeEmployeProvider = FutureProvider.family<List<Contrat>, String>((ref, employeId) {
  return ref.watch(rhRepositoryProvider).contratsDeEmploye(employeId);
});

/// Congés d'un employé.
final congesDeEmployeProvider = FutureProvider.family<List<Conge>, String>((ref, employeId) {
  return ref.watch(rhRepositoryProvider).congesDeEmploye(employeId);
});

/// Absences pointées d'un employé.
final absencesDeEmployeProvider = FutureProvider.family<List<AbsencePersonnel>, String>((ref, employeId) {
  return ref.watch(rhRepositoryProvider).absencesDeEmploye(employeId);
});

/// Bulletins de paie d'un employé (consultation).
final bulletinsDeEmployeProvider = FutureProvider.family<List<BulletinPaie>, String>((ref, employeId) {
  return ref.watch(rhRepositoryProvider).bulletinsDeEmploye(employeId);
});

/// Charge horaire hebdomadaire (affectations M5).
final chargeHoraireProvider = FutureProvider.family<int, String>((ref, employeId) {
  return ref.watch(rhRepositoryProvider).chargeHoraire(employeId);
});

/// Tableau de bord effectifs (IA descriptive).
final analyserEffectifsProvider = FutureProvider.family<List<EffectifCategorie>, String>((ref, etablissementId) {
  return ref.watch(rhRepositoryProvider).analyserEffectifs(etablissementId);
});

/// Score de risque de turn-over — signal IA, jamais un verdict.
final scoreTurnoverProvider = FutureProvider.family<double, String>((ref, employeId) {
  return ref.watch(rhRepositoryProvider).scoreTurnover(employeId);
});

/// Recommandation de formation (IA prescriptive).
final recommanderFormationProvider =
    FutureProvider.family<List<RecommandationFormation>, ({String employeId, String anneeId})>((ref, args) {
  return ref.watch(rhRepositoryProvider).recommanderFormation(args.employeId, args.anneeId);
});

/// Suggestions de remplacement pour les enseignants absents (IA prescriptive).
final optimiserRemplacementsProvider =
    FutureProvider.family<List<RemplacementSuggere>, ({String etablissementId, DateTime date})>((ref, args) {
  return ref.watch(rhRepositoryProvider).optimiserRemplacements(args.etablissementId, args.date);
});

/// Construit une [Conge] prête à être déposée — un identifiant client généré
/// (uuid v4) sert de cible d'upsert hors-ligne, la contrainte serveur
/// `conges_employe_periode_type_unique` gouverne la déduplication réelle.
Conge construireCongeDemande({
  required String etablissementId,
  required String employeId,
  required TypeConge type,
  required DateTime dateDebut,
  required DateTime dateFin,
  required int nbJours,
  String? motif,
}) {
  return Conge(
    id: const Uuid().v4(),
    etablissementId: etablissementId,
    employeId: employeId,
    type: type,
    dateDebut: dateDebut,
    dateFin: dateFin,
    nbJours: nbJours,
    motif: motif,
  );
}

/// Construit une [AbsencePersonnel] prête à être pointée.
AbsencePersonnel construireAbsencePointage({
  required String etablissementId,
  required String employeId,
  required DateTime dateAbsence,
  TypeAbsencePersonnel type = TypeAbsencePersonnel.injustifiee,
  bool justifie = false,
  String? motif,
}) {
  return AbsencePersonnel(
    id: const Uuid().v4(),
    etablissementId: etablissementId,
    employeId: employeId,
    dateAbsence: dateAbsence,
    type: type,
    justifie: justifie,
    motif: motif,
  );
}
