import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/justificatif.dart';

/// Justificatifs d'absence (REG-36), hors connexion d'abord : un dépôt ou
/// une décision faits sans réseau partent au retour, une seule fois
/// (identifiant tiré sur le téléphone, décision idempotente côté serveur).
class JustificatifsRepository {
  JustificatifsRepository(this._client, this._lecture, this._file);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;
  final DriftSyncRepository _file;

  static const entiteDepot = 'justificatif_depot';
  static const entiteDecision = 'justificatif_decision';
  static const entites = [entiteDepot, entiteDecision];

  static const bucket = 'justificatifs-absence';
  static const tailleMaxOctets = 2 * 1024 * 1024;

  /// Dépose ; renvoie vrai s'il est arrivé à l'école, faux s'il attend le
  /// réseau sur le téléphone (photo comprise).
  Future<bool> deposer(Justificatif j, {Uint8List? piece, String extension = 'jpg'}) async {
    if (piece != null && piece.length > tailleMaxOctets) throw const ErreurJustificatif('FICHIER_TROP_LOURD');
    if (j.dateFin.isBefore(j.dateDebut) || j.dateFin.difference(j.dateDebut).inDays > 60) {
      throw const ErreurJustificatif('PERIODE_INVALIDE');
    }
    try {
      await _envoyerDepot(_client, j.versJsonEcriture(), piece, extension);
      return true;
    } catch (e) {
      if (!estErreurReseau(e)) throw _traduire(e);
    }
    await _file.enfiler(SyncEntree(
      id: '$entiteDepot:${j.id}',
      entite: entiteDepot,
      operation: 'insert',
      payload: jsonEncode({
        'ligne': j.versJsonEcriture(),
        if (piece != null) 'piece': base64Encode(piece),
        'extension': extension,
      }),
    ));
    return false;
  }

  /// Justificatifs d'un élève (famille), dépôts en attente compris.
  Future<List<Justificatif>> deFiche(String ficheId) async {
    final serveur = await _lecture.lire(
      type: 'fiche',
      cle: ficheId,
      source: () => _client
          .from('justificatifs_absence')
          .select()
          .eq('fiche_eleve_id', ficheId)
          .order('depose_le', ascending: false),
      decoder: _liste,
    );
    final enAttente = <Justificatif>[];
    for (final e in await _file.entreesEnAttente()) {
      if (e.entite != entiteDepot) continue;
      final p = jsonDecode(e.payload) as Map<String, dynamic>;
      final ligne = (p['ligne'] as Map).cast<String, dynamic>();
      if (ligne['fiche_eleve_id'] != ficheId || serveur.any((s) => s.id == ligne['id'])) continue;
      enAttente.add(Justificatif.depuisJson(ligne).enAttente(avecPiece: p['piece'] != null));
    }
    return [...enAttente, ...serveur];
  }

  /// Justificatifs en attente de décision dans une école (vie scolaire).
  Future<List<Justificatif>> aTraiter(String etablissementId) => _lecture.lire(
        type: 'a_traiter',
        cle: etablissementId,
        source: () => _client
            .from('justificatifs_absence')
            .select('*, fiches_eleves(nom, prenom)')
            .eq('etablissement_id', etablissementId)
            .eq('statut', 'depose')
            .order('depose_le'),
        decoder: _liste,
      );

  /// Décide ; vrai si appliqué, faux si la décision attend le réseau.
  Future<bool> traiter(String id, {required bool accepte, String? motifRefus}) async {
    if (!accepte && (motifRefus == null || motifRefus.trim().isEmpty)) {
      throw const ErreurJustificatif('MOTIF_REFUS_REQUIS');
    }
    final params = {'p_id': id, 'p_accepte': accepte, 'p_motif_refus': motifRefus};
    try {
      await _client.rpc<dynamic>('traiter_justificatif', params: params);
      return true;
    } catch (e) {
      if (!estErreurReseau(e)) throw _traduire(e);
    }
    await _file.enfiler(SyncEntree(
      id: '$entiteDecision:$id',
      entite: entiteDecision,
      operation: 'rpc',
      payload: jsonEncode(params),
    ));
    return false;
  }

  /// Lien temporaire (10 min) vers la pièce, pour la vie scolaire.
  Future<Uri> lienPiece(String chemin) async =>
      Uri.parse(await _client.storage.from(bucket).createSignedUrl(chemin, 600));

  static List<Justificatif> _liste(Object? json) => [
        for (final l in (json as List?) ?? const []) Justificatif.depuisJson((l as Map).cast<String, dynamic>()),
      ];

  static Future<void> _envoyerDepot(
    SupabaseClient client,
    Map<String, dynamic> ligne,
    Uint8List? piece,
    String extension,
  ) async {
    final aEnvoyer = Map<String, dynamic>.of(ligne);
    if (piece != null) {
      final chemin = '${ligne['fiche_eleve_id']}/${ligne['id']}.$extension';
      await client.storage.from(bucket).uploadBinary(
            chemin,
            piece,
            fileOptions: FileOptions(contentType: _typeMime(extension), upsert: true),
          );
      aEnvoyer['piece_chemin'] = chemin;
    }
    try {
      await client.from('justificatifs_absence').insert(aEnvoyer);
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // déjà reçu (rejeu après une coupure)
      rethrow;
    }
  }

  static String _typeMime(String extension) => switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'image/jpeg',
      };

  static ErreurJustificatif _traduire(Object e) {
    if (e is ErreurJustificatif) return e;
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurJustificatif(premier);
      if (e.code == '42501') return const ErreurJustificatif('PERMISSION_REFUSEE');
    }
    if (e is StorageException && e.statusCode == '413') return const ErreurJustificatif('FICHIER_TROP_LOURD');
    return const ErreurJustificatif('ERREUR_SERVEUR');
  }

  /// Rejeu au retour du réseau (moteur de synchronisation).
  static Future<void> rejouer(SupabaseClient client, SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      if (entree.entite == entiteDepot) {
        final piece = p['piece'] == null ? null : base64Decode(p['piece'] as String);
        await _envoyerDepot(client, (p['ligne'] as Map).cast<String, dynamic>(), piece, p['extension'] as String? ?? 'jpg');
      } else {
        await client.rpc<dynamic>('traiter_justificatif', params: p);
      }
    } catch (e) {
      if (estErreurReseau(e)) rethrow;
      final erreur = _traduire(e);
      throw RejetDefinitif(erreur.code, erreur.message);
    }
  }

  static String libelle(SyncEntree entree) =>
      entree.entite == entiteDepot ? 'Justificatif d’absence' : 'Décision sur un justificatif';
}
