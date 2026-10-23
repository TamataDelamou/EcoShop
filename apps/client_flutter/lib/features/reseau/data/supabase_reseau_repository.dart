import 'dart:convert';
import '../../../core/securite/gardien_actions_sensibles.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/reseau.dart';

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

/// Réseaux d'établissements (M19), d'abord hors connexion.
///
/// - Consultation (mes réseaux, tableau de bord, circulaires, calendrier) :
///   dernière réponse du serveur resservie sans réseau.
/// - Gestes du quotidien saisis sans réseau — demande de création,
///   circulaire, événement du calendrier, réponse à une invitation, accusé
///   de lecture — gardés sur l'appareil avec leur clé et envoyés au retour du
///   réseau (le serveur reconnaît la clé : jamais de doublon). Ils
///   apparaissent aussitôt dans les listes, marqués « en attente d'envoi ».
/// - Décisions qui engagent (validation GSG, retrait, dissolution,
///   nomination) : seulement en ligne, pour que la personne voie tout de
///   suite si elles ont abouti.
class SupabaseReseauRepository implements ReseauRepository {
  SupabaseReseauRepository(this._client, this._file, [this._lecture]);

  final SupabaseClient _client;
  final DriftSyncRepository _file;
  final LectureHorsLigne? _lecture;
  final Uuid _uuid = const Uuid();

  static const entiteDemande = 'reseau_demande';
  static const entiteCirculaire = 'reseau_circulaire';
  static const entiteEvenement = 'reseau_evenement';
  static const entiteInvitation = 'reseau_invitation';
  static const entiteLecture = 'reseau_lecture';
  static const entites = [entiteDemande, entiteCirculaire, entiteEvenement, entiteInvitation, entiteLecture];

  static const _delai = Duration(seconds: 10);

  // -------------------------------------------------------------------------
  // Outils
  // -------------------------------------------------------------------------
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

  /// Envoie tout de suite ; sans réseau, garde l'action sur l'appareil.
  /// Renvoie `true` si le serveur l'a reçue, `false` si elle attend le réseau.
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

