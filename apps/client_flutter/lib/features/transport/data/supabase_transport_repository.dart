import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../../pointage/domain/pointage.dart' show jetonDepuisLecture;
import '../domain/transport.dart';

/// Compte connecté, clé du cache local. Un client configuré avec
/// `accessToken` (tests, intégrations) n'expose pas `auth` : on répond
/// alors « aucun compte » au lieu de planter.
String? _compteConnecte(SupabaseClient client) {
  try {
    return client.auth.currentUser?.id;
  } on AuthException {
    return null;
  }
}

/// Transport scolaire (M18), d'abord hors connexion.
///
/// Le téléphone du chauffeur garde ses circuits, arrêts, élèves et leurs
/// cartes : il peut démarrer un trajet, marquer les arrêts, scanner les
/// montées et descentes, et terminer le trajet sans réseau. Chaque geste
/// part tout de suite (5 s au plus) ou attend le réseau avec sa clé et
/// l'heure réelle ; le serveur reconnaît les clés (jamais de doublon). Le
/// trajet en cours est gardé sur l'appareil pour reprendre après une
/// coupure. Seule la dernière position attend le réseau (les anciennes ne
/// servent plus à personne).
class SupabaseTransportRepository implements TransportRepository {
  SupabaseTransportRepository(this._client, this._file, this._store, [this._lecture]);

  final SupabaseClient _client;
  final DriftSyncRepository _file;
  final CacheDocumentStore _store;
  final LectureHorsLigne? _lecture;
  final Uuid _uuid = const Uuid();

  static const entiteTrajet = 'transport_trajet';
  static const entiteArret = 'transport_arret';
  static const entitePosition = 'transport_position';
  static const entiteMontee = 'transport_montee';
  static const entiteFin = 'transport_fin';
  static const entites = [entiteTrajet, entiteArret, entitePosition, entiteMontee, entiteFin];

  static const _delai = Duration(seconds: 5);
  static const _typeTrajet = 'trajet_local';

  // -------------------------------------------------------------------------
  // Outils
  // -------------------------------------------------------------------------
  static ErreurTransport _traduire(Object e) {
    if (e is ErreurTransport) return e;
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurTransport(premier);
      if (e.code == '42501') return const ErreurTransport('ACCES_REFUSE');
      return ErreurTransport(e.code ?? 'ERREUR_SERVEUR');
    }
    if (estErreurReseau(e)) return const ErreurTransport('HORS_CONNEXION');
    return ErreurTransport(e.toString());
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

  Future<Object?> _rpc(String nom, [Map<String, dynamic>? params, Duration delai = const Duration(seconds: 15)]) =>
      _client.rpc<dynamic>(nom, params: params).timeout(delai);

  /// Envoie tout de suite ; sans réseau, garde l'action sur l'appareil.
  /// Renvoie la réponse du serveur, ou `null` si l'action attend le réseau.
  Future<Object?> _envoyerOuGarder({
    required String id,
    required String entite,
    required String rpc,
    required Map<String, dynamic> params,
  }) async {
    try {
      final reponse = await _executer(() => _rpc(rpc, params, _delai));
      return reponse ?? const <String, dynamic>{};
    } on ErreurTransport catch (e) {
      if (e.code != 'HORS_CONNEXION') rethrow;
    }
    await _file.enfiler(SyncEntree(
      id: id,
      entite: entite,
      operation: 'rpc',
      payload: jsonEncode({'rpc': rpc, 'params': params}),
    ));
    return null;
  }

  static String _maintenant() => DateTime.now().toUtc().toIso8601String();

  Future<void> _garderTrajet(TrajetLocal t) => _store.ecrireDocument(_typeTrajet, t.circuitId, t.versJson());

  // -------------------------------------------------------------------------
  // Direction
  // -------------------------------------------------------------------------
  @override
  Future<List<CircuitTransport>> circuits(String etablissementId) => _lire(
        'transport_etablissement',
        etablissementId,
        () => _rpc('transport_etablissement', {'p_etablissement': etablissementId}),
        (json) => [
          for (final c in ((json as Map?)?['circuits'] as List?) ?? const [])
            CircuitTransport.depuisJson((c as Map).cast<String, dynamic>()),
        ],
      );

  @override
  Future<void> enregistrerCircuit({
    required String etablissementId,
    String? id,
    required String nom,
    String? vehicule,
    int? capacite,
    required double tarifAnnuel,
    String? chauffeur,
    bool actif = true,
  }) =>
      _executer(() => _rpc('enregistrer_circuit_transport', {
            'p_id': id ?? _uuid.v4(),
            'p_etablissement': etablissementId,
            'p_nom': nom,
            'p_vehicule': vehicule,
            'p_capacite': capacite,
            'p_tarif_annuel': tarifAnnuel,
            'p_chauffeur': chauffeur,
            'p_actif': actif,
          }));

