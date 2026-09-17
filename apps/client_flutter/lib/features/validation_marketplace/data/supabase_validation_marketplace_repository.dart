import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/agrement_vendeur.dart';
import '../domain/validation_marketplace_repository.dart';
import '../domain/vendeur_validation.dart';

/// Implémentation Supabase du port [ValidationMarketplaceRepository] (cahier
/// §27.1-27.2, §30.1-30.2). Toute écriture passe par une RPC `SECURITY
/// DEFINER` (`valider_vendeur`, `decider_agrement_vendeur_etablissement`) —
/// `commercants`/`agrements_vendeurs_etablissements` n'ont aucune policy
/// d'écriture cliente pour ces champs.
class SupabaseValidationMarketplaceRepository implements ValidationMarketplaceRepository {
  const SupabaseValidationMarketplaceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<VendeurValidation>> vendeurs() {
    return _executer(() async {
      final lignes = await _client
          .from('commercants')
          .select('id, nom, raison_sociale, statut_validation, motif_refus, valide_le')
          .isFilter('deleted_at', null)
          .order('nom');
      return lignes.map((l) => VendeurValidation.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<void> validerVendeur({
    required String commercantId,
    required String decision,
    String? motif,
  }) {
    return _executer(() async {
      await _client.rpc('valider_vendeur', params: {
        'p_commercant': commercantId,
        'p_decision': decision,
        'p_motif': motif,
      });
    });
  }

  @override
  Future<List<AgrementVendeur>> agrementsPourEtablissement(String etablissementId) {
    return _executer(() async {
      final vendeursValides = await _client
          .from('commercants')
          .select('id, nom')
          .eq('statut_validation', 'valide')
          .isFilter('deleted_at', null)
          .order('nom');
      final agrements = await _client
          .from('agrements_vendeurs_etablissements')
          .select('commercant_id, statut, motif_refus, decide_le')
          .eq('etablissement_id', etablissementId);
      final agrementsParCommercant = {
        for (final a in agrements) a['commercant_id'] as String: a,
      };
      return vendeursValides.map((v) {
        final commercantId = v['id'] as String;
        final agrement = agrementsParCommercant[commercantId];
        return AgrementVendeur(
          commercantId: commercantId,
          nomVendeur: v['nom'] as String,
          statut: agrement?['statut'] as String? ?? 'en_attente',
          motifRefus: agrement?['motif_refus'] as String?,
          decideLe: agrement?['decide_le'] == null ? null : DateTime.parse(agrement!['decide_le'] as String),
        );
      }).toList(growable: false);
    });
  }

  @override
  Future<void> deciderAgrement({
    required String commercantId,
    required String etablissementId,
    required String decision,
    String? motif,
  }) {
    return _executer(() async {
      await _client.rpc('decider_agrement_vendeur_etablissement', params: {
        'p_commercant': commercantId,
        'p_etablissement': etablissementId,
        'p_decision': decision,
        'p_motif': motif,
      });
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurValidationMarketplace(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
