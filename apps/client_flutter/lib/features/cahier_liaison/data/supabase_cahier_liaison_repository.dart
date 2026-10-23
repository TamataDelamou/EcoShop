import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/cahier_liaison.dart';

/// Cahier de liaison, hors connexion d'abord :
/// - fils et élèves : dernière réponse du serveur resservie sans réseau ;
/// - mots, réponses et confirmations de lecture : envoyés tout de suite,
///   sinon gardés (file chiffrée par compte) avec leur clé et renvoyés au
///   retour du réseau, sans doublon ; ils apparaissent aussitôt « en attente
///   d'envoi » ;
/// - masquage (modération) : en ligne seulement.
class SupabaseCahierLiaisonRepository implements CahierLiaisonRepository {
  SupabaseCahierLiaisonRepository(this._client, this._file, [this._lecture]);

  final SupabaseClient _client;
  final DriftSyncRepository _file;
  final LectureHorsLigne? _lecture;
  static const _uuid = Uuid();

  static const entiteMot = 'liaison_mot';
  static const entiteReponse = 'liaison_reponse';
  static const entiteLecture = 'liaison_lecture';
  static const entites = [entiteMot, entiteReponse, entiteLecture];

  static const _delai = Duration(seconds: 10);

  static ErreurCahier _traduire(Object e) {
    if (e is ErreurCahier) return e;
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurCahier(premier);
      if (e.code == '42501') return const ErreurCahier('PERMISSION_REFUSEE');
      return ErreurCahier(e.code ?? 'ERREUR_SERVEUR');
    }
    if (estErreurReseau(e)) return const ErreurCahier('HORS_CONNEXION');
    return const ErreurCahier('ERREUR_INATTENDUE');
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

  /// Vrai si le serveur a reçu ; faux si l'action attend le réseau.
  Future<bool> _envoyerOuGarder(String id, String entite, String rpc, Map<String, dynamic> params) async {
    try {
      await _rpc(rpc, params);
      return true;
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
    return false;
  }

  Future<List<Map<String, dynamic>>> _enAttente(String entite) async => [
        for (final e in await _file.entreesEnAttente())
          if (e.entite == entite) ((jsonDecode(e.payload) as Map)['params'] as Map).cast<String, dynamic>(),
      ];

  @override
  Future<List<EleveLiaison>> eleves({String? etablissementId}) => _lire(
        'eleves_liaison',
        etablissementId ?? 'mes_enfants',
        () => _rpc('eleves_cahier_liaison', {'p_etablissement': etablissementId}),
        (json) => [for (final e in (json as List?) ?? const []) EleveLiaison.depuisJson((e as Map).cast<String, dynamic>())],
      );

  @override
  Future<List<MotLiaison>> cahier(String ficheEleveId) async {
    List<MotLiaison> serveur;
    try {
      serveur = await _lire('cahier_liaison', ficheEleveId, () => _rpc('cahier_liaison', {'p_fiche': ficheEleveId}),
          (json) => [for (final m in (json as List?) ?? const []) MotLiaison.depuisJson((m as Map).cast<String, dynamic>())]);
    } on ErreurCahier catch (e) {
      if (e.code != 'HORS_CONNEXION') rethrow;
      serveur = const [];
    }
    final motsGardes = [for (final p in await _enAttente(entiteMot)) if (p['p_fiche'] == ficheEleveId) p];
    final reponsesGardees = await _enAttente(entiteReponse);
    final lus = {for (final p in await _enAttente(entiteLecture)) p['p_message'] as String};

    MotLiaison completer(MotLiaison m) {
      final enAttente = [
        for (final p in reponsesGardees)
          if (p['p_mot'] == m.id && !m.reponses.any((r) => r.id == p['p_id']))
            MessageLiaison(
              id: p['p_id'] as String,
              corps: p['p_corps'] as String? ?? '',
              creeLe: DateTime.now(),
              deMoi: true,
              enAttenteEnvoi: true,
            ),
      ];
      return m.copierAvec(lu: m.lu || lus.contains(m.id), reponses: [...m.reponses, ...enAttente]);
    }

    return [
      for (final p in motsGardes.reversed)
        if (!serveur.any((m) => m.id == p['p_id']))
          completer(MotLiaison(
            id: p['p_id'] as String,
            ficheEleveId: ficheEleveId,
            corps: p['p_corps'] as String? ?? '',
            creeLe: DateTime.now(),
            deMoi: true,
            enAttenteEnvoi: true,
          )),
      for (final m in serveur) completer(m),
    ];
  }

  @override
  Future<bool> ecrireMot(String ficheEleveId, String corps) {
    final id = _uuid.v4();
    return _envoyerOuGarder(id, entiteMot, 'ecrire_mot_liaison', {'p_id': id, 'p_fiche': ficheEleveId, 'p_corps': corps.trim()});
  }

  @override
  Future<bool> repondre({required String ficheEleveId, required String motId, required String corps}) {
    final id = _uuid.v4();
    return _envoyerOuGarder(id, entiteReponse, 'repondre_liaison', {'p_id': id, 'p_mot': motId, 'p_corps': corps.trim()});
  }

  @override
  Future<void> confirmerLecture(String motId) async {
    await _envoyerOuGarder('lecture:$motId', entiteLecture, 'confirmer_lecture_liaison', {'p_message': motId});
  }

  @override
  Future<void> masquer(String messageId, String motif) async {
    try {
      await _rpc('masquer_message_liaison', {'p_message': messageId, 'p_motif': motif.trim()});
    } catch (e) {
      throw _traduire(e);
    }
  }
}

/// Rejoue les mots, réponses et lectures faits sans réseau. Refus du serveur
/// (droits, mot masqué entre-temps…) : définitif, montré à l'utilisateur.
class RejeuCahierLiaison {
  const RejeuCahierLiaison(this._client);

  final SupabaseClient _client;

  Future<void> rejouer(SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      await _client.rpc<dynamic>(p['rpc'] as String, params: (p['params'] as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      final metier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier);
      if (metier || e.code == '42501' || e.code == '23505' || e.code == '22023') {
        final code = metier ? premier : 'PERMISSION_REFUSEE';
        throw RejetDefinitif(code, ErreurCahier(code).message);
      }
      rethrow;
    }
  }

  static String libelle(SyncEntree entree) => switch (entree.entite) {
        SupabaseCahierLiaisonRepository.entiteMot => 'Mot du cahier de liaison',
        SupabaseCahierLiaisonRepository.entiteReponse => 'Réponse dans le cahier de liaison',
        _ => 'Lecture d’un mot du cahier de liaison',
      };
}
