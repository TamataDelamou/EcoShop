import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/cached_vie_scolaire_repository.dart';
import '../data/supabase_vie_scolaire_repository.dart';
import '../domain/alerte_decrochage.dart';
import '../domain/enums_vie_scolaire.dart';
import '../domain/evenement_scolaire.dart';
import '../domain/presence.dart';
import '../domain/retard.dart';
import '../domain/sanction.dart';
import '../domain/vie_scolaire_repository.dart';

/// Port réseau seul — utilisé par le rejeu de la file `sync_queue`
/// ([presencesRejeuProvider]/[retardsRejeuProvider]), qui doit toujours
/// viser le serveur directement (même convention que Notes, M6).
final _vieScolaireReseauProvider = Provider<VieScolaireRepository>((ref) {
  return SupabaseVieScolaireRepository(ref.watch(supabaseClientProvider));
});

/// Port Absences & Vie scolaire — réseau d'abord, repli cache Drift, écriture
/// tolérante hors-ligne via `sync_queue` (domaine `vie_scolaire`).
final vieScolaireRepositoryProvider = Provider<VieScolaireRepository>((ref) {
  final cache = CacheDocumentStore(ref.watch(databaseProvider), 'vie_scolaire');
  return CachedVieScolaireRepository(
    ref.watch(_vieScolaireReseauProvider),
    cache,
    ref.watch(syncRepositoryProvider),
  );
});

/// Fonctions de rejeu — branchées sur le moteur de synchronisation composé à
/// la racine applicative (`features/coquille/application/sync_composition.dart`).
final presencesRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_vieScolaireReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.saisirPresence(Presence.depuisJsonEcriture(json));
  };
});

final retardsRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_vieScolaireReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.saisirRetard(Retard.depuisJsonCache(json));
  };
});

/// Présences d'une classe à une date (grille d'appel enseignant).
final presencesDeClasseProvider =
    FutureProvider.family<List<Presence>, ({String classeId, DateTime date})>((ref, args) {
  return ref.watch(vieScolaireRepositoryProvider).presencesDeClasse(args.classeId, args.date);
});

/// Historique des présences d'une fiche (consultation élève/parent/direction).
final presencesDeFicheProvider = FutureProvider.family<List<Presence>, String>((ref, ficheId) {
  return ref.watch(vieScolaireRepositoryProvider).presencesDeFiche(ficheId);
});

/// Historique des retards d'une fiche.
final retardsDeFicheProvider = FutureProvider.family<List<Retard>, String>((ref, ficheId) {
  return ref.watch(vieScolaireRepositoryProvider).retardsDeFiche(ficheId);
});

/// Sanctions d'une fiche.
final sanctionsDeFicheProvider = FutureProvider.family<List<Sanction>, String>((ref, ficheId) {
  return ref.watch(vieScolaireRepositoryProvider).sanctionsDeFiche(ficheId);
});

/// Alertes décrochage d'une fiche (élève/parent : uniquement transmises).
final alertesDeFicheProvider = FutureProvider.family<List<AlerteDecrochage>, String>((ref, ficheId) {
  return ref.watch(vieScolaireRepositoryProvider).alertesDeFiche(ficheId);
});

/// Alertes décrochage d'un établissement (vue direction).
final alertesEtablissementProvider =
    FutureProvider.family<List<AlerteDecrochage>, String>((ref, etablissementId) {
  return ref.watch(vieScolaireRepositoryProvider).alertesEtablissement(etablissementId);
});

/// Calendrier des événements scolaires d'un établissement.
final evenementsEtablissementProvider =
    FutureProvider.family<List<EvenementScolaire>, String>((ref, etablissementId) {
  return ref.watch(vieScolaireRepositoryProvider).evenementsEtablissement(etablissementId);
});

/// Tableau de bord comportemental descriptif (RPC `analyse_comportement`).
final analyseComportementProvider =
    FutureProvider.family<Map<String, dynamic>, ({String ficheId, String anneeId})>((ref, args) {
  return ref.watch(vieScolaireRepositoryProvider).analyseComportement(args.ficheId, args.anneeId);
});

