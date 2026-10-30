import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/question.dart';

/// Banque de questions (REG-37 lot R1), côté Administrateur de contenu.
///
/// Hors connexion : les listes se lisent depuis la copie de l'appareil ; un
/// brouillon enregistré sans réseau part au retour (identifiant tiré sur
/// l'appareil, jamais créé deux fois). Le circuit (soumettre, valider,
/// publier) et la structure de la matière se font en ligne.
class BanqueQuestionsRepository {
  BanqueQuestionsRepository(this._client, this._lecture, this._file);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;
  final DriftSyncRepository _file;

  static const entiteBrouillon = 'question_brouillon';
  static const entites = [entiteBrouillon];
  static const bucket = 'questions-medias';
  static const tailleMaxOctets = 3 * 1024 * 1024;

  static const _selectQuestion = '*, questions_versions(*), signalements_questions(traite)';

  // ------------------------------------------------------------- structure

  Future<StructureMatiere> structure(String matiereId) => _lecture.lire(
        type: 'structure',
        cle: matiereId,
        source: () async => {
          'chapitres': await _client
              .from('chapitres_matiere')
              .select('*, lecons_chapitre(*)')
              .eq('matiere_id', matiereId)
              .order('ordre'),
          'competences': await _client.from('competences_matiere').select().eq('matiere_id', matiereId).order('code'),
        },
        decoder: (json) {
          final j = (json as Map?)?.cast<String, dynamic>() ?? const {};
          return StructureMatiere(
            chapitres: [
              for (final c in (j['chapitres'] as List?) ?? const [])
                ChapitreMatiere.depuisJson((c as Map).cast<String, dynamic>()),
            ],
            competences: [
              for (final c in (j['competences'] as List?) ?? const [])
                Competence.depuisJson((c as Map).cast<String, dynamic>()),
            ],
          );
        },
      );

  Future<void> ajouterChapitre(String matiereId, String titre, int ordre) => _ecrire(
        () => _client.from('chapitres_matiere').insert({'matiere_id': matiereId, 'titre': titre.trim(), 'ordre': ordre}),
      );

  Future<void> ajouterLecon(String chapitreId, String titre, int ordre) => _ecrire(
        () => _client.from('lecons_chapitre').insert({'chapitre_id': chapitreId, 'titre': titre.trim(), 'ordre': ordre}),
      );

  Future<void> ajouterCompetence(String matiereId, String code, String libelle) => _ecrire(
        () => _client
            .from('competences_matiere')
            .insert({'matiere_id': matiereId, 'code': code.trim().toUpperCase(), 'libelle': libelle.trim()}),
      );

  // ------------------------------------------------------------- questions

  /// Questions d'une matière, brouillons gardés sur l'appareil en tête.
  Future<List<Question>> questions(String matiereId) async {
    final serveur = await _lecture.lire(
      type: 'questions',
      cle: matiereId,
      source: () =>
          _client.from('questions').select(_selectQuestion).eq('matiere_id', matiereId).order('updated_at', ascending: false),
      decoder: _liste,
    );
    final enAttente = await brouillonsEnAttente();
    final ids = {for (final q in enAttente) q.id};
    return [
      for (final q in enAttente)
        if (q.matiereId == matiereId) q,
      for (final q in serveur)
        if (!ids.contains(q.id)) q,
    ];
  }

  /// Questions à valider ou à publier, toutes matières.
  Future<List<Question>> aTraiter() => _lecture.lire(
        type: 'a_traiter',
        cle: 'toutes',
        source: () => _client
            .from('questions')
            .select(_selectQuestion)
            .inFilter('statut', ['revision', 'validee'])
            .order('updated_at'),
        decoder: _liste,
      );

  /// Questions suspendues ou signalées.
  Future<List<Question>> signalees() async {
    final liste = await _lecture.lire(
      type: 'signalees',
      cle: 'toutes',
      source: () => _client
          .from('questions')
          .select('*, questions_versions(*), signalements_questions!inner(traite)')
          .eq('signalements_questions.traite', false)
          .order('updated_at', ascending: false),
      decoder: _liste,
    );
    return [...liste]..sort((a, b) => (b.suspendue ? 1 : 0).compareTo(a.suspendue ? 1 : 0));
  }

