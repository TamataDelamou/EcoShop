import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/anomalie_statistique.dart';
import '../domain/indicateur_cle.dart';
import '../domain/rapport.dart';
import '../domain/rapports_repository.dart';
import '../domain/recommandation_strategique.dart';

/// Implémentation Supabase du port [RapportsRepository] (M10).
class SupabaseRapportsRepository implements RapportsRepository {
  const SupabaseRapportsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Rapport>> rapportsDeFiche(String ficheEleveId) {
    return _executer(() async {
      final lignes = await _client
          .from('rapports')
          .select()
          .eq('fiche_eleve_id', ficheEleveId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      return lignes.map((l) => Rapport.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<Rapport>> rapportsEtablissement(String etablissementId) {
    return _executer(() async {
      final lignes = await _client
          .from('rapports')
          .select()
          .eq('etablissement_id', etablissementId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      return lignes.map((l) => Rapport.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> demanderRapport(Rapport rapport) {
    return _executer(() async {
      await _client.from('rapports').upsert(rapport.versJsonEcriture(), onConflict: 'id');
      return true;
    });
  }

  @override
  Future<List<IndicateurCle>> indicateursEtablissement(String etablissementId, String anneeScolaireId) {
    return _executer(() async {
      final lignes = await _client
          .from('indicateurs_cles')
          .select()
          .eq('etablissement_id', etablissementId)
          .eq('annee_scolaire_id', anneeScolaireId)
          .isFilter('periode_id', null)
          .isFilter('classe_id', null)
          .order('code');
      return lignes.map((l) => IndicateurCle.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<int> consoliderIndicateurs(String etablissementId, String anneeScolaireId) {
    return _executer(() async {
      final resultat = await _client.rpc<num>(
        'consolider_indicateurs_etablissement',
        params: {'p_etab': etablissementId, 'p_annee': anneeScolaireId},
      );
      return resultat.toInt();
    });
  }

  @override
  Future<List<AnomalieStatistique>> anomaliesEtablissement(String etablissementId, String anneeScolaireId) {
    return _executer(() async {
      final lignes = await _client
          .from('anomalies_statistiques')
          .select()
          .eq('etablissement_id', etablissementId)
          .eq('annee_scolaire_id', anneeScolaireId)
          .isFilter('deleted_at', null)
          .order('detectee_le', ascending: false);
      return lignes.map((l) => AnomalieStatistique.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<int> detecterAnomalies(String etablissementId, String anneeScolaireId) {
    return _executer(() async {
      final resultat = await _client.rpc<num>(
        'detecter_anomalies',
        params: {'p_etab': etablissementId, 'p_annee': anneeScolaireId},
      );
      return resultat.toInt();
    });
  }

  @override
  Future<void> traiterAnomalie(String anomalieId, String statut, {required String traiteePar}) {
    return _executer(() async {
      await _client.from('anomalies_statistiques').update({
        'statut': statut,
        'traitee_par': traiteePar,
        'traitee_le': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', anomalieId);
    });
  }

  @override
  Future<List<RecommandationStrategique>> recommandationsEtablissement(
    String etablissementId,
    String anneeScolaireId,
  ) {
    return _executer(() async {
      final lignes = await _client
          .from('recommandations_strategiques')
          .select()
          .eq('etablissement_id', etablissementId)
          .eq('annee_scolaire_id', anneeScolaireId)
          .isFilter('deleted_at', null)
          .order('cree_le', ascending: false);
      return lignes.map((l) => RecommandationStrategique.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<int> genererRecommandations(String etablissementId, String anneeScolaireId) {
    return _executer(() async {
      final resultat = await _client.rpc<num>(
        'recommander_actions',
        params: {'p_etab': etablissementId, 'p_annee': anneeScolaireId},
      );
      return resultat.toInt();
    });
  }

  @override
  Future<void> statuerRecommandation(String recommandationId, String statut, {required String valideePar}) {
    return _executer(() async {
      await _client.from('recommandations_strategiques').update({
        'statut': statut,
        'validee_par': valideePar,
        'validee_le': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', recommandationId);
    });
  }

  @override
  Future<Map<String, dynamic>> risqueClasse(String classeId) {
    return _executer(() async {
      return _client.rpc<Map<String, dynamic>>('risque_classe', params: {'p_classe': classeId});
    });
  }

  @override
  Future<String> resumeExecutif(String etablissementId, String anneeScolaireId) {
    return _executer(() async {
      return _client.rpc<String>(
        'generer_resume_executif',
        params: {'p_etab': etablissementId, 'p_annee': anneeScolaireId},
      );
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurRapports(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
