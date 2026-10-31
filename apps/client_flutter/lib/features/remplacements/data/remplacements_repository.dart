import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../domain/remplacement.dart';

class ErreurRemplacement implements Exception {
  const ErreurRemplacement(this.code);

  final String code;

  String get message => switch (code) {
        'HORS_LIGNE' => 'Pas de réseau pour le moment. Réessayez une fois connecté.',
        'PERMISSION_REFUSEE' => 'Action réservée à la direction.',
        'ABSENCE_PASSEE' => 'On prévient d’une absence à venir ; une absence passée se déclare par la direction.',
        'REMPLACANT_INCONNU' => 'Choisissez un membre du personnel de l’école.',
        'PERIODE_TROP_LONGUE' => 'Choisissez une période de 4 mois au plus.',
        _ => 'Action impossible pour le moment. Réessayez.',
      };

  @override
  String toString() => code;
}

/// Absences des enseignants, remplacements, cours assurés (REG-41).
///
/// Hors connexion d'abord : le plan du jour et les changements d'une classe
/// sont gardés sur le téléphone ; une absence déclarée ou une décision prise
/// sans réseau part au retour (file d'envoi).
class RemplacementsRepository {
  RemplacementsRepository(this._client, this._lecture, this._file);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;
  final DriftSyncRepository _file;

  static const entiteAbsence = 'absence_enseignant';
  static const entiteDecision = 'decision_seance';
  static const entites = [entiteAbsence, entiteDecision];