  /// Enregistre ; vrai si reçu par le serveur, faux si gardé sur l'appareil.
  Future<bool> enregistrer(String id, String matiereId, ContenuQuestion c, {bool petitesClasses = false}) async {
    final erreur = c.erreur(petitesClasses: petitesClasses);
    if (erreur != null) throw ErreurBanque(erreur);
    final params = {'p_id': id, 'p_matiere': matiereId, ...c.versParametres()};
    try {
      await _client.rpc<dynamic>('enregistrer_question', params: params);
      return true;
    } catch (e) {
      if (!estErreurReseau(e)) throw traduire(e);
    }
    // Un seul brouillon en attente par question : le plus récent remplace.
    await _file.enfiler(SyncEntree(
      id: '$entiteBrouillon:$id',
      entite: entiteBrouillon,
      operation: 'rpc',
      payload: jsonEncode(params),
    ));
    return false;
  }

  /// soumettre · renvoyer (remarque requise) · valider · publier.
  Future<void> changerStatut(String id, String action, {String? remarque}) => _ecrire(
        () => _client.rpc<dynamic>('changer_statut_question', params: {
          'p_id': id,
          'p_action': action,
          'p_remarque': remarque,
        }),
      );

  Future<void> retablir(String id) => _ecrire(() => _client.rpc<dynamic>('retablir_question', params: {'p_question': id}));

  /// Envoie une image, un son ou un document ; renvoie son chemin.
  Future<String> envoyerMedia(String questionId, Uint8List octets, String extension) async {
    if (octets.length > tailleMaxOctets) throw const ErreurBanque('FICHIER_TROP_LOURD');
    final chemin = '$questionId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _ecrire(() => _client.storage.from(bucket).uploadBinary(
          chemin,
          octets,
          fileOptions: FileOptions(contentType: typeMime(extension), upsert: true),
        ));
    return chemin;
  }

  Future<Uri> lienMedia(String chemin) async =>
      Uri.parse(await _client.storage.from(bucket).createSignedUrl(chemin, 3600));

  /// Brouillons gardés sur l'appareil, pas encore reçus.
  Future<List<Question>> brouillonsEnAttente() async => [
        for (final e in await _file.entreesEnAttente())
          if (e.entite == entiteBrouillon) questionDepuisParametres(jsonDecode(e.payload) as Map<String, dynamic>),
      ];

  // ------------------------------------------------------------- utilitaires

  static Question questionDepuisParametres(Map<String, dynamic> p) => Question(
        id: p['p_id'] as String,
        matiereId: p['p_matiere'] as String,
        statut: StatutContenu.brouillon,
        versionTravail: 0,
        enAttenteEnvoi: true,
        travail: ContenuQuestion.depuisJson({
          'type': p['p_type'],
          'difficulte': p['p_difficulte'],
          'competence_id': p['p_competence'],
          'chapitre_id': p['p_chapitre'],
          'lecon_id': p['p_lecon'],
          'enonce': p['p_enonce'],
          'contenu': p['p_contenu'],
          'reponse': p['p_reponse'],
          'explication': p['p_explication'],
          'temps_recommande_s': p['p_temps_recommande_s'],
          'source': p['p_source'],
          'tags': p['p_tags'],
          'media_chemin': p['p_media_chemin'],
          'media_type': p['p_media_type'],
        }),
      );

  static String typeMime(String extension) => switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'mp3' => 'audio/mpeg',
        'm4a' => 'audio/mp4',
        'pdf' => 'application/pdf',
        _ => 'image/jpeg',
      };

  static List<Question> _liste(Object? json) => [
        for (final l in (json as List?) ?? const []) Question.depuisJson((l as Map).cast<String, dynamic>()),
      ];

  Future<void> _ecrire(Future<Object?> Function() action) async {
    try {
      await action();
    } catch (e) {
      throw traduire(e);
    }
  }

  static ErreurBanque traduire(Object e) {
    if (e is ErreurBanque) return e;
    if (estErreurReseau(e)) return const ErreurBanque('HORS_LIGNE');
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurBanque(premier);
      if (e.code == '42501') return const ErreurBanque('PERMISSION_REFUSEE');
    }
    if (e is StorageException && e.statusCode == '413') return const ErreurBanque('FICHIER_TROP_LOURD');
    return const ErreurBanque('ERREUR_SERVEUR');
  }

  /// Rejeu d'un brouillon au retour du réseau.
  static Future<void> rejouer(SupabaseClient client, SyncEntree entree) async {
    try {
      await client.rpc<dynamic>('enregistrer_question', params: jsonDecode(entree.payload) as Map<String, dynamic>);
    } catch (e) {
      if (estErreurReseau(e)) rethrow;
      final erreur = traduire(e);
      throw RejetDefinitif(erreur.code, erreur.message);
    }
  }

  static String libelle(SyncEntree entree) => 'Question de la banque (brouillon)';
}
