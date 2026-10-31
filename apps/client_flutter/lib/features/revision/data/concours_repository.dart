import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/concours.dart';

class ErreurConcours implements Exception {
  const ErreurConcours(this.code);

  final String code;

  String get message => switch (code) {
        'HORS_LIGNE' => 'Pas de réseau : il faut le réseau pour recevoir le sujet d’une manche.',
        'NON_INSCRIT' => 'Inscris-toi d’abord au concours.',
        'PAS_ENCORE_OUVERTE' => 'La manche n’est pas encore ouverte.',
        'MANCHE_FERMEE' => 'La manche est fermée.',
        'DEJA_REMIS' => 'Ta copie a déjà été remise.',
        'CONCOURS_FERME' => 'Ce concours n’est pas ouvert.',
        'INSCRIPTIONS_CLOSES' => 'Les inscriptions sont closes.',
        'PERMISSION_REFUSEE' => 'Action réservée.',
        'TYPE_RESERVE_PLATEFORME' => 'Une école organise des concours internes ; les autres types sont organisés par GSG.',
        'CONCOURS_DEJA_OUVERT' => 'Le concours est déjà ouvert : on ne change plus ses règles.',
        'MANCHE_DEJA_COMMENCEE' => 'Des élèves ont commencé cette manche : elle ne peut plus changer.',
        'QUESTIONS_REQUISES' => 'Choisissez les questions de la manche.',
        'QUESTION_NON_PUBLIEE' => 'Une question choisie n’est pas publiée.',
        'MANCHE_REQUISE' => 'Ajoutez au moins une manche avant d’ouvrir le concours.',
        'CONCOURS_NON_TERMINE' => 'Terminez le concours avant de délivrer les certificats.',
        _ => 'Action impossible pour le moment. Réessayez.',
      };

  @override
  String toString() => code;
}

/// Concours et olympiades (REG-38 lot E2a). Le sujet s'obtient en ligne à
/// l'ouverture (équité) ; une copie remise sans réseau part au retour (le
/// serveur dit si elle arrive hors délai).
class ConcoursRepository {
  ConcoursRepository(this._client, this._lecture, this._file);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;
  final DriftSyncRepository _file;

  static const entiteRemise = 'manche_remise';
  static const entites = [entiteRemise];