  static ErreurRemplacement traduire(Object e) {
    if (e is ErreurRemplacement) return e;
    if (estErreurReseau(e)) return const ErreurRemplacement('HORS_LIGNE');
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurRemplacement(premier);
      if (e.code == '42501') return const ErreurRemplacement('PERMISSION_REFUSEE');
    }
    return const ErreurRemplacement('ERREUR_SERVEUR');
  }

  Future<T> _f<T>(Future<T> Function() a) async {
    try {
      return await a();
    } catch (e) {
      throw traduire(e);
    }
  }

  /// Écrit tout de suite, ou garde l'appel pour le retour du réseau.
  /// Renvoie vrai si c'est déjà sur le serveur.
  Future<bool> _ecrire(String entite, String cle, String fonction, Map<String, dynamic> params) async {
    try {
      await _client.rpc<dynamic>(fonction, params: params);
      return true;
    } catch (e) {
      if (!estErreurReseau(e)) throw traduire(e);
    }
    await _file.enfiler(SyncEntree(
      id: '$entite:$cle',
      entite: entite,
      operation: 'rpc',
      payload: jsonEncode({'fonction': fonction, 'params': params}),
    ));
    return false;
  }

  // ------------------------------------------------------------ direction

  Future<List<CoursARemplacer>> coursARemplacer(String etablissementId, DateTime date) => _f(() => _lecture.lire(
        type: 'cours_a_remplacer',
        cle: '$etablissementId.${dateIsoRemplacement(date)}',
        source: () => _client.rpc<dynamic>('cours_a_remplacer',
            params: {'p_etablissement': etablissementId, 'p_date': dateIsoRemplacement(date)}),
        decoder: CoursARemplacer.liste,
      ));

  Future<List<AbsenceEnseignant>> absences(String etablissementId, DateTime du, DateTime au) => _f(() => _lecture.lire(
        type: 'absences_enseignants',
        cle: '$etablissementId.${dateIsoRemplacement(du)}.${dateIsoRemplacement(au)}',
        source: () => _client.rpc<dynamic>('absences_enseignants_periode', params: {
          'p_etablissement': etablissementId,
          'p_du': dateIsoRemplacement(du),
          'p_au': dateIsoRemplacement(au),
        }),
        decoder: AbsenceEnseignant.liste,
      ));

  Future<List<RemplacantPossible>> remplacants(String emploiId, DateTime date) => _f(() async {
        final r = await _client.rpc<dynamic>('remplacants_possibles',
            params: {'p_emploi': emploiId, 'p_date': dateIsoRemplacement(date)});
        return [for (final x in (r as List? ?? const [])) RemplacantPossible.depuisJson((x as Map).cast<String, dynamic>())];
      });

  Future<bool> declarerAbsence({
    required String id,
    required String etablissementId,
    required String enseignantId,
    required DateTime du,
    required DateTime au,
    String? heureDebut,
    String? heureFin,
    String? motif,
  }) =>
      _ecrire(entiteAbsence, id, 'declarer_absence_enseignant', {
        'p_id': id,
        'p_etablissement': etablissementId,
        'p_enseignant': enseignantId,
        'p_du': dateIsoRemplacement(du),
        'p_au': dateIsoRemplacement(au),
        'p_heure_debut': heureDebut,
        'p_heure_fin': heureFin,
        'p_motif': motif,
      });

  Future<void> deciderAbsence(String id, bool valider) =>
      _f(() => _client.rpc<dynamic>('decider_absence_enseignant', params: {'p_id': id, 'p_valider': valider}));

  Future<void> retirerAbsence(String id) =>
      _f(() => _client.rpc<dynamic>('retirer_absence_enseignant', params: {'p_id': id}));

  Future<bool> decider({
    required String id,
    required String emploiId,
    required DateTime date,
    required SolutionSeance solution,
    String? remplacantId,
    DateTime? deplaceLe,
    String? deplaceDebut,
    String? deplaceFin,
    String? note,
  }) =>
      _ecrire(entiteDecision, '$emploiId:${dateIsoRemplacement(date)}', 'decider_seance', {
        'p_id': id,
        'p_emploi': emploiId,
        'p_date': dateIsoRemplacement(date),
        'p_solution': solution.code,
        'p_remplacant': remplacantId,
        'p_salle': null,
        'p_deplace_le': deplaceLe == null ? null : dateIsoRemplacement(deplaceLe),
        'p_deplace_debut': deplaceDebut,
        'p_deplace_fin': deplaceFin,
        'p_note': note,
      });

  Future<void> annulerDecision(String id) =>
      _f(() => _client.rpc<dynamic>('annuler_decision_seance', params: {'p_id': id}));

  Future<CoursAssures> coursAssures(String etablissementId, DateTime du, DateTime au) => _f(() => _lecture.lire(
        type: 'cours_assures',
        cle: '$etablissementId.${dateIsoRemplacement(du)}.${dateIsoRemplacement(au)}',
        source: () => _client.rpc<dynamic>('cours_assures', params: {
          'p_etablissement': etablissementId,
          'p_du': dateIsoRemplacement(du),
          'p_au': dateIsoRemplacement(au),
        }),
        decoder: (j) => CoursAssures.depuisJson(((j as Map?) ?? const {}).cast<String, dynamic>()),
      ));

  Future<CompteurRemplacements> compteur(String etablissementId, DateTime du, DateTime au) => _f(() => _lecture.lire(
        type: 'compteur_remplacements',
        cle: '$etablissementId.${dateIsoRemplacement(du)}.${dateIsoRemplacement(au)}',
        source: () => _client.rpc<dynamic>('compteur_remplacements', params: {
          'p_etablissement': etablissementId,
          'p_du': dateIsoRemplacement(du),
          'p_au': dateIsoRemplacement(au),
        }),
        decoder: (j) => CompteurRemplacements.depuisJson(((j as Map?) ?? const {}).cast<String, dynamic>()),
      ));

  Future<void> regler(String etablissementId, {required bool payes, double? tarif, DateTime? semaineA}) =>
      _f(() => _client.rpc<dynamic>('regler_remplacements', params: {
            'p_etablissement': etablissementId,
            'p_payes': payes,
            'p_tarif': tarif,
            'p_semaine_a': semaineA == null ? null : dateIsoRemplacement(semaineA),
          }));

  // ------------------------------------------------------------ enseignant, famille

  Future<MesRemplacements> mesRemplacements(String etablissementId) => _f(() => _lecture.lire(
        type: 'mes_remplacements',
        cle: etablissementId,
        source: () => _client.rpc<dynamic>('mes_remplacements', params: {'p_etablissement': etablissementId}),
        decoder: (j) => MesRemplacements.depuisJson(((j as Map?) ?? const {}).cast<String, dynamic>()),
      ));

  Future<List<ChangementCours>> changementsClasse(String classeId) => _f(() => _lecture.lire(
        type: 'changements_classe',
        cle: classeId,
        source: () => _client.rpc<dynamic>('changements_classe', params: {'p_classe': classeId}),
        decoder: ChangementCours.liste,
      ));

  Future<List<ChangementCours>> changementsFiche(String ficheId) => _f(() => _lecture.lire(
        type: 'changements_fiche',
        cle: ficheId,
        source: () => _client.rpc<dynamic>('changements_fiche', params: {'p_fiche': ficheId}),
        decoder: ChangementCours.liste,
      ));

  Future<void> purger() => _lecture.purger();

  // ------------------------------------------------------------ file d'envoi

  static Future<void> rejouer(SupabaseClient client, SyncEntree entree) async {
    final p = (jsonDecode(entree.payload) as Map).cast<String, dynamic>();
    try {
      await client.rpc<dynamic>('${p['fonction']}', params: (p['params'] as Map).cast<String, dynamic>());
    } catch (e) {
      if (estErreurReseau(e)) rethrow;
      final err = traduire(e);
      throw RejetDefinitif(err.code, err.message);
    }
  }

  static String libelle(SyncEntree entree) =>
      entree.entite == entiteAbsence ? 'Absence d’un enseignant' : 'Décision pour un cours (remplacement)';
}

