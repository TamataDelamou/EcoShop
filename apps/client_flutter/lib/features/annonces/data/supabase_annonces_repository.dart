import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/annonce.dart';

/// Annonces de l'école, hors connexion d'abord :
/// - lecture : dernière réponse du serveur resservie sans réseau ;
/// - publication et confirmation de lecture : envoyées tout de suite, sinon
///   gardées (file chiffrée par compte) avec leur clé et renvoyées au retour
///   du réseau, sans doublon ;
/// - masquage (modération) : en ligne seulement, pour que la direction voie
///   tout de suite qu'il a abouti.
class SupabaseAnnoncesRepository implements AnnoncesRepository {
  SupabaseAnnoncesRepository(this._client, this._file, [this._lecture]);

  final SupabaseClient _client;
  final DriftSyncRepository _file;
  final LectureHorsLigne? _lecture;
  static const _uuid = Uuid();

  static const entitePublication = 'annonce_publication';
  static const entiteLecture = 'annonce_lecture';
  static const entites = [entitePublication, entiteLecture];

  static const _delai = Duration(seconds: 10);

  static ErreurAnnonces _traduire(Object e) {
    if (e is ErreurAnnonces) return e;
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurAnnonces(premier);
      if (e.code == '42501') return const ErreurAnnonces('PERMISSION_REFUSEE');
      return ErreurAnnonces(e.code ?? 'ERREUR_SERVEUR');
    }
    if (estErreurReseau(e)) return const ErreurAnnonces('HORS_CONNEXION');
    return const ErreurAnnonces('ERREUR_INATTENDUE');
  }

  Future<Object?> _rpc(String nom, [Map<String, dynamic>? params]) =>
      _client.rpc<dynamic>(nom, params: params).timeout(_delai);

  Future<T> _lire<T>(String type, String cle, Future<Object?> Function() source, T Function(Object?) decoder) async {
    try {
      final lecture = _lecture;
      if (lecture == null) return decoder(await source());
      return await lecture.lire(type: type, cle: cle, source: source, decoder: decoder);
    } catch (e) {
      throw _traduire(e);
    }
  }

  /// Envoie ; sans réseau, garde. Renvoie la réponse du serveur, ou null si
  /// l'action attend le réseau.
  Future<Object?> _envoyerOuGarder(String id, String entite, String rpc, Map<String, dynamic> params) async {
    try {
      return await _rpc(rpc, params) ?? const <String, dynamic>{};
    } catch (e) {
      final erreur = _traduire(e);
      if (erreur.code != 'HORS_CONNEXION') throw erreur;
    }
    await _file.enfiler(SyncEntree(
      id: id,
      entite: entite,
      operation: 'rpc',
      payload: jsonEncode({'rpc': rpc, 'params': params}),
    ));
    return null;
  }

  Future<List<Map<String, dynamic>>> _enAttente(String entite) async => [
        for (final e in await _file.entreesEnAttente())
          if (e.entite == entite)
            ((jsonDecode(e.payload) as Map)['params'] as Map).cast<String, dynamic>(),
      ];

  static List<Annonce> _liste(Object? json) =>
      [for (final a in (json as List?) ?? const []) Annonce.depuisJson((a as Map).cast<String, dynamic>())];

  @override
  Future<List<Annonce>> mesAnnonces() async {
    final lues = {for (final p in await _enAttente(entiteLecture)) p['p_annonce'] as String};
    final serveur = await _lire('mes_annonces', 'moi', () => _rpc('mes_annonces'), _liste);
    return [for (final a in serveur) lues.contains(a.id) ? a.copierAvec(lue: true) : a];
  }

  @override
  Future<void> marquerLue(String annonceId) async {
    await _envoyerOuGarder('lecture:$annonceId', entiteLecture, 'marquer_annonce_lue', {'p_annonce': annonceId});
  }

  @override
  Future<List<Annonce>> annoncesEtablissement(String etablissementId) async {
    List<Annonce> serveur;
    try {
      serveur = await _lire('annonces_etablissement', etablissementId,
          () => _rpc('annonces_etablissement', {'p_etablissement': etablissementId}), _liste);
    } on ErreurAnnonces catch (e) {
      if (e.code != 'HORS_CONNEXION') rethrow;
      serveur = const [];
    }
    final gardees = [
      for (final p in await _enAttente(entitePublication))
        if (p['p_etablissement'] == etablissementId) p,
    ];
    return [
      for (final p in gardees.reversed)
        Annonce(
          id: p['p_id'] as String,
          etablissementId: etablissementId,
          titre: p['p_titre'] as String? ?? '',
          corps: p['p_corps'] as String? ?? '',
          importante: p['p_importante'] == true,
          parSms: p['p_par_sms'] == true,
          portee: PorteeAnnonce.depuisCode(p['p_portee'] as String?),
          publieeLe: DateTime.now(),
          enAttenteEnvoi: true,
        ),
      for (final a in serveur)
        if (!gardees.any((p) => p['p_id'] == a.id)) a,
    ];
  }

  @override
  Future<PorteesDisponibles> portees(String etablissementId) => _lire(
        'portees_annonce',
        etablissementId,
        () => _rpc('portees_annonce', {'p_etablissement': etablissementId}),
        (json) => PorteesDisponibles.depuisJson((json as Map?)?.cast<String, dynamic>() ?? const {}),
      );

  @override
  Future<ResultatPublication> publier({
    required String etablissementId,
    required PorteeAnnonce portee,
    String? cibleId,
    required String titre,
    required String corps,
    bool importante = false,
    bool parSms = false,
  }) async {
    final id = _uuid.v4();
    final reponse = await _envoyerOuGarder(id, entitePublication, 'publier_annonce', {
      'p_id': id,
      'p_etablissement': etablissementId,
      'p_portee': portee.code,
      'p_cible': portee == PorteeAnnonce.ecole ? null : cibleId,
      'p_titre': titre.trim(),
      'p_corps': corps.trim(),
      'p_importante': importante,
      'p_par_sms': parSms,
    });
    if (reponse == null) return const ResultatPublication(recue: false);
    final r = (reponse as Map).cast<String, dynamic>();
    return ResultatPublication(
      recue: true,
      familles: (r['familles'] as num?)?.toInt(),
      sms: (r['sms'] as num?)?.toInt(),
      smsNonEnvoyes: (r['sms_non_envoyes'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> masquer(String annonceId, String motif) async {
    try {
      await _rpc('masquer_annonce', {'p_annonce': annonceId, 'p_motif': motif.trim()});
    } catch (e) {
      throw _traduire(e);
    }
  }
}

/// Rejoue les publications et lectures faites sans réseau. Refus du serveur
/// (droits, portée vide…) : définitif, montré à l'utilisateur.
class RejeuAnnonces {
  const RejeuAnnonces(this._client);

  final SupabaseClient _client;

  Future<void> rejouer(SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      await _client.rpc<dynamic>(p['rpc'] as String, params: (p['params'] as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      final metier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier);
      if (metier || e.code == '42501' || e.code == '23505' || e.code == '23514' || e.code == '22023') {
        final code = metier ? premier : 'PERMISSION_REFUSEE';
        throw RejetDefinitif(code, ErreurAnnonces(code).message);
      }
      rethrow;
    }
  }

  static String libelle(SyncEntree entree) {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    final params = (p['params'] as Map?)?.cast<String, dynamic>() ?? const {};
    return entree.entite == SupabaseAnnoncesRepository.entitePublication
        ? 'Annonce « ${params['p_titre'] ?? ''} »'
        : 'Lecture d’une annonce';
  }
}
