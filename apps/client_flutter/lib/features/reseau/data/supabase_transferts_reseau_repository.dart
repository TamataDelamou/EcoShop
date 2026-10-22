import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/regles_transferts.dart';
import '../domain/reseau.dart';

/// Règles du réseau et transferts d'élèves (REG-17), d'abord hors connexion.
///
/// - Consultation (règles, grille, transferts, écoles, élèves, classes) :
///   dernière réponse resservie sans réseau.
/// - Demander, valider, accepter ou refuser un transfert : possible sans
///   réseau. Le geste est gardé avec sa clé et part au retour ; le serveur
///   reconnaît la clé (jamais deux transferts). Les listes le montrent
///   aussitôt, « en attente d'envoi ».
/// - Règles et grille : seulement en ligne (effet immédiat sur les tarifs
///   de toutes les écoles ; on doit voir tout de suite si c'est passé).
class SupabaseTransfertsReseauRepository implements TransfertsReseauRepository {
  SupabaseTransfertsReseauRepository(this._client, this._file, [this._lecture]);

  final SupabaseClient _client;
  final DriftSyncRepository _file;
  final LectureHorsLigne? _lecture;
  final Uuid _uuid = const Uuid();

  static const entiteDemande = 'reseau_transfert_demande';
  static const entiteValidation = 'reseau_transfert_validation';
  static const entiteReponse = 'reseau_transfert_reponse';
  static const entites = [entiteDemande, entiteValidation, entiteReponse];

  static const _delai = Duration(seconds: 10);

