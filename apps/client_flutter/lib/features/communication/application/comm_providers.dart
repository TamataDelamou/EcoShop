import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/cached_comm_repository.dart';
import '../data/supabase_comm_repository.dart';
import '../domain/comm_repository.dart';
import '../domain/enums_comm.dart';
import '../domain/log_envoi.dart';
import '../domain/notif.dart';
import '../domain/preference_canal.dart';
import '../domain/taux_lecture_canal.dart';
import '../domain/template_notification.dart';

/// Port réseau seul — utilisé par le rejeu de la file `sync_queue`, qui doit
/// toujours viser le serveur directement (même convention que M6-M8).
final _commReseauProvider = Provider<CommRepository>((ref) {
  return SupabaseCommRepository(ref.watch(supabaseClientProvider));
});

/// Port Communication & Notifications — réseau d'abord, repli cache Drift,
/// écriture tolérante hors-ligne via `sync_queue` (domaine `communication`).
final commRepositoryProvider = Provider<CommRepository>((ref) {
  final cache = CacheDocumentStore(ref.watch(databaseProvider), 'communication');
  return CachedCommRepository(
    ref.watch(_commReseauProvider),
    cache,
    ref.watch(syncRepositoryProvider),
  );
});

/// Fonctions de rejeu — branchées sur le moteur de synchronisation composé à
/// la racine applicative (`features/coquille/application/sync_composition.dart`).
final notificationsLectureRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_commReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.marquerLue(json['id'] as String, destinataire: json['destinataire'] as String);
  };
});

final preferencesCanauxRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_commReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.definirPreference(PreferenceCanal.depuisJsonEcriture(json));
  };
});

/// Notifications du compte connecté (fil personnel).
final mesNotificationsProvider = FutureProvider.family<List<Notif>, String>((ref, profileId) {
  return ref.watch(commRepositoryProvider).mesNotifications(profileId);
});

/// Notifications de tout l'établissement (vue direction/communication).
final notificationsEtablissementProvider = FutureProvider.family<List<Notif>, String>((ref, etablissementId) {
  return ref.watch(commRepositoryProvider).notificationsEtablissement(etablissementId);
});

/// Préférences de canaux du compte connecté.
final mesPreferencesProvider = FutureProvider.family<List<PreferenceCanal>, String>((ref, profileId) {
  return ref.watch(commRepositoryProvider).mesPreferences(profileId);
});

/// Journal des envois d'un établissement (direction/communication).
final logsEtablissementProvider = FutureProvider.family<List<LogEnvoi>, String>((ref, etablissementId) {
  return ref.watch(commRepositoryProvider).logsEtablissement(etablissementId);
});

/// Modèles de messages d'un établissement.
final templatesEtablissementProvider = FutureProvider.family<List<TemplateNotification>, String>((ref, etablissementId) {
  return ref.watch(commRepositoryProvider).templatesEtablissement(etablissementId);
});

/// Taux de lecture par canal (IA descriptive).
final analyserEnvoisProvider = FutureProvider.family<List<TauxLectureCanal>,
    ({String etablissementId, DateTime debut, DateTime fin})>((ref, args) {
  return ref.watch(commRepositoryProvider).analyserEnvois(args.etablissementId, args.debut, args.fin);
});

/// Créneau d'envoi suggéré pour le compte connecté (IA prédictive).
final suggereHeureEnvoiProvider = FutureProvider.family<String, String>((ref, profileId) {
  return ref.watch(commRepositoryProvider).suggereHeureEnvoi(profileId);
});

/// Canal préféré pour un type de message (IA prescriptive).
final choisirCanalProvider = FutureProvider.family<String, ({String profileId, String type})>((ref, args) {
  return ref.watch(commRepositoryProvider).choisirCanal(args.profileId, args.type);
});

/// Construit une [PreferenceCanal] prête à être enregistrée — un identifiant
/// client généré (uuid v4) sert de cible d'upsert hors-ligne, la contrainte
/// serveur `prefs_canal_unique` gouverne la déduplication réelle.
PreferenceCanal construirePreference({
  required String profileId,
  required CanalNotification canal,
  bool actif = true,
  String horaireDebut = '08:00',
  String horaireFin = '19:00',
  FrequenceNotification frequence = FrequenceNotification.immediat,
}) {
  return PreferenceCanal(
    id: const Uuid().v4(),
    profileId: profileId,
    canal: canal,
    actif: actif,
    horaireDebut: horaireDebut,
    horaireFin: horaireFin,
    frequence: frequence,
  );
}