  static ErreurConcours traduire(Object e) {
    if (e is ErreurConcours) return e;
    if (estErreurReseau(e)) return const ErreurConcours('HORS_LIGNE');
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurConcours(premier);
      if (e.code == '42501') return const ErreurConcours('PERMISSION_REFUSEE');
    }
    return const ErreurConcours('ERREUR_SERVEUR');
  }

  Future<T> _f<T>(Future<T> Function() a) async {
    try {
      return await a();
    } catch (e) {
      throw traduire(e);
    }
  }

  Future<List<Concours>> concoursEleve(String ficheId) => _f(() => _lecture.lire(
        type: 'concours',
        cle: ficheId,
        source: () => _client.rpc<dynamic>('concours_eleve', params: {'p_fiche': ficheId}),
        decoder: Concours.liste,
      ));

  Future<void> inscrire(String concoursId, String ficheId) =>
      _f(() => _client.rpc<dynamic>('inscrire_concours', params: {'p_concours': concoursId, 'p_fiche': ficheId}));

  Future<SujetManche> commencer(String mancheId, String ficheId) => _f(() async {
        final r = await _client.rpc<dynamic>('commencer_manche', params: {'p_manche': mancheId, 'p_fiche': ficheId});
        return SujetManche.depuisJson((r as Map).cast<String, dynamic>());
      });

  /// Remet la copie ; sans réseau, elle est gardée et envoyée au retour.
  Future<ResultatManche> remettre(String mancheId, String ficheId, Map<String, Object?> reponses, int nbQuestions) async {
    final params = {'p_manche': mancheId, 'p_fiche': ficheId, 'p_reponses': _json(reponses)};
    try {
      final r = await _client.rpc<dynamic>('remettre_manche', params: params);
      return ResultatManche.depuisJson((r as Map).cast<String, dynamic>());
    } catch (e) {
      if (!estErreurReseau(e)) throw traduire(e);
    }
    await _file.enfiler(SyncEntree(
      id: '$entiteRemise:$mancheId:$ficheId',
      entite: entiteRemise,
      operation: 'rpc',
      payload: jsonEncode(params),
    ));
    return ResultatManche(score: 0, questions: nbQuestions, enAttente: true);
  }

  Future<ClassementConcours> classement(String concoursId, {String? ficheId, String? pays, String? etablissementId}) =>
      _f(() => _lecture.lire(
            type: 'classement_concours',
            cle: '$concoursId|$ficheId|$pays|$etablissementId',
            source: () => _client.rpc<dynamic>('classement_concours', params: {
              'p_concours': concoursId,
              'p_fiche': ficheId,
              'p_pays': pays,
              'p_etablissement': etablissementId,
            }),
            decoder: (json) => ClassementConcours.depuisJson(((json as Map?) ?? const {}).cast<String, dynamic>()),
          ));

  // ------------------------------------------------------------ organisateur

  /// Concours organisés (école, ou plateforme si [etablissementId] est nul).
  Future<List<Map<String, dynamic>>> organises(String? etablissementId) => _f(() async {
        var q = _client.from('concours').select('*, manches_concours(*)');
        q = etablissementId == null ? q.isFilter('etablissement_id', null) : q.eq('etablissement_id', etablissementId);
        final l = await q.order('created_at', ascending: false);
        return [for (final c in l) c];
      });

  Future<void> enregistrerConcours({
    required String id,
    required String titre,
    required TypeConcours type,
    String? etablissementId,
    String? paysCode,
    required int gradeMin,
    required int gradeMax,
    String? description,
    String? recompenses,
    DateTime? inscriptionJusquau,
    int seuilCertificat = 50,
  }) =>
      _f(() => _client.rpc<dynamic>('enregistrer_concours', params: {
            'p_id': id,
            'p_titre': titre,
            'p_type': type.code,
            'p_etablissement': etablissementId,
            'p_pays': paysCode,
            'p_grade_min': gradeMin,
            'p_grade_max': gradeMax,
            'p_description': description,
            'p_recompenses': recompenses,
            'p_inscription_jusquau': inscriptionJusquau?.toUtc().toIso8601String(),
            'p_seuil_certificat': seuilCertificat,
          }));

  Future<void> enregistrerManche({
    required String id,
    required String concoursId,
    required int ordre,
    required String titre,
    required DateTime ouverture,
    required DateTime fermeture,
    required int dureeMin,
    required List<Map<String, dynamic>> questions,
  }) =>
      _f(() => _client.rpc<dynamic>('enregistrer_manche', params: {
            'p_id': id,
            'p_concours': concoursId,
            'p_ordre': ordre,
            'p_titre': titre,
            'p_ouverture': ouverture.toUtc().toIso8601String(),
            'p_fermeture': fermeture.toUtc().toIso8601String(),
            'p_duree_min': dureeMin,
            'p_questions': questions,
          }));

  Future<List<QuestionProposee>> questionsProposees(String concoursId) => _f(() async =>
      QuestionProposee.liste(await _client.rpc<dynamic>('questions_pour_concours', params: {'p_concours': concoursId})));

  Future<void> changerStatut(String concoursId, String statut) =>
      _f(() => _client.rpc<dynamic>('changer_statut_concours', params: {'p_concours': concoursId, 'p_statut': statut}));

  Future<int> delivrerCertificats(String concoursId) =>
      _f(() async => ((await _client.rpc<dynamic>('delivrer_certificats', params: {'p_concours': concoursId})) as num).toInt());

  Future<void> rehabiliter(String concoursId, String ficheId) =>
      _f(() => _client.rpc<dynamic>('rehabiliter_participation', params: {'p_concours': concoursId, 'p_fiche': ficheId}));

  static Object? _json(Object? d) {
    if (d is Set) return d.toList();
    if (d is Map) return d.map((k, v) => MapEntry('$k', _json(v)));
    if (d is List) return [for (final x in d) _json(x)];
    return d;
  }

  static Future<void> rejouer(SupabaseClient client, SyncEntree entree) async {
    try {
      await client.rpc<dynamic>('remettre_manche', params: jsonDecode(entree.payload) as Map<String, dynamic>);
    } catch (e) {
      if (estErreurReseau(e)) rethrow;
      final err = traduire(e);
      throw RejetDefinitif(err.code, err.message);
    }
  }

  static String libelle(SyncEntree entree) => 'Copie de concours';
}