  static ErreurReseau _traduire(Object e) {
    if (e is ErreurReseau) return e;
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurReseau(premier);
      if (e.code == '42501') return const ErreurReseau('ACCES_REFUSE');
      return ErreurReseau(e.code ?? 'ERREUR_SERVEUR');
    }
    if (estErreurReseau(e)) return const ErreurReseau('HORS_CONNEXION');
    return ErreurReseau(e.toString());
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      throw _traduire(e);
    }
  }

  Future<T> _lire<T>(String type, String cle, Future<Object?> Function() source, T Function(Object?) decoder) {
    final lecture = _lecture;
    if (lecture == null) return _executer(() async => decoder(await source()));
    return _executer(() => lecture.lire(type: type, cle: cle, source: source, decoder: decoder));
  }

  Future<Object?> _rpc(String nom, [Map<String, dynamic>? params]) =>
      _client.rpc<dynamic>(nom, params: params).timeout(_delai);

  Future<bool> _envoyerOuGarder({
    required String id,
    required String entite,
    required String rpc,
    required Map<String, dynamic> params,
    Map<String, dynamic>? affichage,
  }) async {
    try {
      await _executer(() => _rpc(rpc, params));
      return true;
    } on ErreurReseau catch (e) {
      if (e.code != 'HORS_CONNEXION') rethrow;
    }
    await _file.enfiler(SyncEntree(
      id: id,
      entite: entite,
      operation: 'rpc',
      payload: jsonEncode({'rpc': rpc, 'params': params, 'affichage': ?affichage}),
    ));
    return false;
  }

  Future<List<({Map<String, dynamic> params, Map<String, dynamic> affichage})>> _enAttente(String entite) async {
    final r = <({Map<String, dynamic> params, Map<String, dynamic> affichage})>[];
    for (final e in await _file.entreesEnAttente()) {
      if (e.entite != entite) continue;
      final p = jsonDecode(e.payload) as Map<String, dynamic>;
      r.add((
        params: (p['params'] as Map).cast<String, dynamic>(),
        affichage: (p['affichage'] as Map?)?.cast<String, dynamic>() ?? const {},
      ));
    }
    return r;
  }

  static List<Map<String, dynamic>> _liste(Object? json) =>
      [for (final x in (json as List?) ?? const []) (x as Map).cast<String, dynamic>()];

  // -------------------------------------------------------------------------
  // Règles et grille
  // -------------------------------------------------------------------------
  @override
  Future<ReglesReseau> regles(String reseauId, {String? etablissementId}) => _lire(
        'regles',
        '$reseauId:${etablissementId ?? ''}',
        () => _rpc('regles_reseau', {'p_reseau': reseauId, 'p_etablissement': etablissementId}),
        (json) => ReglesReseau.depuisJson((json as Map).cast<String, dynamic>()),
      );

  @override
  Future<ReglesReseau> parametrer(ReglesReseau r) => _executer(() async {
        final json = await _rpc('parametrer_reseau', {
          'p_reseau': r.reseauId,
          'p_politique_frais': r.politiqueFrais,
          'p_transferts_ouverts': r.transfertsOuverts,
          'p_quitus_requis': r.quitusRequis,
          'p_validation_reseau': r.validationReseau,
          'p_inscription_offerte': r.inscriptionOfferte,
          'p_dossier_partage': r.dossierPartage,
        });
        return ReglesReseau.depuisJson((json as Map).cast<String, dynamic>());
      });

  @override
  Future<void> enregistrerGrille(String reseauId, List<LigneGrilleReseau> lignes) => _executer(() => _rpc(
        'enregistrer_grille_reseau',
        {'p_reseau': reseauId, 'p_lignes': [for (final l in lignes) l.versParams()]},
      ));

  @override
  Future<int> appliquerGrille(String reseauId, {String? etablissementId}) => _executer(() async {
        final json = await _rpc('appliquer_grille_reseau', {'p_reseau': reseauId, 'p_etablissement': etablissementId});
        return ((json as Map)['ecoles'] as num?)?.toInt() ?? 0;
      });

  // -------------------------------------------------------------------------
  // Transferts
  // -------------------------------------------------------------------------
  @override
  Future<List<TransfertReseau>> transferts({String? reseauId, String? etablissementId}) async {
    final serveur = await _lire(
      'transferts',
      '${reseauId ?? ''}:${etablissementId ?? ''}',
      () => _rpc('transferts_reseau_liste', {'p_reseau': reseauId, 'p_etablissement': etablissementId}),
      (json) => [for (final t in _liste(json)) TransfertReseau.depuisJson(t)],
    );

    // Gestes faits sans réseau : déjà visibles.
    final decisions = <String, ({String statut, String? motif, String? par})>{};
    for (final v in await _enAttente(entiteValidation)) {
      final accorde = v.params['p_accorder'] == true;
      decisions[v.params['p_id'] as String] =
          (statut: accorde ? 'en_attente_accueil' : 'refuse', motif: v.params['p_motif'] as String?, par: accorde ? null : 'reseau');
    }
    for (final v in await _enAttente(entiteReponse)) {
      final accepte = v.params['p_accepter'] == true;
      decisions[v.params['p_id'] as String] =
          (statut: accepte ? 'transfere' : 'refuse', motif: v.params['p_motif'] as String?, par: accepte ? null : 'accueil');
    }
    final liste = [
      for (final t in serveur)
        if (decisions[t.id] case final d?)
          t.avecStatut(d.statut, enAttenteEnvoi: true, motifRefus: d.motif, refusePar: d.par)
        else
          t,
    ];
    final connus = {for (final t in liste) t.id};
    for (final d in await _enAttente(entiteDemande)) {
      final id = d.params['p_id'] as String;
      if (connus.contains(id)) continue;
      if (etablissementId != null && d.affichage['origine_id'] != etablissementId) continue;
      liste.insert(
        0,
        TransfertReseau(
          id: id,
          statut: 'en_attente_accueil',
          eleve: d.affichage['eleve'] as String? ?? '',
          origine: d.affichage['origine'] as String? ?? '',
          origineId: d.affichage['origine_id'] as String?,
          destination: d.affichage['destination'] as String? ?? '',
          destinationId: d.params['p_destination'] as String?,
          motif: d.params['p_motif'] as String? ?? '',
          sens: etablissementId == null ? null : 'depart',
          demandeLe: DateTime.tryParse(d.affichage['le'] as String? ?? ''),
          enAttenteEnvoi: true,
        ),
      );
    }
    return liste;
  }

  @override
  Future<List<DestinationTransfert>> destinations(String etablissementId) => _lire(
        'destinations',
        etablissementId,
        () => _rpc('destinations_transfert', {'p_etablissement': etablissementId}),
        (json) => [for (final d in _liste(json)) DestinationTransfert.depuisJson(d)],
      );

  @override
  Future<List<EleveTransferable>> elevesTransferables(String etablissementId, {String texte = ''}) => _lire(
        'eleves',
        '$etablissementId:${texte.trim().toLowerCase()}',
        () => _rpc('eleves_transferables', {'p_etablissement': etablissementId, 'p_texte': texte.trim()}),
        (json) => [for (final e in _liste(json)) EleveTransferable.depuisJson(e)],
      );

  @override
  Future<List<ClasseAccueil>> classesAccueil(String transfertId) => _lire(
        'classes',
        transfertId,
        () => _rpc('classes_accueil_transfert', {'p_id': transfertId}),
        (json) => [for (final c in _liste(json)) ClasseAccueil.depuisJson(c)],
      );

  @override
  Future<bool> demander({
    required String etablissementId,
    required EleveTransferable eleve,
    required DestinationTransfert destination,
    required String motif,
  }) {
    final id = _uuid.v4();
    return _envoyerOuGarder(
      id: id,
      entite: entiteDemande,
      rpc: 'demander_transfert_reseau',
      params: {'p_id': id, 'p_fiche': eleve.ficheId, 'p_destination': destination.etablissementId, 'p_motif': motif.trim()},
      affichage: {
        'eleve': eleve.nomComplet,
        'origine_id': etablissementId,
        'origine': '',
        'destination': destination.nom,
        'le': DateTime.now().toIso8601String(),
      },
    );
  }

  @override
  Future<bool> valider({required String transfertId, required bool accorder, String? motif}) => _envoyerOuGarder(
        id: 'validation:$transfertId',
        entite: entiteValidation,
        rpc: 'valider_transfert_reseau',
        params: {'p_id': transfertId, 'p_accorder': accorder, 'p_motif': motif?.trim()},
      );

  @override
  Future<bool> repondre({required String transfertId, required bool accepter, String? classeId, String? motif}) =>
      _envoyerOuGarder(
        id: 'reponse:$transfertId',
        entite: entiteReponse,
        rpc: 'repondre_transfert_reseau',
        params: {'p_id': transfertId, 'p_accepter': accepter, 'p_classe': classeId, 'p_motif': motif?.trim()},
      );

  @override
  Future<void> annuler(String transfertId) =>
      _executer(() => _rpc('annuler_transfert_reseau', {'p_id': transfertId}));

  /// Ce qui avait été saisi, pour le reconnaître dans les refus du serveur.
  static String libelle(SyncEntree entree) {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    final params = (p['params'] as Map?)?.cast<String, dynamic>() ?? const {};
    final affichage = (p['affichage'] as Map?)?.cast<String, dynamic>() ?? const {};
    return switch (entree.entite) {
      entiteDemande => 'Transfert de ${affichage['eleve'] ?? 'l’élève'} vers ${affichage['destination'] ?? 'une autre école'}',
      entiteValidation => params['p_accorder'] == true ? 'Validation d’un transfert' : 'Refus d’un transfert (réseau)',
      _ => params['p_accepter'] == true ? 'Accueil d’un élève transféré' : 'Refus d’un élève transféré',
    };
  }
}