  @override
  Future<void> enregistrerArrets(String circuitId, List<ArretTransport> arrets) => _executer(() => _rpc(
        'enregistrer_arrets_transport',
        {'p_circuit': circuitId, 'p_arrets': [for (final a in arrets) a.versJson()]},
      ));

  @override
  Future<List<EleveTransporte>> rechercherEleves(String etablissementId, String texte) => _executer(() async {
        final json = await _rpc('rechercher_eleves_transport', {'p_etablissement': etablissementId, 'p_texte': texte});
        return [for (final e in (json as List?) ?? const []) EleveTransporte.depuisJson((e as Map).cast<String, dynamic>())];
      });

  @override
  Future<void> affecter({required String ficheEleveId, required String circuitId, required String arretId}) => _executer(
      () => _rpc('affecter_eleve_transport', {'p_fiche': ficheEleveId, 'p_circuit': circuitId, 'p_arret': arretId}));

  @override
  Future<void> retirerAffectation(String ficheEleveId) =>
      _executer(() => _rpc('retirer_affectation_transport', {'p_fiche': ficheEleveId}));

  // -------------------------------------------------------------------------
  // Chauffeur
  // -------------------------------------------------------------------------
  @override
  Future<List<CircuitTransport>> mesCircuitsChauffeur() => _lire(
        'mes_circuits_chauffeur',
        _compteConnecte(_client) ?? 'anonyme',
        () => _rpc('mes_circuits_chauffeur'),
        (json) => [for (final c in (json as List?) ?? const []) CircuitTransport.depuisJson((c as Map).cast<String, dynamic>())],
      );

  @override
  Future<TrajetLocal?> trajetLocal(String circuitId) async {
    final doc = await _store.lireDocument(_typeTrajet, circuitId);
    return doc == null ? null : TrajetLocal.depuisJson(doc);
  }

  @override
  Future<TrajetLocal> demarrer(CircuitTransport circuit, SensTrajet sens) async {
    final trajet = TrajetLocal(id: _uuid.v4(), circuitId: circuit.id, sens: sens, demarreLe: DateTime.now());
    await _garderTrajet(trajet);
    await _envoyerOuGarder(
      id: trajet.id,
      entite: entiteTrajet,
      rpc: 'demarrer_trajet',
      params: {'p_id': trajet.id, 'p_circuit': circuit.id, 'p_sens': sens.code, 'p_demarre_le': _maintenant()},
    );
    return trajet;
  }

  @override
  Future<TrajetLocal> passerArret(TrajetLocal trajet, ArretTransport arret) async {
    if (trajet.arretsPasses.contains(arret.id)) return trajet;
    final suivant = trajet.avec(arretsPasses: [...trajet.arretsPasses, arret.id]);
    await _garderTrajet(suivant);
    await _envoyerOuGarder(
      id: 'arret:${trajet.id}:${arret.id}',
      entite: entiteArret,
      rpc: 'passer_arret',
      params: {'p_trajet': trajet.id, 'p_arret': arret.id, 'p_le': _maintenant()},
    );
    return suivant;
  }

  @override
  Future<void> signalerPosition(TrajetLocal trajet, double latitude, double longitude) async {
    await _envoyerOuGarder(
      // Même clé : seule la dernière position attend le réseau.
      id: 'position:${trajet.id}',
      entite: entitePosition,
      rpc: 'signaler_position_trajet',
      params: {'p_trajet': trajet.id, 'p_latitude': latitude, 'p_longitude': longitude, 'p_le': _maintenant()},
    );
  }