final lectureRemplacementsProvider = Provider<LectureHorsLigne>((ref) => LectureHorsLigne(
      CacheDocumentStore(ref.watch(databaseProvider), 'remplacements_hl'),
      ref.watch(fraicheurHorsLigneProvider),
    ));

final remplacementsRepositoryProvider = Provider<RemplacementsRepository>((ref) => RemplacementsRepository(
      ref.watch(supabaseClientProvider),
      ref.watch(lectureRemplacementsProvider),
      ref.watch(syncRepositoryProvider),
    ));

typedef JourEcole = ({String etablissementId, DateTime date});
typedef PeriodeEcole = ({String etablissementId, DateTime du, DateTime au});

final coursARemplacerProvider = FutureProvider.autoDispose.family<List<CoursARemplacer>, JourEcole>((ref, p) {
  ref.watch(suiviSyncProvider);
  return ref.watch(remplacementsRepositoryProvider).coursARemplacer(p.etablissementId, p.date);
});

final absencesEnseignantsProvider = FutureProvider.autoDispose.family<List<AbsenceEnseignant>, PeriodeEcole>((ref, p) {
  ref.watch(suiviSyncProvider);
  return ref.watch(remplacementsRepositoryProvider).absences(p.etablissementId, p.du, p.au);
});

final coursAssuresProvider = FutureProvider.autoDispose.family<CoursAssures, PeriodeEcole>(
  (ref, p) => ref.watch(remplacementsRepositoryProvider).coursAssures(p.etablissementId, p.du, p.au),
);

final compteurRemplacementsProvider = FutureProvider.autoDispose.family<CompteurRemplacements, PeriodeEcole>(
  (ref, p) => ref.watch(remplacementsRepositoryProvider).compteur(p.etablissementId, p.du, p.au),
);

final mesRemplacementsProvider = FutureProvider.autoDispose.family<MesRemplacements, String>((ref, etablissementId) {
  ref.watch(suiviSyncProvider);
  return ref.watch(remplacementsRepositoryProvider).mesRemplacements(etablissementId);
});

final changementsClasseProvider = FutureProvider.autoDispose.family<List<ChangementCours>, String>(
  (ref, classeId) => ref.watch(remplacementsRepositoryProvider).changementsClasse(classeId),
);

final changementsFicheProvider = FutureProvider.autoDispose.family<List<ChangementCours>, String>(
  (ref, ficheId) => ref.watch(remplacementsRepositoryProvider).changementsFiche(ficheId),
);
