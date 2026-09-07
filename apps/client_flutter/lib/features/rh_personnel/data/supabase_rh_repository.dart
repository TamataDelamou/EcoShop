import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/absence_personnel.dart';
import '../domain/bulletin_paie.dart';
import '../domain/conge.dart';
import '../domain/contrat.dart';
import '../domain/effectif_categorie.dart';
import '../domain/employe.dart';
import '../domain/recommandation_formation.dart';
import '../domain/remplacement_suggere.dart';
import '../domain/rh_repository.dart';

/// Implémentation Supabase du port [RhRepository] (M8).
class SupabaseRhRepository implements RhRepository {
  const SupabaseRhRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Employe>> employesEtablissement(String etablissementId) {
    return _executer(() async {
      final lignes = await _client
          .from('employes')
          .select('*, profiles(prenom, nom)')
          .eq('etablissement_id', etablissementId)
          .isFilter('deleted_at', null)
          .order('matricule');
      return lignes.map((l) => Employe.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<Employe?> employeParProfil(String profileId) {
    return _executer(() async {
      final ligne = await _client
          .from('employes')
          .select('*, profiles(prenom, nom)')
          .eq('profile_id', profileId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      return ligne == null ? null : Employe.depuisJson(ligne);
    });
  }

  @override
  Future<Employe?> employe(String employeId) {
    return _executer(() async {
      final ligne = await _client
          .from('employes')
          .select('*, profiles(prenom, nom)')
          .eq('id', employeId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      return ligne == null ? null : Employe.depuisJson(ligne);
    });
  }

  @override
  Future<List<Contrat>> contratsDeEmploye(String employeId) {
    return _executer(() async {
      final lignes = await _client
          .from('contrats')
          .select()
          .eq('employe_id', employeId)
          .isFilter('deleted_at', null)
          .order('date_debut', ascending: false);
      return lignes.map((l) => Contrat.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<Conge>> congesDeEmploye(String employeId) {
    return _executer(() async {
      final lignes = await _client
          .from('conges')
          .select()
          .eq('employe_id', employeId)
          .isFilter('deleted_at', null)
          .order('date_debut', ascending: false);
      return lignes.map((l) => Conge.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<AbsencePersonnel>> absencesDeEmploye(String employeId) {
    return _executer(() async {
      final lignes = await _client
          .from('absences_personnel')
          .select()
          .eq('employe_id', employeId)
          .isFilter('deleted_at', null)
          .order('date_absence', ascending: false);
      return lignes.map((l) => AbsencePersonnel.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<BulletinPaie>> bulletinsDeEmploye(String employeId) {
    return _executer(() async {
      final lignes = await _client
          .from('paie_bulletins')
          .select()
          .eq('employe_id', employeId)
          .isFilter('deleted_at', null)
          .order('periode_debut', ascending: false);
      return lignes.map((l) => BulletinPaie.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<int> chargeHoraire(String employeId) {
    return _executer(() async {
      final resultat = await _client.rpc<num>('charge_horaire', params: {'p_employe': employeId});
      return resultat.toInt();
    });
  }

  @override
  Future<List<EffectifCategorie>> analyserEffectifs(String etablissementId) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'analyser_effectifs',
        params: {'p_etablissement': etablissementId},
      );
      return resultat
          .map((l) => EffectifCategorie.depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    });
  }

  @override
  Future<double> scoreTurnover(String employeId) {
    return _executer(() async {
      final resultat = await _client.rpc<num>('calculer_score_turnover', params: {'p_employe': employeId});
      return resultat.toDouble();
    });
  }

  @override
  Future<List<RecommandationFormation>> recommanderFormation(String employeId, String anneeScolaireId) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'recommander_formation',
        params: {'p_employe': employeId, 'p_annee': anneeScolaireId},
      );
      return resultat
          .map((l) => RecommandationFormation.depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    });
  }

  @override
  Future<List<RemplacementSuggere>> optimiserRemplacements(String etablissementId, DateTime date) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'optimiser_remplacements',
        params: {'p_etablissement': etablissementId, 'p_date': _dateIso(date)},
      );
      return resultat
          .map((l) => RemplacementSuggere.depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    });
  }

  @override
  Future<void> creerOuModifierEmploye(Employe employe) {
    return _executer(() async {
      await _client.from('employes').upsert(employe.versJsonEcriture(), onConflict: 'id');
    });
  }

  @override
  Future<Contrat> creerContrat(Contrat contrat) {
    return _executer(() async {
      final ligne = await _client.from('contrats').insert(contrat.versJsonEcriture()).select().single();
      return Contrat.depuisJson(ligne);
    });
  }

  @override
  Future<bool> demanderConge(Conge conge) {
    return _executer(() async {
      await _client.from('conges').upsert(conge.versJsonEcriture(), onConflict: 'employe_id,date_debut,type');
      return true;
    });
  }

  @override
  Future<void> validerConge(String congeId, {required String statut, required String valideePar}) {
    return _executer(() async {
      await _client.from('conges').update({
        'statut': statut,
        'valide_par': valideePar,
        'date_validation': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', congeId);
    });
  }

  @override
  Future<bool> pointerAbsence(AbsencePersonnel absence) {
    return _executer(() async {
      await _client
          .from('absences_personnel')
          .upsert(absence.versJsonEcriture(), onConflict: 'employe_id,date_absence');
      return true;
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
      throw ErreurRh(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
