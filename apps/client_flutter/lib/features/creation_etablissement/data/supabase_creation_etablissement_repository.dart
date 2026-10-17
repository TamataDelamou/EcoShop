import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/demande_etablissement.dart';

/// Implémentation Supabase (REG-04) : RPC sous RLS, jamais d'écriture directe.
class SupabaseCreationEtablissementRepository implements CreationEtablissementRepository {
  const SupabaseCreationEtablissementRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> soumettre(SaisieDemandeEtablissement s) {
    return _executer(() => _client.rpc<String>('soumettre_demande_etablissement', params: {
          'p_nom': s.nom,
          'p_pays_code': s.paysCode,
          'p_ville': s.ville,
          'p_telephone': s.telephone,
          'p_adresse': s.adresse,
          'p_email': s.email,
          'p_effectif_estime': s.effectifEstime,
          'p_numero_autorisation': s.numeroAutorisation,
          'p_message': s.message,
        }));
  }

  @override
  Future<DemandeEtablissement?> maDerniereDemande() {
    return _executer(() async {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final ligne = await _client
          .from('demandes_etablissement')
          .select('id, nom_etablissement, pays_code, ville, statut, motif_refus, etablissement_id, created_at')
          .eq('demandeur_id', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return ligne == null ? null : DemandeEtablissement.depuisJson(ligne);
    });
  }

  @override
  Future<List<DemandeATraiter>> demandesATraiter() {
    return _executer(() async {
      final json = await _client.rpc<List<dynamic>>('demandes_etablissement_a_traiter');
      return [for (final d in json) DemandeATraiter.depuisJson(d as Map<String, dynamic>)];
    });
  }

  @override
  Future<void> traiter({required String demandeId, required bool accepter, String? motif}) {
    return _executer(() => _client.rpc<dynamic>('traiter_demande_etablissement', params: {
          'p_demande_id': demandeId,
          'p_decision': accepter ? 'acceptee' : 'refusee',
          'p_motif': motif,
        }));
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      throw ErreurCreationEtablissement(
        RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier) ? premier : 'ERREUR_RESEAU',
      );
    }
  }
}
