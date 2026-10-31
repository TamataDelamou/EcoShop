import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/revision_repository.dart';
import '../domain/classement.dart';
import '../domain/examen_national.dart';
import '../domain/maitrise.dart';
import '../domain/quiz.dart';

final revisionRepositoryProvider = Provider<RevisionRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return RevisionRepository(
    ref.watch(supabaseClientProvider),
    CacheDocumentStore(db, 'revision_appareil'),
    LectureHorsLigne(CacheDocumentStore(db, 'revision_hl'), ref.watch(fraicheurHorsLigneProvider)),
    ref.watch(syncRepositoryProvider),
  );
});

/// Tout ce qu'il faut pour l'écran des révisions d'un élève.
class EspaceRevision {
  const EspaceRevision({required this.niveau, required this.paquet, required this.traces, required this.resume});

  final NiveauRevision niveau;
  final PaquetRevision paquet;
  final Map<String, TraceQuestion> traces;
  final ResumeRevision resume;
}

final espaceRevisionProvider = FutureProvider.autoDispose.family<EspaceRevision, String>((ref, ficheId) async {
  ref.watch(suiviSyncProvider); // relu quand un quiz en attente part
  final depot = ref.watch(revisionRepositoryProvider);
  final niveau = await depot.niveau(ficheId);
  final paquet = await depot.paquet(niveau);
  final traces = await depot.traces(ficheId);
  final resume = await depot.resume(ficheId, paquet: paquet);
  return EspaceRevision(niveau: niveau, paquet: paquet, traces: traces, resume: resume);
});

final classementRevisionProvider =
    FutureProvider.autoDispose.family<ClassementRevision, ({String fiche, String echelle})>((ref, cle) {
  ref.watch(suiviSyncProvider);
  return ref.watch(revisionRepositoryProvider).classement(cle.fiche, echelle: cle.echelle);
});

final bilanRevisionProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, ficheId) => ref.watch(revisionRepositoryProvider).bilan(ficheId),
);

/// Progression (lot R4) : profil, révisions du jour, plan. Vide si le
/// serveur n'est pas joignable et qu'aucune copie n'existe.
class ProgressionRevision {
  const ProgressionRevision({
    this.profil = const ProfilMaitrise(),
    this.revisions = const RevisionsDuJour(),
    this.plan,
    this.coefficients = const {},
  });

  final ProfilMaitrise profil;
  final RevisionsDuJour revisions;
  final PlanRevision? plan;
  final Map<String, num> coefficients;
}

final progressionRevisionProvider = FutureProvider.autoDispose.family<ProgressionRevision, ({String fiche, bool petites})>(
  (ref, cle) async {
    ref.watch(suiviSyncProvider);
    final depot = ref.watch(revisionRepositoryProvider);
    Future<T> ou<T>(Future<T> f, T defaut) async {
      try {
        return await f;
      } catch (_) {
        return defaut;
      }
    }

    final traces = await ou(depot.traces(cle.fiche), const <String, TraceQuestion>{});
    final profil = await ou(depot.profil(cle.fiche), const ProfilMaitrise());
    final revisions = await ou(
      depot.revisionsDuJour(cle.fiche, limite: plafondRevisions(petitesClasses: cle.petites)),
      const RevisionsDuJour(),
    );
    final plan = await ou(depot.plan(cle.fiche), null);
    final coefficients = plan == null ? const <String, num>{} : await ou(depot.coefficients(plan.matieres), const <String, num>{});
    return ProgressionRevision(
      profil: profil,
      revisions: revisions.sansDejaRevues(traces, DateTime.now()),
      plan: plan,
      coefficients: coefficients,
    );
  },
);

final classesSuiviesProvider = FutureProvider.autoDispose.family<List<({String id, String nom, int eleves})>, String>(
  (ref, etablissementId) => ref.watch(revisionRepositoryProvider).classesSuivies(etablissementId),
);

final maitriseClasseProvider = FutureProvider.autoDispose.family<MaitriseClasse, String>(
  (ref, classeId) => ref.watch(revisionRepositoryProvider).maitriseClasse(classeId),
);

final espacesExamensProvider = FutureProvider.autoDispose.family<List<EspaceExamen>, String>((ref, ficheId) async {
  ref.watch(suiviSyncProvider);
  try {
    return await ref.watch(revisionRepositoryProvider).espacesExamens(ficheId);
  } catch (_) {
    return const [];
  }
});
