import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import 'referentiel_back_office.dart';

class ErreurReferentiel implements Exception {
  const ErreurReferentiel(this.code);

  final String code;

  String get message => switch (code) {
        'HORS_LIGNE' => 'Pas de réseau : cette action se fait en ligne.',
        'PERMISSION_REFUSEE' => 'Réservé à l’Administrateur de contenu ou à GSG.',
        'CODE_PAYS_INVALIDE' => 'Code pays : deux lettres (GN, SN, CI…).',
        'DEVISE_INVALIDE' => 'Devise : trois lettres (XOF, GNF, NGN…).',
        'NOM_REQUIS' => 'Le code et le nom sont requis.',
        'ISCED_INVALIDE' => 'Niveau ISCED : le minimum dépasse le maximum.',
        'CODE_DEJA_UTILISE' => 'Ce code existe déjà dans ce pays.',
        'CODE_OU_RANG_DEJA_UTILISE' => 'Ce code ou ce rang est déjà pris par un autre niveau du pays.',
        'NIVEAU_UTILISE' => 'Des classes utilisent ce niveau : son rang et son cycle ne changent plus.',
        'ELEMENT_UTILISE' => 'Des données en dépendent (niveaux, classes, programmes ou épreuves) : suppression impossible.',
        'ELEMENT_PUBLIE' => 'Déjà publié : il ne se supprime plus.',
        'QUESTIONS_EXISTANTES' => 'Des questions de la banque en dépendent : suppression impossible.',
        'PROGRAMME_EXISTANT' => 'Ce niveau a déjà un programme national (pour cette série).',
        'MATIERE_REQUISE' => 'Ajoutez au moins une matière avant de publier.',
        'NIVEAU_NON_PUBLIE' => 'Publiez d’abord le pays (ou ce niveau).',
        'REFERENTIEL_INCOMPLET' => 'Des points bloquants restent dans le contrôle.',
        'CYCLE_INTROUVABLE' || 'NIVEAU_INTROUVABLE' || 'PAYS_INTROUVABLE' || 'PROGRAMME_INTROUVABLE' =>
          'Élément introuvable : actualisez.',
        _ => 'Action impossible pour le moment. Réessayez.',
      };

  @override
  String toString() => code;
}

/// Écritures du back-office : idempotentes (identifiants créés sur
/// l'appareil), gardées sans réseau et envoyées au retour. Publication et
/// suppression se font en ligne (elles dépendent de l'état du serveur).
class ReferentielBackOfficeRepository {
  ReferentielBackOfficeRepository(this._client, this._lecture, this._file);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;
  final DriftSyncRepository _file;

  static const entite = 'referentiel_back_office';
  static const entites = [entite];

