import 'package:supabase_flutter/supabase_flutter.dart' hide Presence;

import '../domain/alerte_decrochage.dart';
import '../domain/evenement_scolaire.dart';
import '../domain/presence.dart';
import '../domain/retard.dart';
import '../domain/sanction.dart';
import '../domain/vie_scolaire_repository.dart';

/// Implémentation Supabase du port [VieScolaireRepository] (M7).
///
/// [presence.id] est généré côté client de façon déterministe (fiche +
/// date + séance, voir `construirePresenceSaisie`) : `presences` porte deux
/// index uniques **partiels** (`demi_journee` / `cours`) que PostgREST ne
/// peut pas cibler directement via `on_conflict` (un `ON CONFLICT (colonnes)`
/// sans clause `WHERE` ne matche pas un index partiel). Upserter sur la clé
/// primaire déterministe contourne cette limite sans exiger de RPC dédiée.
class SupabaseVieScolaireRepository implements VieScolaireRepository {
  const SupabaseVieScolaireRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Presence>> presencesDeClasse(String classeId, DateTime date) {
    return _executer(() async {
      final lignes = await _client
          .from('presences')
          .select('*, fiches_eleves(prenom, nom)')
          .eq('classe_id', classeId)
          .eq('date_presence', _dateIso(date))
          .isFilter('deleted_at', null);
      return lignes.map((l) => Presence.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<Presence>> presencesDeFiche(String ficheEleveId) {
    return _executer(() async {
      final lignes = await _client
          .from('presences')
          .select()
          .eq('fiche_eleve_id', ficheEleveId)
          .isFilter('deleted_at', null)
          .order('date_presence', ascending: false);
      return lignes.map((l) => Presence.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<Retard>> retardsDeFiche(String ficheEleveId) {
    return _executer(() async {
      final lignes = await _client
          .from('retards')
          .select()
          .eq('fiche_eleve_id', ficheEleveId)
          .isFilter('deleted_at', null)
          .order('date_retard', ascending: false);
      return lignes.map((l) => Retard.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<Sanction>> sanctionsDeFiche(String ficheEleveId) {
    return _executer(() async {
      final lignes = await _client
          .from('sanctions')
          .select()
          .eq('fiche_eleve_id', ficheEleveId)
          .isFilter('deleted_at', null)
          .order('date_debut', ascending: false);
      return lignes.map((l) => Sanction.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<AlerteDecrochage>> alertesDeFiche(String ficheEleveId) {
    return _executer(() async {
      final lignes = await _client
          .from('alertes_decrochage')
          .select('*, fiches_eleves(prenom, nom)')
          .eq('fiche_eleve_id', ficheEleveId)
          .isFilter('deleted_at', null)
          .order('date_calcul', ascending: false);
      return lignes.map((l) => AlerteDecrochage.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<AlerteDecrochage>> alertesEtablissement(String etablissementId) {
    return _executer(() async {
      final lignes = await _client
          .from('alertes_decrochage')
          .select('*, fiches_eleves(prenom, nom)')
          .eq('etablissement_id', etablissementId)
          .isFilter('deleted_at', null)
          .order('score', ascending: false);
      return lignes.map((l) => AlerteDecrochage.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<EvenementScolaire>> evenementsEtablissement(String etablissementId) {
    return _executer(() async {
      final lignes = await _client
          .from('evenements_scolaires')
          .select()
          .eq('etablissement_id', etablissementId)
          .isFilter('deleted_at', null)
          .order('date_debut');
      return lignes.map((l) => EvenementScolaire.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<Map<String, dynamic>> analyseComportement(String ficheEleveId, String anneeScolaireId) {
    return _executer(() async {
      final resultat = await _client.rpc<Map<String, dynamic>>(
        'analyse_comportement',
        params: {'p_fiche': ficheEleveId, 'p_annee': anneeScolaireId},
      );
      return resultat;
    });
  }

  @override
  Future<double> scoreDecrochage(String ficheEleveId, String anneeScolaireId) {
    return _executer(() async {
      final resultat = await _client.rpc<num>(
        'calculer_score_decrochage',
        params: {'p_fiche': ficheEleveId, 'p_annee': anneeScolaireId},
      );
      return resultat.toDouble();
    });
  }

  @override
  Future<Map<String, dynamic>> recommandationSanction(String ficheEleveId, String anneeScolaireId) {
    return _executer(() async {
      final resultat = await _client.rpc<Map<String, dynamic>>(
        'recommander_sanction_educative',
        params: {'p_fiche': ficheEleveId, 'p_annee': anneeScolaireId},
      );
      return resultat;
    });
  }

  @override
  Future<double> predirePresence(String etablissementId, DateTime date) {
    return _executer(() async {
      final resultat = await _client.rpc<num>(
        'predire_presence',
        params: {'p_etab': etablissementId, 'p_date': _dateIso(date)},
      );
      return resultat.toDouble();
    });
  }

  @override
  Future<bool> saisirPresence(Presence presence) {
    return _executer(() async {
      await _client.from('presences').upsert(presence.versJsonEcriture(), onConflict: 'id');
      return true;
    });
  }

  @override
  Future<bool> saisirRetard(Retard retard) {
    return _executer(() async {
      await _client
          .from('retards')
          .upsert(retard.versJsonEcriture(), onConflict: 'fiche_eleve_id,date_retard');
      return true;
    });
  }

  @override
  Future<Sanction> proposerSanction(Sanction sanction) {
    return _executer(() async {
      final payload = sanction.versJsonCache()..remove('id');
      final ligne = await _client.from('sanctions').insert(payload).select().single();
      return Sanction.depuisJson(ligne);
    });
  }

  @override
  Future<void> validerSanction(String sanctionId, {required String valideePar}) {
    return _executer(() async {
      await _client.from('sanctions').update({
        'validee_par': valideePar,
        'validee_le': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', sanctionId);
    });
  }

  @override
  Future<void> changerStatutSanction(String sanctionId, String statut) {
    return _executer(() async {
      await _client.from('sanctions').update({'statut': statut}).eq('id', sanctionId);
    });
  }

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurVieScolaire(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