  @override
  Future<(ResultatScanBus, TrajetLocal)> scanner({
    required TrajetLocal trajet,
    required CircuitTransport circuit,
    required String lecture,
    required EvenementBus evenement,
  }) async {
    final jeton = jetonDepuisLecture(lecture);
    final eleve = circuit.eleves.where((e) => e.jeton != null && e.jeton == jeton).firstOrNull;
    if (eleve != null) {
      final aBord = trajet.aBord.contains(eleve.ficheEleveId);
      if (evenement == EvenementBus.montee && aBord) {
        return (ResultatScanBus(statut: StatutScanBus.dejaFait, evenement: evenement, eleve: eleve), trajet);
      }
    }
    final id = _uuid.v4();
    final reponse = await _envoyerOuGarder(
      id: id,
      entite: entiteMontee,
      rpc: 'enregistrer_montee',
      params: {
        'p_id': id,
        'p_trajet': trajet.id,
        'p_jeton': jeton,
        'p_evenement': evenement.code,
        'p_arret': _arretCourant(trajet, circuit)?.id,
        'p_scanne_le': _maintenant(),
      },
    );

    var statut = reponse == null ? StatutScanBus.enAttenteEnvoi : StatutScanBus.enregistre;
    String? nom;
    String? ficheServeur;
    if (reponse is Map) {
      switch (reponse['statut']) {
        case 'carte_inconnue':
          return (ResultatScanBus(statut: StatutScanBus.carteInconnue, evenement: evenement), trajet);
        case 'deja_recu':
          statut = StatutScanBus.dejaFait;
        default:
          if (reponse['hors_circuit'] == true) statut = StatutScanBus.horsCircuit;
      }
      nom = [reponse['prenom'], reponse['nom']].whereType<String>().join(' ');
      ficheServeur = reponse['fiche_eleve_id'] as String?;
    }

    final fiche = eleve?.ficheEleveId ?? ficheServeur;
    var suivant = trajet;
    if (fiche != null) {
      final liste = [...trajet.aBord]..remove(fiche);
      if (evenement == EvenementBus.montee) liste.add(fiche);
      suivant = trajet.avec(aBord: liste);
      await _garderTrajet(suivant);
    }
    return (ResultatScanBus(statut: statut, evenement: evenement, eleve: eleve, nom: nom), suivant);
  }

  /// Dernier arrêt marqué passé (là où se trouve le bus).
  static ArretTransport? _arretCourant(TrajetLocal trajet, CircuitTransport circuit) {
    if (trajet.arretsPasses.isEmpty) return null;
    return circuit.arret(trajet.arretsPasses.last);
  }

  @override
  Future<List<EleveTransporte>> terminer(TrajetLocal trajet, CircuitTransport circuit) async {
    // Le téléphone sait déjà qui est à bord : la vérification marche sans réseau.
    final restes = <String, EleveTransporte>{
      for (final id in trajet.aBord)
        id: circuit.eleves.where((e) => e.ficheEleveId == id).firstOrNull ??
            EleveTransporte(ficheEleveId: id, nom: '', prenom: 'Élève hors liste'),
    };
    final reponse = await _envoyerOuGarder(
      id: 'fin:${trajet.id}',
      entite: entiteFin,
      rpc: 'terminer_trajet',
      params: {'p_trajet': trajet.id, 'p_termine_le': _maintenant()},
    );
    if (reponse is Map) {
      for (final r in (reponse['restes_a_bord'] as List?) ?? const []) {
        final e = EleveTransporte.depuisJson((r as Map).cast<String, dynamic>());
        restes.putIfAbsent(e.ficheEleveId, () => e);
      }
    }
    await _store.supprimerDocument(_typeTrajet, trajet.circuitId);
    return restes.values.toList();
  }

  // -------------------------------------------------------------------------
  // Famille
  // -------------------------------------------------------------------------
  @override
  Future<SuiviTransport> suivi(String ficheEleveId) => _lire(
        'suivi_transport',
        ficheEleveId,
        () => _rpc('suivi_transport_enfant', {'p_fiche': ficheEleveId}),
        (json) => SuiviTransport.depuisJson((json as Map).cast<String, dynamic>()),
      );
}

/// Rejoue au serveur les gestes du chauffeur faits sans réseau, dans l'ordre.
class RejeuTransport {
  const RejeuTransport(this._client);

  final SupabaseClient _client;

  Future<void> rejouer(SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      await _client.rpc<dynamic>(p['rpc'] as String, params: (p['params'] as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      final metier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier);
      if (metier || e.code == '42501' || e.code == '23505' || e.code == '23514' || e.code == '23503' || e.code == '22023') {
        final code = metier ? premier : 'ACCES_REFUSE';
        throw RejetDefinitif(code, ErreurTransport(code).messageUtilisateur);
      }
      rethrow;
    }
  }

  static String libelle(SyncEntree entree) => switch (entree.entite) {
        SupabaseTransportRepository.entiteTrajet => 'Départ d’un trajet de bus',
        SupabaseTransportRepository.entiteArret => 'Passage du bus à un arrêt',
        SupabaseTransportRepository.entitePosition => 'Position du bus',
        SupabaseTransportRepository.entiteMontee => 'Montée ou descente d’un élève',
        _ => 'Fin d’un trajet de bus',
      };
}
