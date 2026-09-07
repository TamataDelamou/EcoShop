import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_providers.dart';
import '../data/cached_scolarite_repository.dart';
import '../data/supabase_scolarite_repository.dart';
import '../domain/affectation_enseignant.dart';
import '../domain/fiche_eleve.dart';
import '../domain/inscription.dart';
import '../domain/relation_parent_eleve.dart';
import '../domain/scolarite_repository.dart';
import '../domain/structure_etablissement.dart';

/// Port de la scolarité — réseau d'abord, repli cache Drift (domaine
/// `scolarite`, table [CacheEntries] partagée à partir de M5).
final scolariteRepositoryProvider = Provider<ScolariteRepository>((ref) {
  final distant = SupabaseScolariteRepository(ref.watch(supabaseClientProvider));
  final cache = CacheDocumentStore(ref.watch(databaseProvider), 'scolarite');
  return CachedScolariteRepository(distant, cache);
});

/// Annuaire de l'établissement actif (unités, années, classes, périodes) pour
/// l'année [anneeScolaireId], ou l'année courante si `null`. Les unités et la
/// liste des années sont toujours complètes ; seules classes et périodes sont
/// bornées à l'année demandée.
final structureEtablissementProvider =
    FutureProvider.family<StructureEtablissement?, String?>((ref, anneeScolaireId) async {
  final etablissement = ref.watch(etablissementActifProvider);
  if (etablissement == null) return null;
  return ref.watch(scolariteRepositoryProvider).structureEtablissement(
        etablissement.id,
        anneeScolaireId: anneeScolaireId,
      );
});

/// Élèves inscrits dans une classe.
final inscriptionsDeClasseProvider =
    FutureProvider.family<List<Inscription>, String>((ref, classeId) {
  return ref.watch(scolariteRepositoryProvider).inscriptionsDeClasse(classeId);
});

/// Historique des inscriptions d'une fiche (classe actuelle en tête).
final inscriptionsDeFicheProvider =
    FutureProvider.family<List<Inscription>, String>((ref, ficheId) {
  return ref.watch(scolariteRepositoryProvider).inscriptionsDeFiche(ficheId);
});

/// Fiche de l'utilisateur connecté (rôle élève).
final maFicheProvider = FutureProvider<FicheEleve?>((ref) {
  return ref.watch(scolariteRepositoryProvider).maFiche();
});

/// Affectations enseignantes d'une classe.
final affectationsDeClasseProvider =
    FutureProvider.family<List<AffectationEnseignant>, String>((ref, classeId) {
  return ref.watch(scolariteRepositoryProvider).affectationsDeClasse(classeId);
});

/// Classes et matières de l'enseignant connecté.
final mesAffectationsProvider = FutureProvider<List<AffectationEnseignant>>((ref) {
  return ref.watch(scolariteRepositoryProvider).mesAffectations();
});

/// Enfants liés au parent connecté (support du sélecteur d'enfant).
final mesEnfantsProvider = FutureProvider<List<RelationParentEleve>>((ref) {
  if (ref.watch(profilProvider).value?.roleRacine != RoleRacine.parent) {
    return Future.value(const []);
  }
  return ref.watch(scolariteRepositoryProvider).mesEnfants();
});

/// Fiche actuellement choisie par le sélecteur d'enfant (aiguille le reste de
/// l'application — notes, absences, emploi du temps — une fois ces modules
/// branchés).
final enfantSelectionneProvider = StateProvider<FicheEleve?>((ref) => null);

/// Résout automatiquement l'enfant actif : le choix explicite s'il est
/// toujours valide, sinon le premier enfant confirmé de la liste.
final enfantActifProvider = Provider<FicheEleve?>((ref) {
  final enfants = ref.watch(mesEnfantsProvider).value ?? const [];
  final actifs = enfants.where((r) => r.estActive).map((r) => r.fiche).whereType<FicheEleve>();
  if (actifs.isEmpty) return null;

  final choisi = ref.watch(enfantSelectionneProvider);
  if (choisi != null && actifs.any((f) => f.id == choisi.id)) return choisi;
  return actifs.first;
});
