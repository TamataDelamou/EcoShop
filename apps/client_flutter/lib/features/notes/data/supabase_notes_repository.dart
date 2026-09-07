import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/appreciation.dart';
import '../domain/bulletin.dart';
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
