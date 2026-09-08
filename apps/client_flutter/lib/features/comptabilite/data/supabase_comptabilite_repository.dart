import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/comptabilite_repository.dart';
import '../domain/ecriture_comptable.dart';
import '../domain/journal.dart';
import '../domain/ligne_balance.dart';
import '../domain/ligne_journal.dart';
import '../domain/mouvement_grand_livre.dart';
import '../domain/plan_comptable.dart';
import '../domain/signaux_ia_comptables.dart';

/// Implémentation Supabase du port [ComptabiliteRepository] (M14).
class SupabaseComptabiliteRepository implements ComptabiliteRepository {
  const SupabaseComptabiliteRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<PlanComptable>> planComptable(String etablissementId) {
    return _executer(() async {
      final lignes = await _client
          .from('plans_comptables')
          .select()
          .eq('etablissement_id', etablissementId)
          .isFilter('deleted_at', null)
          .order('code');
      return lignes.map((l) => PlanComptable.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> enregistrerCompte(PlanComptable compte) {
    return _executer(() async {
      await _client.from('plans_comptables').upsert(compte.versJsonEcriture(), onConflict: 'etablissement_id,code');
      return true;
    });
  }

  @override
  Future<List<Journal>> journaux(String etablissementId) {
    return _executer(() async {
      final lignes = await _client
          .from('journaux')
          .select()
          .eq('etablissement_id', etablissementId)
          .isFilter('deleted_at', null)
          .order('code');
      return lignes.map((l) => Journal.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> enregistrerJournal(Journal journal) {
    return _executer(() async {
      await _client.from('journaux').upsert(journal.versJsonEcriture(), onConflict: 'etablissement_id,code');
      return true;
    });
  }

  @override
  Future<List<EcritureComptable>> ecrituresRecentes(String etablissementId, {int limite = 100}) {
    return _executer(() async {
      final lignes = await _client
          .from('ecritures_comptables')
          .select()
          .eq('etablissement_id', etablissementId)
          .isFilter('deleted_at', null)
          .order('date_ecriture', ascending: false)
          .order('created_at', ascending: false)
          .limit(limite);
      return lignes.map((l) => EcritureComptable.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> enregistrerEcriture(EcritureComptable ecriture) {
    return _executer(() async {
      await _client.from('ecritures_comptables').upsert(ecriture.versJsonEcriture(), onConflict: 'id');
      return true;
    });
  }

  @override
  Future<List<LigneJournal>> journalComptable(
    String etablissementId,
    String journalId,
    DateTime debut,
    DateTime fin,
  ) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'journal_comptable',
        params: {
          'p_etablissement': etablissementId,
          'p_journal': journalId,
          'p_debut': _dateIso(debut),
          'p_fin': _dateIso(fin),
        },
      );
      return resultat.map((l) => LigneJournal.depuisJson(l as Map<String, dynamic>)).toList(growable: false);
    });
  }

  @override
  Future<List<MouvementGrandLivre>> grandLivre(
    String etablissementId,
    String compteId,
    DateTime debut,
    DateTime fin,
  ) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'grand_livre',
        params: {
          'p_etablissement': etablissementId,
          'p_compte': compteId,
          'p_debut': _dateIso(debut),
          'p_fin': _dateIso(fin),
        },
      );
      return resultat.map((l) => MouvementGrandLivre.depuisJson(l as Map<String, dynamic>)).toList(growable: false);
    });
  }

  @override
  Future<List<LigneBalance>> balanceComptable(String etablissementId, DateTime date) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'balance_comptable',
        params: {'p_etablissement': etablissementId, 'p_date': _dateIso(date)},
      );
      return resultat.map((l) => LigneBalance.depuisJson(l as Map<String, dynamic>)).toList(growable: false);
    });
  }

  @override
  Future<List<Balance>> genererBalance(String etablissementId, DateTime date) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'generer_balance',
        params: {'p_etablissement': etablissementId, 'p_date': _dateIso(date)},
      );
      return resultat.map((l) => Balance.depuisJson(l as Map<String, dynamic>)).toList(growable: false);
    });
  }

  @override
  Future<List<AnomalieComptable>> detecterAnomalies(String etablissementId) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'detecter_anomalies_comptables',
        params: {'p_etablissement': etablissementId},
      );
      return resultat.map((l) => AnomalieComptable.depuisJson(l as Map<String, dynamic>)).toList(growable: false);
    });
  }

  @override
  Future<List<ProjectionTresorerie>> predireTresorerie(String etablissementId, {int jours = 30}) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'predire_tresorerie',
        params: {'p_etablissement': etablissementId, 'p_jours': jours},
      );
      return resultat.map((l) => ProjectionTresorerie.depuisJson(l as Map<String, dynamic>)).toList(growable: false);
    });
  }

  @override
  Future<List<EcritureRecommandee>> recommanderEcritures(String etablissementId) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'recommander_ecritures',
        params: {'p_etablissement': etablissementId},
      );
      return resultat.map((l) => EcritureRecommandee.depuisJson(l as Map<String, dynamic>)).toList(growable: false);
    });
  }

  @override
  Future<List<TendanceMensuelle>> analyserTendances(String etablissementId, {int mois = 12}) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'analyser_tendances',
        params: {'p_etablissement': etablissementId, 'p_mois': mois},
      );
      return resultat.map((l) => TendanceMensuelle.depuisJson(l as Map<String, dynamic>)).toList(growable: false);
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
      throw ErreurComptabilite(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