/// Score de décrochage — signal IA, jamais un verdict (RPC serveur).
final scoreDecrochageProvider =
    FutureProvider.family<double, ({String ficheId, String anneeId})>((ref, args) {
  return ref.watch(vieScolaireRepositoryProvider).scoreDecrochage(args.ficheId, args.anneeId);
});

/// Recommandation éducative non punitive (RPC `recommander_sanction_educative`).
final recommandationSanctionProvider =
    FutureProvider.family<Map<String, dynamic>, ({String ficheId, String anneeId})>((ref, args) {
  return ref.watch(vieScolaireRepositoryProvider).recommandationSanction(args.ficheId, args.anneeId);
});

/// Construit une [Presence] déterministe (fiche + date + séance) prête à
/// être pointée — l'id sert de cible d'upsert (voir
/// `SupabaseVieScolaireRepository`, index uniques partiels sur `presences`).
Presence construirePresenceSaisie({
  required String etablissementId,
  required String anneeScolaireId,
  required String classeId,
  required String ficheEleveId,
  required DateTime date,
  required String saisiPar,
  required String deviceId,
  required bool enLigne,
  TypeSeance typeSeance = TypeSeance.demiJournee,
  String? programmeMatiereId,
  StatutPresence statut = StatutPresence.present,
  bool justifie = false,
  String? motif,
}) {
  final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  final id = typeSeance == TypeSeance.cours
      ? '$ficheEleveId:$dateStr:cours:${programmeMatiereId ?? '-'}'
      : '$ficheEleveId:$dateStr:demi_journee';

  return Presence(
    id: id,
    etablissementId: etablissementId,
    anneeScolaireId: anneeScolaireId,
    classeId: classeId,
    ficheEleveId: ficheEleveId,
    datePresence: date,
    saisiPar: saisiPar,
    typeSeance: typeSeance,
    programmeMatiereId: programmeMatiereId,
    statut: statut,
    justifie: justifie,
    motif: motif,
    saisiHorsLigne: !enLigne,
    deviceId: deviceId,
    clientTs: DateTime.now(),
  );
}

/// Construit une [Sanction] déclarée manuellement (origine humaine, jamais
/// `ia`) — l'`id` fourni est un simple placeholder, ignoré par
/// `SupabaseVieScolaireRepository.proposerSanction` (qui le retire du
/// payload avant insertion, le serveur générant le vrai id) : contrairement
/// à `construirePresenceSaisie`/`construireRetardSaisie`, aucune sémantique
/// d'upsert hors-ligne n'existe ici (une sanction exige une connexion active,
/// voir `CachedVieScolaireRepository`).
Sanction construireSanctionDeclaree({
  required String etablissementId,
  required String ficheEleveId,
  required String anneeScolaireId,
  required String decisionnaireId,
  required TypeSanction typeSanction,
  required String motif,
  required DateTime dateDebut,
  DateTime? dateFin,
  String? contexteEducatif,
  StatutSanction statut = StatutSanction.notifiee,
}) {
  return Sanction(
    id: '',
    etablissementId: etablissementId,
    ficheEleveId: ficheEleveId,
    anneeScolaireId: anneeScolaireId,
    typeSanction: typeSanction,
    motif: motif,
    dateDebut: dateDebut,
    dateFin: dateFin,
    decisionnaireId: decisionnaireId,
    contexteEducatif: contexteEducatif,
    statut: statut,
  );
}

/// Construit un [Retard] prêt à être enregistré (un par fiche et par jour,
/// contrainte `retards_fiche_date_unique`).
Retard construireRetardSaisie({
  required String etablissementId,
  required String ficheEleveId,
  required String anneeScolaireId,
  required DateTime date,
  required int minutesRetard,
  required String saisiPar,
  required String deviceId,
  required bool enLigne,
  bool justifie = false,
  String? motif,
}) {
  final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return Retard(
    id: '$ficheEleveId:$dateStr',
    etablissementId: etablissementId,
    ficheEleveId: ficheEleveId,
    anneeScolaireId: anneeScolaireId,
    dateRetard: date,
    minutesRetard: minutesRetard,
    saisiPar: saisiPar,
    justifie: justifie,
    motif: motif,
    saisiHorsLigne: !enLigne,
    deviceId: deviceId,
    clientTs: DateTime.now(),
  );
}
