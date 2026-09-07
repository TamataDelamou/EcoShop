import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/cached_planification_repository.dart';
import '../data/supabase_planification_repository.dart';
import '../domain/charge_travail.dart';
import '../domain/conflit_emploi.dart';
import '../domain/emploi_du_temps.dart';
import '../domain/enums_planification.dart';
import '../domain/evenement_agenda.dart';
import '../domain/planification_repository.dart';
import '../domain/progression_pedagogique.dart';
import '../domain/salle.dart';

/// Port réseau seul — utilisé par le rejeu de la file `sync_queue`, qui doit
/// toujours viser le serveur directement (même convention que M6-M10).
final _planificationReseauProvider = Provider<PlanificationRepository>((ref) {
  return SupabasePlanificationRepository(ref.watch(supabaseClientProvider));
});

/// Port Planification & Agenda — réseau d'abord, repli cache Drift,
/// écriture tolérante hors-ligne via `sync_queue` (domaine `planification`).
final planificationRepositoryProvider = Provider<PlanificationRepository>((ref) {
  final cache = CacheDocumentStore(ref.watch(databaseProvider), 'planification');
  return CachedPlanificationRepository(
    ref.watch(_planificationReseauProvider),
    cache,
    ref.watch(syncRepositoryProvider),
  );
});

/// Fonctions de rejeu — branchées sur le moteur de synchronisation composé à
/// la racine applicative (`features/coquille/application/sync_composition.dart`).
final emploisRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_planificationReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.enregistrerSeance(EmploiDuTemps.depuisJsonEcriture(json));
  };
});

final evenementsAgendaRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_planificationReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.enregistrerEvenement(EvenementAgenda.depuisJsonEcriture(json));
  };
});

final progressionPedagogiqueRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_planificationReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.enregistrerProgression(ProgressionPedagogique.depuisJsonEcriture(json));
  };
});

/// Salles de l'établissement.
final sallesEtablissementProvider = FutureProvider.family<List<Salle>, String>((ref, etablissementId) {
  return ref.watch(planificationRepositoryProvider).sallesEtablissement(etablissementId);
});

/// Emploi du temps d'une classe.
final emploisDeClasseProvider = FutureProvider.family<List<EmploiDuTemps>, String>((ref, classeId) {
  return ref.watch(planificationRepositoryProvider).emploisDeClasse(classeId);
});

/// Emploi du temps d'un enseignant, toutes classes confondues.
final emploisDeEnseignantProvider = FutureProvider.family<List<EmploiDuTemps>,
    ({String enseignantProfileId, String etablissementId, String anneeId})>((ref, args) {
  return ref
      .watch(planificationRepositoryProvider)
      .emploisDeEnseignant(args.enseignantProfileId, args.etablissementId, args.anneeId);
});

/// Occupation d'une salle sur une année.
final emploisDeSalleProvider =
    FutureProvider.family<List<EmploiDuTemps>, ({String salleId, String anneeId})>((ref, args) {
  return ref.watch(planificationRepositoryProvider).emploisDeSalle(args.salleId, args.anneeId);
});

/// Événements d'agenda de tout l'établissement.
final evenementsEtablissementProvider =
    FutureProvider.family<List<EvenementAgenda>, ({String etablissementId, String anneeId})>((ref, args) {
  return ref.watch(planificationRepositoryProvider).evenementsEtablissement(args.etablissementId, args.anneeId);
});

/// Événements d'agenda d'une classe.
final evenementsDeClasseProvider =
    FutureProvider.family<List<EvenementAgenda>, ({String classeId, String anneeId})>((ref, args) {
  return ref.watch(planificationRepositoryProvider).evenementsDeClasse(args.classeId, args.anneeId);
});

/// Progression pédagogique d'une classe.
final progressionDeClasseProvider =
    FutureProvider.family<List<ProgressionPedagogique>, ({String classeId, String anneeId})>((ref, args) {
  return ref.watch(planificationRepositoryProvider).progressionDeClasse(args.classeId, args.anneeId);
});

/// Chevauchements horaires détectés (IA descriptive).
final conflitsEmploiProvider =
    FutureProvider.family<List<ConflitEmploi>, ({String etablissementId, String anneeId})>((ref, args) {
  return ref.watch(planificationRepositoryProvider).detecterConflits(args.etablissementId, args.anneeId);
});

/// Charge horaire d'un enseignant (IA prédictive).
final chargeEnseignantProvider = FutureProvider.family<ChargeTravailEnseignant,
    ({String etablissementId, String anneeId, String enseignantProfileId})>((ref, args) {
  return ref
      .watch(planificationRepositoryProvider)
      .chargeEnseignant(args.etablissementId, args.anneeId, args.enseignantProfileId);
});

/// Charge horaire d'une classe (IA prédictive).
final chargeEleveProvider = FutureProvider.family<ChargeTravailEleve, String>((ref, classeId) {
  return ref.watch(planificationRepositoryProvider).chargeEleve(classeId);
});

/// Construit un [EmploiDuTemps] prêt à être enregistré — un identifiant
/// client généré (uuid v4) sert de cible d'upsert, la contrainte serveur
/// `idx_emplois_creneau_unique` gouverne la déduplication réelle pour une
/// nouvelle séance ; passer l'id d'une séance existante pour la modifier.
EmploiDuTemps construireSeance({
  String? id,
  required String etablissementId,
  required String anneeScolaireId,
  required String classeId,
  String? enseignantProfileId,
  String? programmeMatiereId,
  String? salleId,
  required int jourSemaine,
  required String heureDebut,
  required String heureFin,
  TypeSeance type = TypeSeance.cours,
  required String deviceId,
}) {
  return EmploiDuTemps(
    id: id ?? const Uuid().v4(),
    etablissementId: etablissementId,
    anneeScolaireId: anneeScolaireId,
    classeId: classeId,
    enseignantProfileId: enseignantProfileId,
    programmeMatiereId: programmeMatiereId,
    salleId: salleId,
    jourSemaine: jourSemaine,
    heureDebut: heureDebut,
    heureFin: heureFin,
    type: type,
    modifieLe: DateTime.now(),
    deviceId: deviceId,
  );
}

/// Construit un [EvenementAgenda] prêt à être enregistré.
EvenementAgenda construireEvenement({
  String? id,
  required String etablissementId,
  required String anneeScolaireId,
  String? classeId,
  required String titre,
  TypeEvenementAgenda type = TypeEvenementAgenda.reunion,
  required DateTime dateDebut,
  required DateTime dateFin,
  String? heureDebut,
  String? heureFin,
  String? lieu,
  bool rappel = false,
  required String deviceId,
}) {
  return EvenementAgenda(
    id: id ?? const Uuid().v4(),
    etablissementId: etablissementId,
    anneeScolaireId: anneeScolaireId,
    classeId: classeId,
    titre: titre,
    type: type,
    dateDebut: dateDebut,
    dateFin: dateFin,
    heureDebut: heureDebut,
    heureFin: heureFin,
    lieu: lieu,
    rappel: rappel,
    modifieLe: DateTime.now(),
    deviceId: deviceId,
  );
}