  Future<List<Map<String, dynamic>>> _enAttente(String entite, bool Function(Map<String, dynamic> params) filtre) async {
    final resultat = <Map<String, dynamic>>[];
    for (final e in await _file.entreesEnAttente()) {
      if (e.entite != entite) continue;
      final p = jsonDecode(e.payload) as Map<String, dynamic>;
      final params = (p['params'] as Map).cast<String, dynamic>();
      if (filtre(params)) resultat.add({...params, 'affichage': p['affichage']});
    }
    return resultat;
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // -------------------------------------------------------------------------
  // Création, validation GSG
  // -------------------------------------------------------------------------
  @override
  Future<DemandeReseau> soumettreDemande(SaisieDemandeReseau saisie) async {
    final id = _uuid.v4();
    final recue = await _envoyerOuGarder(
      id: id,
      entite: entiteDemande,
      rpc: 'soumettre_demande_reseau',
      params: saisie.versParams(id),
    );
    return DemandeReseau(
      id: id,
      nom: saisie.nom,
      denomination: saisie.denomination,
      statut: 'en_attente',
      creeLe: DateTime.now(),
      typeReseau: saisie.typeReseau,
      enAttenteEnvoi: !recue,
    );
  }

  @override
  Future<DemandeReseau?> maDerniereDemande() async {
    final gardees = await _enAttente(entiteDemande, (_) => true);
    if (gardees.isNotEmpty) {
      final p = gardees.last;
      return DemandeReseau(
        id: p['p_id'] as String,
        nom: p['p_nom'] as String? ?? '',
        denomination: p['p_denomination'] as String? ?? '',
        statut: 'en_attente',
        creeLe: DateTime.now(),
        enAttenteEnvoi: true,
      );
    }
    final uid = _compteConnecte(_client);
    if (uid == null) return null;
    return _lire('ma_demande_reseau', uid, () async {
      return await _client
          .from('demandes_reseau')
          .select('id, nom, denomination, type_reseau, statut, motif_refus, created_at')
          .eq('demandeur_id', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(_delai);
    }, (json) => json == null ? null : DemandeReseau.depuisJson((json as Map).cast<String, dynamic>()));
  }

  @override
  Future<List<DemandeReseau>> demandesATraiter() => _executer(() async {
        final json = await _rpc('demandes_reseau_a_traiter');
        return [for (final d in (json as List?) ?? const []) DemandeReseau.depuisJson((d as Map).cast<String, dynamic>())];
      });

  @override
  Future<void> traiterDemande({required String demandeId, required bool accepter, String? motif, bool fraisRegles = false}) => avecCode('Décision sur la demande de réseau', () =>
      _executer(() => _rpc('traiter_demande_reseau', {
            'p_demande': demandeId,
            'p_accepter': accepter,
            'p_motif': motif,
            'p_frais_regles': fraisRegles,
          })));

  @override
  Future<List<ReseauVueGsg>> vueEnsemble() => _lire(
        'reseaux_gsg',
        'tous',
        () => _rpc('reseaux_vue_ensemble'),
        (json) => [for (final r in (json as List?) ?? const []) ReseauVueGsg.depuisJson((r as Map).cast<String, dynamic>())],
      );

  @override
  Future<void> deciderRetrait({required String reseauId, required String etablissementId, required bool accorder}) =>
      _executer(() => _rpc('decider_retrait_reseau', {
            'p_reseau': reseauId,
            'p_etablissement': etablissementId,
            'p_accorder': accorder,
          }));

  // -------------------------------------------------------------------------
  // Réseaux du compte, tableau de bord
  // -------------------------------------------------------------------------
  @override
  Future<List<MonReseau>> mesReseaux() async {
    final reseaux = await _lire(
      'mes_reseaux',
      _compteConnecte(_client) ?? 'anonyme',
      () => _rpc('mes_reseaux'),
      (json) => [for (final r in (json as List?) ?? const []) MonReseau.depuisJson((r as Map).cast<String, dynamic>())],
    );
    // Réponses à une invitation saisies sans réseau : déjà prises en compte.
    final reponses = await _enAttente(entiteInvitation, (_) => true);
    if (reponses.isEmpty) return reseaux;
    return [
      for (final r in reseaux)
        MonReseau(
          id: r.id,
          nom: r.nom,
          denomination: r.denomination,
          deviseCode: r.deviseCode,
          monRole: r.monRole,
          responsables: r.responsables,
          ecoles: [for (final e in r.ecoles) _avecReponse(e, r.id, reponses)],
        ),
    ];
  }

  static EcoleDuReseau _avecReponse(EcoleDuReseau e, String reseauId, List<Map<String, dynamic>> reponses) {
    if (e.statut != 'invite') return e;
    final rep = reponses.where((p) => p['p_reseau'] == reseauId && p['p_etablissement'] == e.etablissementId).toList();
    if (rep.isEmpty) return e;
    return EcoleDuReseau(
      etablissementId: e.etablissementId,
      nom: e.nom,
      ville: e.ville,
      statut: rep.last['p_accepter'] == true ? 'membre' : 'refuse',
    );
  }

  @override
  Future<TableauBordReseau> tableauBord(String reseauId) => _lire(
        'tableau_bord_reseau',
        reseauId,
        () => _rpc('tableau_bord_reseau', {'p_reseau': reseauId}),
        (json) => TableauBordReseau.depuisJson((json as Map).cast<String, dynamic>()),
      );

  // -------------------------------------------------------------------------
  // Pilotage
  // -------------------------------------------------------------------------
  @override
  Future<List<EcoleDuReseau>> rechercherEtablissements(String reseauId, String texte) => _executer(() async {
        final json = await _rpc('rechercher_etablissements_reseau', {'p_reseau': reseauId, 'p_texte': texte});
        return [
          for (final e in (json as List?) ?? const [])
            EcoleDuReseau.depuisJson({...(e as Map).cast<String, dynamic>(), 'statut': e['statut_reseau'] ?? ''}),
        ];
      });

  @override
  Future<void> inviter(String reseauId, String etablissementId) =>
      _executer(() => _rpc('inviter_etablissement_reseau', {'p_reseau': reseauId, 'p_etablissement': etablissementId}));

  @override
  Future<void> nommerResponsable(String reseauId, String identifiant, String role) => _executer(
      () => _rpc('nommer_responsable_reseau', {'p_reseau': reseauId, 'p_identifiant': identifiant, 'p_role': role}));

  @override
  Future<void> retirerResponsable(String reseauId, String profileId) =>
      _executer(() => _rpc('retirer_responsable_reseau', {'p_reseau': reseauId, 'p_profil': profileId}));

  @override
  Future<void> dissoudre(String reseauId, String confirmationNom) =>
      _executer(() => _rpc('dissoudre_reseau', {'p_reseau': reseauId, 'p_confirmation_nom': confirmationNom}));

  @override
  Future<bool> publierCirculaire({
    required String reseauId,
    required String titre,
    required String corps,
    required bool importante,
  }) {
    final id = _uuid.v4();
    return _envoyerOuGarder(
      id: id,
      entite: entiteCirculaire,
      rpc: 'publier_circulaire_reseau',
      params: {'p_id': id, 'p_reseau': reseauId, 'p_titre': titre, 'p_corps': corps, 'p_importante': importante},
    );
  }

  @override
  Future<bool> enregistrerEvenement({
    required String reseauId,
    required String titre,
    required String type,
    required DateTime debut,
    required DateTime fin,
    String? description,
    String? id,
  }) {
    final cle = id ?? _uuid.v4();
    return _envoyerOuGarder(
      id: cle,
      entite: entiteEvenement,
      rpc: 'enregistrer_evenement_reseau',
      params: {
        'p_id': cle,
        'p_reseau': reseauId,
        'p_titre': titre,
        'p_type': type,
        'p_debut': _date(debut),
        'p_fin': _date(fin),
        'p_description': description,
      },
    );
  }

  @override
  Future<void> supprimerEvenement(String evenementId) =>
      _executer(() => _rpc('supprimer_evenement_reseau', {'p_id': evenementId}));

  // -------------------------------------------------------------------------
  // Écoles du réseau
  // -------------------------------------------------------------------------
  @override
  Future<List<CirculaireReseau>> circulaires(String reseauId) async {
    final lues = {for (final p in await _enAttente(entiteLecture, (_) => true)) p['p_circulaire'] as String};
    List<CirculaireReseau> serveur;
    try {
      serveur = await _lire(
        'circulaires_reseau',
        reseauId,
        () => _rpc('circulaires_reseau_liste', {'p_reseau': reseauId}),
        (json) => [for (final c in (json as List?) ?? const []) CirculaireReseau.depuisJson((c as Map).cast<String, dynamic>())],
      );
    } on ErreurReseau catch (e) {
      if (e.code != 'HORS_CONNEXION') rethrow;
      serveur = const [];
    }
    final gardees = await _enAttente(entiteCirculaire, (p) => p['p_reseau'] == reseauId);
    return [
      for (final p in gardees.reversed)
        CirculaireReseau(
          id: p['p_id'] as String,
          titre: p['p_titre'] as String? ?? '',
          corps: p['p_corps'] as String? ?? '',
          importante: p['p_importante'] as bool? ?? false,
          publieeLe: DateTime.now(),
          lue: true,
          enAttenteEnvoi: true,
        ),
      for (final c in serveur)
        lues.contains(c.id)
            ? CirculaireReseau(
                id: c.id,
                titre: c.titre,
                corps: c.corps,
                importante: c.importante,
                publieeLe: c.publieeLe,
                lue: true,
                lectures: c.lectures,
                destinataires: c.destinataires,
              )
            : c,
    ];
  }

  @override
  Future<List<EvenementReseau>> evenements(String reseauId, {String? etablissementId}) async {
    List<EvenementReseau> serveur;
    try {
      serveur = await _lire(
        'evenements_reseau',
        '$reseauId/${etablissementId ?? '-'}',
        () => _rpc('evenements_reseau_liste', {'p_reseau': reseauId, 'p_etablissement': etablissementId}),
        (json) => [for (final e in (json as List?) ?? const []) EvenementReseau.depuisJson((e as Map).cast<String, dynamic>())],
      );
    } on ErreurReseau catch (e) {
      if (e.code != 'HORS_CONNEXION') rethrow;
      serveur = const [];
    }
    final gardes = await _enAttente(entiteEvenement, (p) => p['p_reseau'] == reseauId);
    final remplaces = {for (final p in gardes) p['p_id'] as String};
    final tous = [
      for (final e in serveur)
        if (!remplaces.contains(e.id)) e,
      for (final p in gardes)
        EvenementReseau(
          id: p['p_id'] as String,
          titre: p['p_titre'] as String? ?? '',
          type: p['p_type'] as String? ?? 'autre',
          debut: DateTime.parse(p['p_debut'] as String),
          fin: DateTime.parse(p['p_fin'] as String),
          description: p['p_description'] as String?,
          enAttenteEnvoi: true,
        ),
    ]..sort((a, b) => a.debut.compareTo(b.debut));
    return tous;
  }

  @override
  Future<bool> repondreInvitation({required String reseauId, required String etablissementId, required bool accepter}) =>
      _envoyerOuGarder(
        id: 'invitation:$reseauId:$etablissementId',
        entite: entiteInvitation,
        rpc: 'repondre_invitation_reseau',
        params: {'p_reseau': reseauId, 'p_etablissement': etablissementId, 'p_accepter': accepter},
      );

  @override
  Future<void> marquerLue(String circulaireId) async {
    await _envoyerOuGarder(
      id: 'lecture:$circulaireId',
      entite: entiteLecture,
      rpc: 'marquer_circulaire_lue',
      params: {'p_circulaire': circulaireId},
    );
  }

  @override
  Future<void> importerEvenement(String evenementId, String etablissementId) =>
      _executer(() => _rpc('importer_evenement_reseau', {'p_evenement': evenementId, 'p_etablissement': etablissementId}));

  @override
  Future<void> demanderRetrait({required String reseauId, required String etablissementId, required String motif}) =>
      _executer(() => _rpc('demander_retrait_reseau', {
            'p_reseau': reseauId,
            'p_etablissement': etablissementId,
            'p_motif': motif,
          }));
}

/// Rejoue au serveur les actions du réseau faites sans connexion.
///
/// Panne de réseau : l'erreur remonte, l'entrée reste en file. Refus du
/// serveur (droits retirés, réseau dissous…) : [RejetDefinitif] avec
/// l'explication, montrée dans le bandeau de synchronisation.
class RejeuReseau {
  const RejeuReseau(this._client);

  final SupabaseClient _client;

  Future<void> rejouer(SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      await _client.rpc<dynamic>(p['rpc'] as String, params: (p['params'] as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      final metier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier);
      if (metier || e.code == '42501' || e.code == '23505' || e.code == '23514' || e.code == '23503') {
        final code = metier ? premier : 'ACCES_REFUSE';
        throw RejetDefinitif(code, ErreurReseau(code).messageUtilisateur);
      }
      rethrow;
    }
  }

  /// Ce qui avait été saisi, pour le reconnaître dans les refus.
  static String libelle(SyncEntree entree) {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    final params = (p['params'] as Map?)?.cast<String, dynamic>() ?? const {};
    return switch (entree.entite) {
      SupabaseReseauRepository.entiteDemande => 'Demande de création du réseau « ${params['p_nom'] ?? ''} »',
      SupabaseReseauRepository.entiteCirculaire => 'Circulaire « ${params['p_titre'] ?? ''} »',
      SupabaseReseauRepository.entiteEvenement => 'Calendrier du réseau : « ${params['p_titre'] ?? ''} »',
      SupabaseReseauRepository.entiteInvitation =>
        params['p_accepter'] == true ? 'Acceptation d’une invitation de réseau' : 'Refus d’une invitation de réseau',
      _ => 'Lecture d’une circulaire',
    };
  }
}
