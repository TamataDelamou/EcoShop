import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../domain/inscription_en_ligne.dart';

/// Bucket privé des pièces d'inscription (migration `…1544`).
const bucketPiecesInscription = 'pieces-inscription';

/// Accès réseau aux inscriptions en ligne (REG-08). Les lectures passent par
/// [LectureHorsLigne] (dernière réponse resservie sans réseau) ; une panne de
/// réseau devient `HORS_CONNEXION`, que le décorateur hors ligne sait traiter.
class SupabaseInscriptionEnLigneRepository implements InscriptionEnLigneRepository {
  const SupabaseInscriptionEnLigneRepository(this._client, [this._lecture]);

  final SupabaseClient _client;
  final LectureHorsLigne? _lecture;

  static const tailleMaxOctets = 5 * 1024 * 1024;

  static const _colonnesDemande =
      '*, niveaux_educatifs(nom, isced), etablissements(nom, devise_code), pieces_demandes_inscription(code, chemin), '
      'campagnes_inscription(pieces_requises)';

  Future<T> _lire<T>(String type, String cle, Future<Object?> Function() source, T Function(Object?) decoder) {
    final lecture = _lecture;
    if (lecture == null) return source().then(decoder);
    return lecture.lire(type: type, cle: cle, source: source, decoder: decoder);
  }

  String? get _moi => _client.auth.currentUser?.id;

  // -------------------------------------------------------------------------
  // Familles
  // -------------------------------------------------------------------------
  @override
  Future<List<ReinscriptionPossible>> reinscriptionsPossibles() => _executer(() => _lire(
        'reinscriptions_possibles',
        _moi ?? 'anonyme',
        () => _client.rpc<dynamic>('reinscriptions_possibles'),
        (json) => [
          for (final r in (json as List?) ?? const []) ReinscriptionPossible.depuisJson(r as Map<String, dynamic>),
        ],
      ));

  @override
  Future<List<CampagneOuverte>> campagnesOuvertes({String? recherche}) => _executer(() => _lire(
        'campagnes_ouvertes',
        (recherche ?? '').trim().toLowerCase(),
        () => _client.rpc<dynamic>('campagnes_inscription_ouvertes', params: {'p_recherche': recherche}),
        (json) => [
          for (final c in (json as List?) ?? const []) CampagneOuverte.depuisJson(c as Map<String, dynamic>),
        ],
      ));