  static ErreurReferentiel traduire(Object e) {
    if (e is ErreurReferentiel) return e;
    if (estErreurReseau(e)) return const ErreurReferentiel('HORS_LIGNE');
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurReferentiel(premier);
      if (e.code == '42501') return const ErreurReferentiel('PERMISSION_REFUSEE');
    }
    return const ErreurReferentiel('ERREUR_SERVEUR');
  }

  Future<List<PaysBackOffice>> pays() => _lire(
        type: 'pays_back_office',
        cle: 'tous',
        source: () => _client.rpc<dynamic>('pays_back_office'),
        decoder: PaysBackOffice.liste,
      );

  Future<ReferentielPays> referentiel(String code) => _lire(
        type: 'referentiel_back_office',
        cle: code,
        source: () => _client.rpc<dynamic>('referentiel_back_office', params: {'p_pays': code}),
        decoder: (j) => ReferentielPays.depuisJson(((j as Map?) ?? const {}).cast<String, dynamic>()),
      );

  Future<T> _lire<T>({
    required String type,
    required String cle,
    required Future<Object?> Function() source,
    required T Function(Object?) decoder,
  }) async {
    try {
      return await _lecture.lire(type: type, cle: cle, source: source, decoder: decoder);
    } catch (e) {
      throw traduire(e);
    }
  }

  /// Vrai si le serveur a reçu ; faux si gardé pour le retour du réseau.
  Future<bool> _ecrire(String id, String fonction, Map<String, Object?> params) async {
    try {
      await _client.rpc<dynamic>(fonction, params: params);
      return true;
    } catch (e) {
      if (!estErreurReseau(e)) throw traduire(e);
    }
    await _file.enfiler(SyncEntree(
      id: '$entite:$fonction:$id',
      entite: entite,
      operation: fonction,
      payload: jsonEncode(params),
    ));
    return false;
  }

  Future<bool> enregistrerPays(FichePays p) => _ecrire(p.code, 'enregistrer_pays_referentiel', {
        'p_code': p.code,
        'p_nom': p.nom,
        'p_type_systeme': p.typeSysteme,
        'p_langue': p.langue,
        'p_organisme': p.organisme,
        'p_devise': p.devise,
        'p_zone': p.zone.code,
        'p_sources': p.sources,
        'p_points_a_verifier': p.pointsAVerifier,
      });

  Future<bool> enregistrerCycle(String pays, CycleBackOffice c) => _ecrire(c.id, 'enregistrer_cycle_referentiel', {
        'p_id': c.id,
        'p_pays': pays,
        'p_code': c.code,
        'p_nom': c.nom,
        'p_ordre': c.ordre,
        'p_isced_min': c.iscedMin,
        'p_isced_max': c.iscedMax,
        'p_age_min': c.ageMin,
        'p_age_max': c.ageMax,
        'p_duree': c.duree,
      });

  Future<bool> enregistrerNiveau(NiveauBackOffice n) => _ecrire(n.id, 'enregistrer_niveau_referentiel', {
        'p_id': n.id,
        'p_cycle': n.cycleId,
        'p_code': n.code,
        'p_nom': n.nom,
        'p_grade': n.grade,
        'p_isced': n.isced,
        'p_ordre': n.ordre,
        'p_examinateur': n.examinateur,
      });

  Future<bool> enregistrerExamen(String pays, ExamenBackOffice e) => _ecrire(e.id, 'enregistrer_examen_referentiel', {
        'p_id': e.id,
        'p_pays': pays,
        'p_cycle': e.cycleId,
        'p_code': e.code,
        'p_nom': e.nom,
        'p_organisme': e.organisme,
        'p_mois': e.mois,
      });

  Future<bool> enregistrerProgramme({required String id, required String niveauId, String? serieId, String? nom, String? annee}) =>
      _ecrire(id, 'enregistrer_programme_national', {
        'p_id': id,
        'p_niveau': niveauId,
        'p_filiere': serieId,
        'p_nom': nom,
        'p_annee': annee,
      });

  Future<bool> enregistrerMatiere(String programmeId, MatiereNationale m) => _ecrire(m.id, 'enregistrer_matiere_nationale', {
        'p_id': m.id,
        'p_programme': programmeId,
        'p_code': m.code,
        'p_nom': m.nom,
        'p_ordre': m.ordre,
        'p_nature': m.nature,
      });

  Future<void> _enLigne(String fonction, Map<String, Object?> params) async {
    try {
      await _client.rpc<dynamic>(fonction, params: params);
    } catch (e) {
      throw traduire(e);
    }
  }

  Future<void> publierProgramme(String id) => _enLigne('publier_programme_national', {'p_programme': id});

  Future<void> publierPays(String code) => _enLigne('publier_pays_referentiel', {'p_pays': code});

  Future<void> supprimer(String type, String id) => _enLigne('supprimer_element_referentiel', {'p_type': type, 'p_id': id});

  static Future<void> rejouer(SupabaseClient client, SyncEntree entree) async {
    try {
      await client.rpc<dynamic>(entree.operation, params: jsonDecode(entree.payload) as Map<String, dynamic>);
    } catch (e) {
      if (estErreurReseau(e)) rethrow;
      final err = traduire(e);
      throw RejetDefinitif(err.code, err.message);
    }
  }

  static String libelle(SyncEntree entree) => 'Référentiel (back-office)';
}
