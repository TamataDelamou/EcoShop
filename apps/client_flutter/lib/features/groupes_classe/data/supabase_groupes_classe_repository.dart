import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/groupe_classe.dart';

ErreurGroupe traduireErreurGroupe(Object e) {
  if (e is ErreurGroupe) return e;
  if (e is PostgrestException) {
    final premier = e.message.trim().split(RegExp(r'\s+')).first;
    if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurGroupe(premier);
    if (e.code == '42501') return const ErreurGroupe('PERMISSION_REFUSEE');
    return ErreurGroupe(e.code ?? 'ERREUR_SERVEUR');
  }
  if (estErreurReseau(e)) return const ErreurGroupe('HORS_CONNEXION');
  return const ErreurGroupe('ERREUR_INATTENDUE');
}

/// Groupes de classe, hors connexion d'abord :
/// - liste et fils : dernière réponse du serveur resservie sans réseau ;
/// - messages : envoyés tout de suite, sinon gardés (file chiffrée par
///   compte) avec leur clé, renvoyés au retour sans doublon, et montrés
///   aussitôt « en attente d'envoi » ;
/// - création, réglages, modération : en ligne seulement.
class SupabaseGroupesClasseRepository implements GroupesClasseRepository {
  SupabaseGroupesClasseRepository(this._client, this._file, [this._lecture]);

  final SupabaseClient _client;
  final DriftSyncRepository _file;
  final LectureHorsLigne? _lecture;
  static const _uuid = Uuid();

  static const entiteMessage = 'groupe_message';
  static const entites = [entiteMessage];

  static const _delai = Duration(seconds: 10);

  Future<Object?> _rpc(String nom, [Map<String, dynamic>? params]) =>
      _client.rpc<dynamic>(nom, params: params).timeout(_delai);

  Future<T> _lire<T>(String type, String cle, Future<Object?> Function() source, T Function(Object?) decoder) async {
    try {
      final lecture = _lecture;
      if (lecture == null) return decoder(await source());
      return await lecture.lire(type: type, cle: cle, source: source, decoder: decoder);
    } catch (e) {
      throw traduireErreurGroupe(e);
    }
  }

  Future<void> _enLigne(String nom, Map<String, dynamic> params) async {
    try {
      await _rpc(nom, params);
    } catch (e) {
      throw traduireErreurGroupe(e);
    }
  }

  @override
  Future<MesGroupes> mesGroupes(String etablissementId) => _lire(
        'mes_groupes',
        etablissementId,
        () => _rpc('mes_groupes_classe', {'p_etablissement': etablissementId}),
        (json) => MesGroupes.depuisJson((json as Map?)?.cast<String, dynamic>() ?? const {}),
      );

  @override
  Future<List<MessageGroupe>> fil(String groupeId) async {
    List<MessageGroupe> serveur;
    try {
      serveur = await _lire('fil_groupe', groupeId, () => _rpc('fil_groupe_classe', {'p_groupe': groupeId}),
          (json) => [for (final m in (json as List?) ?? const []) MessageGroupe.depuisJson((m as Map).cast<String, dynamic>())]);
    } on ErreurGroupe catch (e) {
      if (e.code != 'HORS_CONNEXION') rethrow;
      serveur = const [];
    }
    final gardes = [
      for (final e in await _file.entreesEnAttente())
        if (e.entite == entiteMessage) ((jsonDecode(e.payload) as Map)['params'] as Map).cast<String, dynamic>(),
    ];
    return [
      ...serveur,
      for (final p in gardes)
        if (p['p_groupe'] == groupeId && !serveur.any((m) => m.id == p['p_id']))
          MessageGroupe(
            id: p['p_id'] as String,
            creeLe: DateTime.now(),
            deMoi: true,
            corps: p['p_corps'] as String?,
            enAttenteEnvoi: true,
          ),
    ];
  }

  @override
  Future<bool> envoyer(String groupeId, String corps) async {
    final id = _uuid.v4();
    final params = {'p_id': id, 'p_groupe': groupeId, 'p_corps': corps.trim()};
    try {
      await _rpc('envoyer_message_groupe', params);
      return true;
    } catch (e) {
      final erreur = traduireErreurGroupe(e);
      if (erreur.code != 'HORS_CONNEXION') throw erreur;
    }
    await _file.enfiler(SyncEntree(
      id: id,
      entite: entiteMessage,
      operation: 'rpc',
      payload: jsonEncode({'rpc': 'envoyer_message_groupe', 'params': params}),
    ));
    return false;
  }

  @override
  Future<void> marquerLu(String groupeId) async {
    try {
      await _rpc('marquer_groupe_lu', {'p_groupe': groupeId});
    } catch (_) {
      // Sans réseau : le compteur se mettra à jour à la prochaine ouverture.
    }
  }

  @override
  Future<String> creer(String classeId) async {
    try {
      return (await _rpc('creer_groupe_classe', {'p_classe': classeId})) as String;
    } catch (e) {
      throw traduireErreurGroupe(e);
    }
  }

  @override
  Future<void> regler(String groupeId, {required bool elevesPeuventEcrire, required bool actif}) => _enLigne(
        'regler_groupe_classe',
        {'p_groupe': groupeId, 'p_eleves_peuvent_ecrire': elevesPeuventEcrire, 'p_actif': actif},
      );

  @override
  Future<void> signaler(String messageId, String motif) =>
      _enLigne('signaler_message_groupe', {'p_message': messageId, 'p_motif': motif.trim()});

  @override
  Future<void> masquer(String messageId, String motif) =>
      _enLigne('masquer_message_groupe', {'p_message': messageId, 'p_motif': motif.trim()});

  @override
  Future<List<SignalementGroupe>> signalements(String groupeId) async {
    try {
      final json = await _rpc('signalements_groupe', {'p_groupe': groupeId});
      return [for (final s in (json as List?) ?? const []) SignalementGroupe.depuisJson((s as Map).cast<String, dynamic>())];
    } catch (e) {
      throw traduireErreurGroupe(e);
    }
  }

  @override
  Future<void> ecarter(String signalementId) => _enLigne('ecarter_signalement', {'p_signalement': signalementId});

  @override
  Future<HeuresMessagerie?> heures(String etablissementId) => _lire(
        'heures_messagerie',
        etablissementId,
        () => _rpc('heures_messagerie', {'p_etablissement': etablissementId}),
        (json) => json is Map ? HeuresMessagerie.depuisJson(json.cast<String, dynamic>()) : null,
      );

  @override
  Future<void> definirHeures(String etablissementId,
          {required String debut, required String fin, required List<int> jours}) =>
      _enLigne('definir_heures_messagerie',
          {'p_etablissement': etablissementId, 'p_debut': debut, 'p_fin': fin, 'p_jours': jours});
}

/// Rejoue les messages écrits sans réseau. Refus du serveur (groupe fermé
/// entre-temps, hors des heures, droits) : définitif, montré à l'utilisateur.
class RejeuGroupesClasse {
  const RejeuGroupesClasse(this._client);

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
        throw RejetDefinitif(code, ErreurGroupe(code).message);
      }
      rethrow;
    }
  }

  static String libelle(SyncEntree entree) => 'Message dans le groupe de la classe';
}
