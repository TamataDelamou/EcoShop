import 'dart:convert';

import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/etats_financiers.dart';

/// États financiers d'abord hors connexion (REG-03 C7) : la consultation
/// est gardée sur l'appareil par le dépôt réseau ; ici, les notes annexes
/// rédigées sans réseau partent en file et s'affichent tout de suite. Le
/// passage des produits constatés d'avance reste une opération en ligne.
class EtatsFinanciersHorsLigneRepository implements EtatsFinanciersRepository {
  const EtatsFinanciersHorsLigneRepository(this._distant, this._file);

  final EtatsFinanciersRepository _distant;
  final DriftSyncRepository _file;

  static const entite = 'notes_annexes';

  @override
  Future<void> enregistrerNote(String exerciceId, String cle, String texte) async {
    try {
      await _distant.enregistrerNote(exerciceId, cle, texte);
    } on ErreurEtatsFinanciers catch (e) {
      if (e.code != 'HORS_CONNEXION') rethrow;
      await _file.enfiler(SyncEntree(
        id: 'note-$exerciceId-$cle',
        entite: entite,
        operation: 'upsert',
        payload: jsonEncode({'p_exercice_id': exerciceId, 'p_cle': cle, 'p_texte': texte}),
      ));
    }
  }

  @override
  Future<NotesAnnexes> notesAnnexes(String etablissementId, String exerciceId) async {
    final notes = await _distant.notesAnnexes(etablissementId, exerciceId);
    final enAttente = <String, String>{
      for (final e in await _file.entreesEnAttente())
        if (e.entite == entite)
          if (jsonDecode(e.payload) case {'p_exercice_id': final String x, 'p_cle': final String cle, 'p_texte': final String t}
              when x == exerciceId)
            cle: t,
    };
    if (enAttente.isEmpty) return notes;
    return NotesAnnexes(
      plan: notes.plan,
      cloture: notes.cloture,
      devise: notes.devise,
      notes: [
        for (final n in notes.notes)
          n.modifiable != null && enAttente.containsKey(n.modifiable) && n.code != '1'
              ? NoteAnnexe(
                  code: n.code,
                  titre: n.titre,
                  genre: n.genre,
                  texte: enAttente[n.modifiable],
                  colonnes: n.colonnes,
                  lignes: n.lignes,
                  modifiable: n.modifiable,
                )
              : n,
      ],
    );
  }

  @override
  Future<EtatFinancier> etat(String etablissementId, String exerciceId) => _distant.etat(etablissementId, exerciceId);

  @override
  Future<ApercuPca> apercuPca(String exerciceId) => _distant.apercuPca(exerciceId);

  @override
  Future<double> passerPca(String exerciceId) => _distant.passerPca(exerciceId);

  @override
  Future<TableauFlux> fluxTresorerie(String etablissementId, String exerciceId) =>
      _distant.fluxTresorerie(etablissementId, exerciceId);
}
