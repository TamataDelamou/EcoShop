import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/cached_notes_repository.dart';
import '../data/supabase_notes_repository.dart';
import '../domain/appreciation.dart';
import '../domain/bulletin.dart';
import '../domain/evaluation.dart';
import '../domain/note.dart';
import '../domain/notes_repository.dart';

/// Port réseau seul — utilisé par le rejeu de la file `sync_queue`
/// ([notesRejeuProvider]), qui doit toujours viser le serveur directement.
final _notesReseauProvider = Provider<NotesRepository>((ref) {
  return SupabaseNotesRepository(ref.watch(supabaseClientProvider));
});

/// Port de Notes & Évaluations — réseau d'abord, repli cache Drift, écriture
/// tolérante hors-ligne via `sync_queue` (domaine `notes`).
final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  final cache = CacheDocumentStore(ref.watch(databaseProvider), 'notes');
  return CachedNotesRepository(
    ref.watch(_notesReseauProvider),
    cache,
    ref.watch(syncRepositoryProvider),
  );
});

/// Fonction de rejeu des notes en attente — branchée sur le moteur de
/// synchronisation composé à la racine applicative (voir
/// `features/coquille/application/sync_composition.dart`).
final notesRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_notesReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.saisirNote(Note.depuisJsonEcriture(json));
  };
});

/// Évaluations d'une classe pour une période (ou toutes si `null`).
final evaluationsDeClasseProvider =
    FutureProvider.family<List<Evaluation>, ({String classeId, String? periodeId})>((ref, args) {
  return ref.watch(notesRepositoryProvider).evaluationsDeClasse(args.classeId, periodeId: args.periodeId);
});

/// Notes d'une évaluation (grille de saisie enseignant), file d'attente
/// hors-ligne superposée.
final notesDeEvaluationProvider = FutureProvider.family<List<Note>, String>((ref, evaluationId) {
  return ref.watch(notesRepositoryProvider).notesDeEvaluation(evaluationId);
});

/// Notes d'une fiche (carnet élève/parent), pour une période donnée.
final notesDeFicheProvider =
    FutureProvider.family<List<Note>, ({String ficheId, String? periodeId})>((ref, args) {
  return ref.watch(notesRepositoryProvider).notesDeFiche(args.ficheId, periodeId: args.periodeId);
});

/// Moyenne d'un élève (RPC serveur, jamais calculée côté client).
final moyenneEleveProvider = FutureProvider.family<double?,
    ({String ficheId, String? matiereId, String? periodeId})>((ref, args) {
  return ref
      .watch(notesRepositoryProvider)
      .moyenneEleve(args.ficheId, programmeMatiereId: args.matiereId, periodeId: args.periodeId);
});

/// Appréciations d'une fiche pour une période.
final appreciationsDeFicheProvider =
    FutureProvider.family<List<Appreciation>, ({String ficheId, String? periodeId})>((ref, args) {
  return ref.watch(notesRepositoryProvider).appreciationsDeFiche(args.ficheId, periodeId: args.periodeId);
});

/// Bulletins d'une fiche.
final bulletinsDeFicheProvider = FutureProvider.family<List<Bulletin>, String>((ref, ficheId) {
  return ref.watch(notesRepositoryProvider).bulletinsDeFiche(ficheId);
});

/// Construit une [Note] prête à être saisie (id stable, horodatage LWW).
///
/// Ne prend pas de `Ref`/`WidgetRef` : `Ref` et `WidgetRef` n'ont pas de
/// supertype commun en Riverpod 2 (même convention que
/// `RafraichirSessionRef`/`RafraichirSessionWidgetRef` dans le module Auth) —
/// l'appelant résout donc [deviceId] lui-même (`ref.read(deviceIdProvider.future)`),
/// quel que soit son type de `Ref`.
Note construireNoteSaisie({
  required String etablissementId,
  required String evaluationId,
  required String ficheEleveId,
  required String saisiPar,
  required String deviceId,
  required bool enLigne,
  double? valeur,
  bool absent = false,
  String? commentaire,
}) {
  return Note(
    id: '$evaluationId:$ficheEleveId',
    etablissementId: etablissementId,
    evaluationId: evaluationId,
    ficheEleveId: ficheEleveId,
    saisiPar: saisiPar,
    valeur: absent ? null : valeur,
    absent: absent,
    commentaire: commentaire,
    saisiHorsLigne: !enLigne,
    deviceId: deviceId,
    clientTs: DateTime.now(),
  );
}
