import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/referentiel_comptable.dart';

/// Implémentation Supabase (REG-03 C1) : lecture sous RLS, choix par RPC.
class SupabaseReferentielComptableRepository implements ReferentielComptableRepository {
  const SupabaseReferentielComptableRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ParametresComptables> parametres(String etablissementId) {
    return _executer(() async {
      final ligne = await _client
          .from('parametres_comptables')
          .select('referentiel, forme_juridique, chiffre_affaires_estime, choisi_le')
          .eq('etablissement_id', etablissementId)
          .maybeSingle();
      return ligne == null ? ParametresComptables.parDefaut : ParametresComptables.depuisJson(ligne);
    });
  }

  @override
  Future<RecommandationReferentiel> recommander({
    required FormeJuridique formeJuridique,
    double? chiffreAffaires,
    required String devise,
    required bool souhaitReglementaire,
  }) {
    return _executer(() async {
      final json = await _client.rpc<Map<String, dynamic>>('recommander_referentiel_comptable', params: {
        'p_forme_juridique': formeJuridique.code,
        'p_chiffre_affaires': chiffreAffaires,
        'p_devise': devise,
        'p_souhait_reglementaire': souhaitReglementaire,
      });
      return RecommandationReferentiel.depuisJson(json);
    });
  }

  @override
  Future<ResultatChoixReferentiel> choisir({
    required String etablissementId,
    required ReferentielComptable referentiel,
    FormeJuridique? formeJuridique,
    double? chiffreAffaires,
  }) {
    return _executer(() async {
      final json = await _client.rpc<Map<String, dynamic>>('choisir_referentiel_comptable', params: {
        'p_etablissement': etablissementId,
        'p_referentiel': referentiel.code,
        'p_forme_juridique': formeJuridique?.code,
        'p_chiffre_affaires': chiffreAffaires,
      });
      return ResultatChoixReferentiel(
        referentiel: ReferentielComptable.depuisCode(json['referentiel'] as String?),
        comptesCharges: (json['comptes_charges'] as num?)?.toInt() ?? 0,
      );
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      throw ErreurReferentielComptable(
        RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier) ? premier : 'ERREUR_RESEAU',
      );
    }
  }
}
