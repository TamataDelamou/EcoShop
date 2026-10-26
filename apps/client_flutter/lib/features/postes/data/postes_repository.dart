import 'package:supabase_flutter/supabase_flutter.dart';

import '../../appareil/data/appareil_repository.dart' show codeErreurServeur;

/// Postes du personnel (REG-22, partie C).
class Poste {
  const Poste({
    required this.id,
    required this.nom,
    required this.codes,
    required this.membres,
    required this.actif,
    this.modeleCode,
    this.description,
  });

  final String id;
  final String nom;
  final String? modeleCode;
  final String? description;
  final List<String> codes;
  final int membres;
  final bool actif;

  factory Poste.depuisJson(Map<String, dynamic> j) => Poste(
    id: j['id'] as String,
    nom: j['nom'] as String,
    modeleCode: j['modele_code'] as String?,
    description: j['description'] as String?,
    codes: [for (final c in (j['codes'] as List? ?? const [])) c as String],
    membres: (j['membres'] as num?)?.toInt() ?? 0,
    actif: j['actif'] != false,
  );
}

class ModelePoste {
  const ModelePoste({required this.code, required this.nom, required this.description, required this.role, required this.codes});

  final String code;
  final String nom;
  final String description;
  final String role;
  final List<String> codes;

  factory ModelePoste.depuisJson(Map<String, dynamic> j) => ModelePoste(
    code: j['code'] as String,
    nom: j['nom'] as String,
    description: j['description'] as String,
    role: j['role'] as String,
    codes: [for (final c in (j['codes'] as List? ?? const [])) c as String],
  );
}

class DroitCatalogue {
  const DroitCatalogue({required this.code, required this.domaine, required this.libelle, this.description});

  final String code;
  final String domaine;
  final String libelle;
  final String? description;

  factory DroitCatalogue.depuisJson(Map<String, dynamic> j) => DroitCatalogue(
    code: j['code'] as String,
    domaine: j['domaine'] as String,
    libelle: j['libelle'] as String,
    description: j['description'] as String?,
  );
}

class MembrePersonnel {
  const MembrePersonnel({required this.profileId, required this.nomComplet, required this.role, this.posteId, this.poste});

  final String profileId;
  final String nomComplet;
  final String role;
  final String? posteId;
  final String? poste;

  factory MembrePersonnel.depuisJson(Map<String, dynamic> j) => MembrePersonnel(
    profileId: j['profile_id'] as String,
    nomComplet: (j['nom_complet'] as String?)?.trim().isNotEmpty == true ? j['nom_complet'] as String : 'Sans nom',
    role: j['role'] as String,
    posteId: j['poste_id'] as String?,
    poste: j['poste'] as String?,
  );
}

class ErreurPostes implements Exception {
  const ErreurPostes(this.code);
  final String code;

  String get message => switch (code) {
    'CUMUL_INTERDIT' => 'Un même poste ne peut pas encaisser et tenir ou valider la comptabilité (séparation des tâches).',
    'PERMISSION_REFUSEE' => 'Réservé à la direction de l’école.',
    'NOM_OBLIGATOIRE' => 'Donnez un nom au poste.',
    'POSTE_OCCUPE' => 'Des personnes occupent ce poste : changez d’abord leur poste.',
    'POSTE_OBLIGATOIRE' => 'Le personnel a toujours un poste : ses droits en dépendent.',
    'MODIFICATION_SOI_MEME' => 'Vous ne pouvez pas changer votre propre rôle.',
    'DROIT_INCONNU' => 'Un des droits n’existe plus. Actualisez la liste.',
    _ => 'Le serveur n’a pas pu traiter la demande. Réessayez.',
  };

  @override
  String toString() => message;
}

abstract interface class PostesRepository {
  Future<List<Poste>> postes(String etablissementId);
  Future<List<ModelePoste>> modeles();
  Future<List<DroitCatalogue>> catalogue();
  Future<String> creerPoste({required String etablissementId, String? modele, required String nom, required List<String> codes});
  Future<void> modifierPoste({required String posteId, required String nom, required List<String> codes, bool actif = true});
  Future<List<MembrePersonnel>> personnel(String etablissementId);
  Future<void> modifierMembre({required String etablissementId, required String compteId, required String role, String? posteId});
  Future<Set<String>> mesPermissions(String etablissementId);
}

class SupabasePostesRepository implements PostesRepository {
  const SupabasePostesRepository(this._client);

  final SupabaseClient _client;

  List<Map<String, dynamic>> _lignes(Object? r) => [for (final l in (r as List)) (l as Map).cast<String, dynamic>()];

  @override
  Future<List<Poste>> postes(String etablissementId) => _executer(() async =>
      [for (final l in _lignes(await _client.rpc<dynamic>('postes_etablissement', params: {'p_etablissement': etablissementId}))) Poste.depuisJson(l)]);

  @override
  Future<List<ModelePoste>> modeles() => _executer(() async =>
      [for (final l in _lignes(await _client.from('modeles_postes').select().order('ordre'))) ModelePoste.depuisJson(l)]);

  @override
  Future<List<DroitCatalogue>> catalogue() => _executer(() async =>
      [for (final l in _lignes(await _client.rpc<dynamic>('catalogue_permissions'))) DroitCatalogue.depuisJson(l)]);

  @override
  Future<String> creerPoste({required String etablissementId, String? modele, required String nom, required List<String> codes}) =>
      _executer(() async => (await _client.rpc<dynamic>('creer_poste', params: {
            'p_etablissement': etablissementId,
            'p_modele': modele,
            'p_nom': nom,
            'p_codes': codes,
          })) as String);

  @override
  Future<void> modifierPoste({required String posteId, required String nom, required List<String> codes, bool actif = true}) =>
      _executer(() => _client.rpc<dynamic>('modifier_poste', params: {'p_poste': posteId, 'p_nom': nom, 'p_codes': codes, 'p_actif': actif}));

  @override
  Future<List<MembrePersonnel>> personnel(String etablissementId) => _executer(() async =>
      [for (final l in _lignes(await _client.rpc<dynamic>('membres_personnel', params: {'p_etablissement': etablissementId}))) MembrePersonnel.depuisJson(l)]);

  @override
  Future<void> modifierMembre({required String etablissementId, required String compteId, required String role, String? posteId}) =>
      _executer(() => _client.rpc<dynamic>('modifier_membre', params: {
            'p_etablissement': etablissementId,
            'p_compte': compteId,
            'p_role': role,
            'p_poste': posteId,
          }));

  @override
  Future<Set<String>> mesPermissions(String etablissementId) => _executer(() async {
    final r = await _client.rpc<dynamic>('mes_permissions', params: {'p_etablissement': etablissementId});
    return {for (final c in (r as List)) c is Map ? c.values.first as String : c as String};
  });

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurPostes(codeErreurServeur(e.message));
    }
  }
}
