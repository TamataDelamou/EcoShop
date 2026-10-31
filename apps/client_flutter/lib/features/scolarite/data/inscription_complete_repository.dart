import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../domain/scolarite_repository.dart';

/// Bucket privé des photos d'élèves (migration 20260906001593).
const bucketPhotosEleves = 'photos-eleves';

/// Renseignements d'une inscription complète (REG-39). Seuls [nom],
/// [prenom] et [dateNaissance] sont obligatoires.
class RenseignementsEleve {
  const RenseignementsEleve({
    required this.nom,
    required this.prenom,
    required this.dateNaissance,
    this.sexe,
    this.lieuNaissance,
    this.nationalite,
    this.telephoneEleve,
    this.nomPere,
    this.telephonePere,
    this.professionPere,
    this.nomMere,
    this.telephoneMere,
    this.professionMere,
    this.tuteurLien,
    this.tuteurNom,
    this.tuteurTelephone,
    this.situationHandicap = false,
    this.handicapPrecision,
    this.quartier,
    this.ecoleOrigine,
    this.matriculeNational,
  });

  final String nom;
  final String prenom;
  final DateTime dateNaissance;
  final String? sexe;
  final String? lieuNaissance;
  final String? nationalite;
  final String? telephoneEleve;
  final String? nomPere;
  final String? telephonePere;
  final String? professionPere;
  final String? nomMere;
  final String? telephoneMere;
  final String? professionMere;

  /// `pere`, `mere` ou `autre`.
  final String? tuteurLien;
  final String? tuteurNom;
  final String? tuteurTelephone;
  final bool situationHandicap;
  final String? handicapPrecision;
  final String? quartier;
  final String? ecoleOrigine;

  /// Matricule attribué par l'État (Guinée).
  final String? matriculeNational;

  Map<String, dynamic> versJson() {
    String? net(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    String d(int v) => v.toString().padLeft(2, '0');
    return {
      'nom': nom.trim(),
      'prenom': prenom.trim(),
      'date_naissance': '${dateNaissance.year}-${d(dateNaissance.month)}-${d(dateNaissance.day)}',
      'sexe': sexe,
      'lieu_naissance': net(lieuNaissance),
      'nationalite': net(nationalite),
      'telephone_eleve': net(telephoneEleve),
      'nom_pere': net(nomPere),
      'telephone_pere': net(telephonePere),
      'profession_pere': net(professionPere),
      'nom_mere': net(nomMere),
      'telephone_mere': net(telephoneMere),
      'profession_mere': net(professionMere),
      'tuteur_lien': tuteurLien,
      'tuteur_nom': net(tuteurNom),
      'tuteur_telephone': net(tuteurTelephone),
      'situation_handicap': situationHandicap,
      'handicap_precision': situationHandicap ? net(handicapPrecision) : null,
      'quartier': net(quartier),
      'ecole_origine': net(ecoleOrigine),
      'matricule_national': net(matriculeNational)?.toUpperCase(),
    }..removeWhere((_, v) => v == null);
  }
}

/// Inscription complète en une transaction, puis photo (REG-39).
class InscriptionCompleteRepository {
  const InscriptionCompleteRepository(this._client);

  final SupabaseClient _client;

  /// 512 Ko (limite du bucket) : la photo est réduite avant l'envoi.
  static const tailleMaxPhoto = 512 * 1024;

  Future<String> inscrire({
    required String etablissementId,
    required String classeId,
    required String anneeScolaireId,
    required RenseignementsEleve eleve,
  }) async {
    try {
      final id = await _client.rpc<dynamic>('creer_inscription_eleve_complete', params: {
        'p_etablissement': etablissementId,
        'p_classe_id': classeId,
        'p_annee_scolaire_id': anneeScolaireId,
        'p_eleve': eleve.versJson(),
      });
      return id as String;
    } on PostgrestException catch (e) {
      throw ErreurScolarite(_code(e.message));
    }
  }

  /// Dépose la photo dans le dossier de l'école et l'enregistre sur la fiche.
  /// Une photo qui échoue n'annule pas l'inscription : elle s'ajoute plus tard
  /// depuis la fiche.
  Future<void> definirPhoto({
    required String etablissementId,
    required String ficheId,
    required Uint8List octets,
  }) async {
    if (octets.length > tailleMaxPhoto) throw const ErreurScolarite('PHOTO_TROP_LOURDE');
    final chemin = '$etablissementId/$ficheId/photo-${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await _client.storage.from(bucketPhotosEleves).uploadBinary(
            chemin,
            octets,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      await _client.rpc<dynamic>('definir_photo_eleve', params: {'p_fiche': ficheId, 'p_chemin': chemin});
    } on StorageException {
      throw const ErreurScolarite('PHOTO_NON_ENVOYEE');
    } on PostgrestException catch (e) {
      throw ErreurScolarite(_code(e.message));
    }
  }

  /// Octets d'une photo d'élève.
  Future<Uint8List> telechargerPhoto(String chemin) => _client.storage.from(bucketPhotosEleves).download(chemin);

  static String _code(String message) {
    for (final code in const [
      'PERMISSION_REFUSEE',
      'CLASSE_AUTRE_ETABLISSEMENT',
      'CHAMPS_OBLIGATOIRES',
      'FICHE_INTROUVABLE',
      'PHOTO_HORS_DOSSIER',
    ]) {
      if (message.contains(code)) return code;
    }
    return 'INCONNU';
  }
}

final inscriptionCompleteRepositoryProvider = Provider<InscriptionCompleteRepository>(
  (ref) => InscriptionCompleteRepository(ref.watch(supabaseClientProvider)),
);
