import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/charge_travail.dart';
import '../domain/conflit_emploi.dart';
import '../domain/emploi_du_temps.dart';
import '../domain/evenement_agenda.dart';
import '../domain/planification_repository.dart';
import '../domain/progression_pedagogique.dart';
import '../domain/salle.dart';

const _embedEmploi = '*, profiles(prenom, nom), programmes_matieres(nom), salles(code), classes(nom)';

/// Implémentation Supabase du port [PlanificationRepository] (M11).
class SupabasePlanificationRepository implements PlanificationRepository {
  const SupabasePlanificationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Salle>> sallesEtablissement(String etablissementId) {
    return _executer(() async {
      final lignes = await _client
          .from('salles')
          .select()
          .eq('etablissement_id', etablissementId)
          .isFilter('deleted_at', null)
          .order('code');
      return lignes.map((l) => Salle.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<EmploiDuTemps>> emploisDeClasse(String classeId) {
    return _executer(() async {
      final lignes = await _client
          .from('emplois_du_temps')
          .select(_embedEmploi)
          .eq('classe_id', classeId)
          .isFilter('deleted_at', null)
          .order('jour_semaine')
          .order('heure_debut');
      return lignes.map((l) => EmploiDuTemps.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<EmploiDuTemps>> emploisDeEnseignant(
    String enseignantProfileId,
    String etablissementId,
    String anneeScolaireId,
  ) {
    return _executer(() async {
      final lignes = await _client
          .from('emplois_du_temps')
          .select(_embedEmploi)
          .eq('enseignant_profile_id', enseignantProfileId)
          .eq('etablissement_id', etablissementId)
          .eq('annee_scolaire_id', anneeScolaireId)
          .isFilter('deleted_at', null)
          .order('jour_semaine')
          .order('heure_debut');
      return lignes.map((l) => EmploiDuTemps.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<EmploiDuTemps>> emploisDeSalle(String salleId, String anneeScolaireId) {
    return _executer(() async {
      final lignes = await _client
          .from('emplois_du_temps')
          .select(_embedEmploi)
          .eq('salle_id', salleId)
          .eq('annee_scolaire_id', anneeScolaireId)
          .isFilter('deleted_at', null)
          .order('jour_semaine')
          .order('heure_debut');
      return lignes.map((l) => EmploiDuTemps.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> enregistrerSeance(EmploiDuTemps emploi) {
    return _executer(() async {
      await _client.from('emplois_du_temps').upsert(emploi.versJsonEcriture(), onConflict: 'id');
      return true;
    });
  }

  @override
  Future<List<EvenementAgenda>> evenementsEtablissement(String etablissementId, String anneeScolaireId) {
    return _executer(() async {
      final lignes = await _client
          .from('evenements_agenda')
          .select()
          .eq('etablissement_id', etablissementId)
          .eq('annee_scolaire_id', anneeScolaireId)
          .isFilter('deleted_at', null)
          .order('date_debut');
      return lignes.map((l) => EvenementAgenda.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<EvenementAgenda>> evenementsDeClasse(String classeId, String anneeScolaireId) {
    return _executer(() async {
      final lignes = await _client
          .from('evenements_agenda')
          .select()
          .eq('classe_id', classeId)
          .eq('annee_scolaire_id', anneeScolaireId)
          .isFilter('deleted_at', null)
          .order('date_debut');
      return lignes.map((l) => EvenementAgenda.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> enregistrerEvenement(EvenementAgenda evenement) {
    return _executer(() async {
      await _client.from('evenements_agenda').upsert(evenement.versJsonEcriture(), onConflict: 'id');
      return true;
    });
  }

  @override
  Future<List<ProgressionPedagogique>> progressionDeClasse(String classeId, String anneeScolaireId) {
    return _executer(() async {
      final lignes = await _client
          .from('progression_pedagogique')
          .select()
          .eq('classe_id', classeId)
          .eq('annee_scolaire_id', anneeScolaireId)
          .isFilter('deleted_at', null)
          .order('date_prevue');
      return lignes.map((l) => ProgressionPedagogique.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> enregistrerProgression(ProgressionPedagogique progression) {
    return _executer(() async {
      await _client.from('progression_pedagogique').upsert(progression.versJsonEcriture(), onConflict: 'id');
      return true;
    });
  }

  @override
  Future<void> changerStatutProgression(String progressionId, String statut) {
    return _executer(() async {
      await _client.from('progression_pedagogique').update({'statut': statut}).eq('id', progressionId);
    });
  }

  @override
  Future<int> recommanderSeances(String etablissementId, String anneeScolaireId) {
    return _executer(() async {
      final resultat = await _client.rpc<num>(
        'recommander_seances',
        params: {'p_etab': etablissementId, 'p_annee': anneeScolaireId},
      );
      return resultat.toInt();
    });
  }

  @override
  Future<Map<String, dynamic>?> suggererPlacement({
    required String etablissementId,
    required String anneeScolaireId,
    required String enseignantProfileId,
    required String classeId,
    required String salleId,
  }) {
    return _executer(() async {
      return _client.rpc<Map<String, dynamic>?>(
        'suggerer_placement_seance',
        params: {
          'p_etab': etablissementId,
          'p_annee': anneeScolaireId,
          'p_enseignant': enseignantProfileId,
          'p_classe': classeId,
          'p_salle': salleId,
        },
      );
    });
  }

  @override
  Future<List<ConflitEmploi>> detecterConflits(String etablissementId, String anneeScolaireId) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'detecter_conflits_emploi',
        params: {'p_etab': etablissementId, 'p_annee': anneeScolaireId},
      );
      return resultat.map((l) => ConflitEmploi.depuisJson(l as Map<String, dynamic>)).toList(growable: false);
    });
  }

  @override
  Future<ChargeTravailEnseignant> chargeEnseignant(
    String etablissementId,
    String anneeScolaireId,
    String enseignantProfileId,
  ) {
    return _executer(() async {
      final resultat = await _client.rpc<Map<String, dynamic>>(
        'charger_travail_enseignant',
        params: {'p_etab': etablissementId, 'p_annee': anneeScolaireId, 'p_enseignant': enseignantProfileId},
      );
      return ChargeTravailEnseignant.depuisJson(resultat);
    });
  }

  @override
  Future<ChargeTravailEleve> chargeEleve(String classeId) {
    return _executer(() async {
      final resultat = await _client.rpc<Map<String, dynamic>>('charger_travail_eleve', params: {'p_classe': classeId});
      return ChargeTravailEleve.depuisJson(resultat);
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurPlanification(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