  @override
  Future<ResultatDemandeInscription> soumettre(SaisieDemandeInscription saisie) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('soumettre_demande_inscription', params: saisie.versParams());
        return ResultatDemandeInscription.depuisJson(json);
      });

  @override
  Future<void> deposerPiece(String demandeId, PieceAEnvoyer piece) => _executer(() async {
        await deposerPieceBrute(_client, demandeId, piece.code, piece.octets, piece.extension);
      });

  /// Envoi d'une pièce (aussi utilisé par le rejeu hors connexion).
  static Future<void> deposerPieceBrute(
    SupabaseClient client,
    String demandeId,
    String code,
    List<int> octets,
    String extension,
  ) async {
    if (octets.length > tailleMaxOctets) throw const ErreurInscriptionEnLigne('FICHIER_TROP_LOURD');
    final piece = PieceAEnvoyer(code: code, octets: octets is Uint8List ? octets : Uint8List.fromList(octets), extension: extension);
    final chemin = '$demandeId/$code-${DateTime.now().millisecondsSinceEpoch}.${piece.extension}';
    await client.storage.from(bucketPiecesInscription).uploadBinary(
          chemin,
          piece.octets,
          fileOptions: FileOptions(contentType: piece.typeMime, upsert: true),
        );
    await client.rpc<dynamic>('deposer_piece_inscription',
        params: {'p_demande': demandeId, 'p_code': code, 'p_chemin': chemin});
  }

  @override
  Future<List<DemandeInscription>> mesDemandes() => _executer(() => _lire(
        'mes_demandes',
        _moi ?? 'anonyme',
        () async {
          final moi = _moi;
          if (moi == null) return const <Object?>[];
          // Mes enfants et ma propre fiche : leurs dossiers me concernent
          // aussi (un parent voit la réinscription faite par l'autre parent).
          final enfants = await _client
              .from('relations_parent_eleve')
              .select('fiche_eleve_id')
              .eq('parent_profile_id', moi)
              .eq('statut', 'confirmee')
              .isFilter('deleted_at', null);
          final maFiche = await _client.from('fiches_eleves').select('id').eq('profile_id', moi);
          final fiches = {
            for (final r in enfants as List) (r as Map<String, dynamic>)['fiche_eleve_id'] as String,
            for (final r in maFiche as List) (r as Map<String, dynamic>)['id'] as String,
          };
          final filtre = fiches.isEmpty
              ? 'demandeur_id.eq.$moi'
              : 'demandeur_id.eq.$moi,fiche_eleve_id.in.(${fiches.join(',')})';
          return _client
              .from('demandes_inscription')
              .select(_colonnesDemande)
              .or(filtre)
              .order('created_at', ascending: false);
        },
        (json) => [
          for (final d in (json as List?) ?? const []) DemandeInscription.depuisJson(d as Map<String, dynamic>),
        ],
      ));

  @override
  Future<void> retirer(String demandeId) =>
      _executer(() => _client.rpc<dynamic>('retirer_demande_inscription', params: {'p_demande': demandeId}));

  // -------------------------------------------------------------------------
  // Direction
  // -------------------------------------------------------------------------
  @override
  Future<CampagneInscription?> campagne(String etablissementId, String anneeScolaireId) => _executer(() => _lire(
        'campagne',
        '$etablissementId/$anneeScolaireId',
        () => _client
            .from('campagnes_inscription')
            .select('*, places_inscription(niveau_id, places)')
            .eq('etablissement_id', etablissementId)
            .eq('annee_scolaire_id', anneeScolaireId)
            .maybeSingle(),
        (json) => json == null ? null : CampagneInscription.depuisJson(json as Map<String, dynamic>),
      ));

  @override
  Future<String?> enregistrerCampagne(CampagneInscription campagne) => _executer(() async {
        final id = await _client.rpc<dynamic>('enregistrer_campagne_inscription', params: campagne.versParams());
        return id as String;
      });

  @override
  Future<List<DemandeInscription>> dossiers(String campagneId) => _executer(() => _lire(
        'dossiers',
        campagneId,
        () => _client
            .from('demandes_inscription')
            .select(_colonnesDemande)
            .eq('campagne_id', campagneId)
            .order('created_at', ascending: true),
        (json) => [
          for (final d in (json as List?) ?? const []) DemandeInscription.depuisJson(d as Map<String, dynamic>),
        ],
      ));

  @override
  Future<TableauCampagne> tableau(String campagneId) => _executer(() => _lire(
        'tableau',
        campagneId,
        () => _client.rpc<dynamic>('tableau_campagne_inscription', params: {'p_campagne': campagneId}),
        (json) => TableauCampagne.depuisJson((json as Map<String, dynamic>?) ?? const {}),
      ));

  @override
  Future<StatutDemandeInscription?> traiter(
    String demandeId,
    DecisionDossier decision, {
    String? motif,
    String? niveauId,
    bool forcer = false,
  }) =>
      _executer(() async {
        final statut = await _client.rpc<dynamic>('traiter_demande_inscription', params: {
          'p_demande': demandeId,
          'p_decision': decision.code,
          'p_motif': motif,
          'p_niveau': niveauId,
          'p_forcer': forcer,
        });
        return StatutDemandeInscription.depuisCode(statut as String?);
      });

  @override
  Future<String?> finaliserAuGuichet(String demandeId, {String? classeId, double? montant, String moyen = 'especes'}) =>
      _executer(() async {
        final id = await _client.rpc<dynamic>('finaliser_inscription_guichet', params: {
          'p_demande': demandeId,
          'p_classe': classeId,
          'p_montant': montant,
          'p_moyen': moyen,
        });
        return id as String;
      });

  @override
  Future<Uri> lienPiece(String chemin) => _executer(() async {
        final url = await _client.storage.from(bucketPiecesInscription).createSignedUrl(chemin, 600);
        return Uri.parse(url);
      });

  @override
  Future<Map<String, String>> nomsNiveaux(List<String> niveauIds) => _executer(() => _lire(
        'noms_niveaux',
        (List.of(niveauIds)..sort()).join(','),
        () async {
          if (niveauIds.isEmpty) return const <Object?>[];
          return _client.from('niveaux_educatifs').select('id, nom, grade_level_normalise').inFilter('id', niveauIds);
        },
        (json) {
          final lignes = [for (final l in (json as List?) ?? const []) l as Map<String, dynamic>]
            ..sort((a, b) => ((a['grade_level_normalise'] as num?) ?? 0).compareTo((b['grade_level_normalise'] as num?) ?? 0));
          return {for (final l in lignes) l['id'] as String: l['nom'] as String? ?? ''};
        },
      ));

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ErreurInscriptionEnLigne {
      rethrow;
    } on PostgrestException catch (e) {
      throw ErreurInscriptionEnLigne(codeMetier(e.message) ?? (e.code == '42501' ? 'ACCES_REFUSE' : 'ERREUR_SERVEUR'));
    } on StorageException catch (e) {
      throw ErreurInscriptionEnLigne(e.statusCode == '403' ? 'ACCES_REFUSE' : 'ERREUR_SERVEUR');
    } catch (e) {
      if (estErreurReseau(e)) throw const ErreurInscriptionEnLigne('HORS_CONNEXION');
      rethrow;
    }
  }

  /// Code métier en tête du message d'erreur du serveur, s'il y en a un.
  static String? codeMetier(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier) ? premier : null;
  }
}
