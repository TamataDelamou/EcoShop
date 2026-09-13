import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/appreciation.dart';
import '../domain/bulletin.dart';
import '../domain/classement_eleve.dart';
import '../domain/enums_notes.dart';
import '../domain/evaluation.dart';
import '../domain/note.dart';
import '../domain/notes_repository.dart';

/// Implémentation Supabase du port [NotesRepository] (M6).
///
/// Les moyennes ne sont **jamais** calculées ici : [moyenneEleve] et
/// [moyenneClasse] se contentent de relayer les RPC serveur
/// `calculer_moyenne_*` (contrat M06 §5) — voir la docstring du port.
class SupabaseNotesRepository implements NotesRepository {
  const SupabaseNotesRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Evaluation>> evaluationsDeClasse(String classeId, {String? periodeId}) {
    return _executer(() async {
      var requete = _client
          .from('evaluations')
          .select('*, programmes_matieres(nom)')
          .eq('classe_id', classeId)
          .isFilter('deleted_at', null);
      if (periodeId != null) {
        requete = requete.eq('periode_id', periodeId);
      }
      final lignes = await requete.order('date_evaluation', ascending: false);
      return lignes.map((l) => Evaluation.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<Note>> notesDeEvaluation(String evaluationId) {
    return _executer(() async {
      final lignes = await _client
          .from('notes')
          .select('*, fiches_eleves(prenom, nom)')
          .eq('evaluation_id', evaluationId)
          .isFilter('deleted_at', null);
      return lignes.map((l) => Note.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<Note>> notesDeFiche(String ficheEleveId, {String? periodeId}) {
    return _executer(() async {
      var requete = _client
          .from('notes')
          .select('*, evaluations(*, programmes_matieres(nom))')
          .eq('fiche_eleve_id', ficheEleveId)
          .isFilter('deleted_at', null);
      if (periodeId != null) {
        requete = requete.eq('evaluations.periode_id', periodeId);
      }
      final lignes = await requete;
      return lignes.map((l) => Note.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<double?> moyenneEleve(
    String ficheEleveId, {
    String? programmeMatiereId,
    String? periodeId,
  }) {
    return _executer(() async {
      final resultat = await _client.rpc<num?>(
        'calculer_moyenne_eleve',
        params: {
          'p_fiche': ficheEleveId,
          'p_matiere': programmeMatiereId,
          'p_periode': periodeId,
        },
      );
      return resultat?.toDouble();
    });
  }

  @override
  Future<double?> moyenneClasse(
    String classeId, {
    String? programmeMatiereId,
    String? periodeId,
  }) {
    return _executer(() async {
      final resultat = await _client.rpc<num?>(
        'calculer_moyenne_classe',
        params: {
          'p_classe': classeId,
          'p_matiere': programmeMatiereId,
          'p_periode': periodeId,
        },
      );
      return resultat?.toDouble();
    });
  }

  @override
  Future<List<Appreciation>> appreciationsDeFiche(String ficheEleveId, {String? periodeId}) {
    return _executer(() async {
      var requete = _client
          .from('appreciations')
          .select('*, programmes_matieres(nom)')
          .eq('fiche_eleve_id', ficheEleveId)
          .isFilter('deleted_at', null);
      if (periodeId != null) {
        requete = requete.eq('periode_id', periodeId);
      }
      final lignes = await requete;
      return lignes.map((l) => Appreciation.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<Bulletin>> bulletinsDeFiche(String ficheEleveId) {
    return _executer(() async {
      final lignes = await _client
          .from('bulletins')
          .select()
          .eq('fiche_eleve_id', ficheEleveId)
          .isFilter('deleted_at', null)
          .order('genere_le', ascending: false);
      return lignes.map((l) => Bulletin.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<Evaluation> creerEvaluation(Evaluation evaluation) {
    return _executer(() async {
      final payload = evaluation.versJsonCache()
        ..remove('id') // laisser gen_random_uuid() attribuer l'identifiant
        ..remove('nom_matiere');
      final ligne = await _client.from('evaluations').insert(payload).select().single();
      return Evaluation.depuisJson(ligne);
    });
  }

  @override
  Future<void> publierEvaluation(String evaluationId) {
    return _executer(() async {
      await _client.from('evaluations').update({
        'statut': 'publiee',
        'publie_le': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', evaluationId);
    });
  }

  @override
  Future<List<ClassementEleve>> classerElevesClasse(
    String classeId, {
    String? programmeMatiereId,
    String? periodeId,
  }) {
    return _executer(() async {
      final lignes = await _client.rpc<List<dynamic>>(
        'classer_eleves_classe',
        params: {
          'p_classe': classeId,
          'p_matiere': programmeMatiereId,
          'p_periode': periodeId,
        },
      );
      return lignes
          .map((l) => ClassementEleve.depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    });
  }

  /// Publie directement chaque bulletin généré (`statut = 'publie'`) : la
  /// source (`ecoshop_flutter`) n'a jamais eu de cycle brouillon/publication
  /// séparé pour les bulletins — un bulletin y est visible dès sa génération.
  /// Le cycle brouillon/aperçu/publication du chapitre 18 est hors périmètre
  /// D5 (différé) ; générer en `brouillon` ici rendrait le bulletin
  /// invisible pour l'élève/parent (`bulletin_visible` exige `publie`) sans
  /// qu'aucune action de publication n'existe pour l'en sortir — une
  /// régression par rapport à la source, pas un choix par défaut neutre.
  ///
  /// N'effectue aucun calcul : [classerElevesClasse] (RPC serveur) a déjà
  /// produit moyenne et rang, recopiés tels quels dans `contenu`.
  @override
  Future<List<Bulletin>> genererBulletinsClasse({
    required String classeId,
    required String etablissementId,
    required String anneeScolaireId,
    String? periodeId,
    TypeBulletin type = TypeBulletin.trimestriel,
  }) {
    return _executer(() async {
      final classement = await classerElevesClasse(classeId, periodeId: periodeId);
      if (classement.isEmpty) return const <Bulletin>[];

      final effectif = classement.length;
      final maintenant = DateTime.now().toUtc().toIso8601String();
      final lignes = classement
          .map((e) => {
                'etablissement_id': etablissementId,
                'annee_scolaire_id': anneeScolaireId,
                'periode_id': periodeId,
                'classe_id': classeId,
                'fiche_eleve_id': e.ficheEleveId,
                'type': type.code,
                'statut': StatutBulletin.publie.code,
                'contenu': {
                  'moyenne_generale': e.moyenne,
                  'rang': e.rang,
                  'effectif_classe': effectif,
                },
                'genere_le': maintenant,
                'publie_le': maintenant,
              })
          .toList(growable: false);

      final onConflict = periodeId == null ? 'fiche_eleve_id,type' : 'fiche_eleve_id,periode_id,type';
      final ecrites = await _client.from('bulletins').upsert(lignes, onConflict: onConflict).select();
      return ecrites.map((l) => Bulletin.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> saisirNote(Note note) {
    return _executer(() async {
      await _client
          .from('notes')
          .upsert(note.versJsonEcriture(), onConflict: 'evaluation_id,fiche_eleve_id');
      return true;
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurNotes(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
