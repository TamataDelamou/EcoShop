import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/eleve_mention.dart';
import '../domain/proclamation_repository.dart';

/// Implémentation Supabase du port [ProclamationRepository] (cahier §12.3,
/// §12.4, §7.3). Toute écriture passe par une RPC `SECURITY DEFINER`
/// (`definir_mention_finale`, `proclamer_classe`) — jamais un `.update()`
/// direct sur `inscriptions`/`proclamations_classes`.
class SupabaseProclamationRepository implements ProclamationRepository {
  const SupabaseProclamationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> classeEstExamen(String classeId) {
    return _executer(() async {
      return await _client.rpc<bool>(
        'classe_est_examen',
        params: {'p_classe': classeId},
      );
    });
  }

  @override
  Future<bool> classeEstProclamee({
    required String classeId,
    required String anneeScolaireId,
  }) {
    return _executer(() async {
      return await _client.rpc<bool>(
        'classe_est_proclamee',
        params: {'p_classe': classeId, 'p_annee': anneeScolaireId},
      );
    });
  }

  @override
  Future<List<EleveMention>> elevesDeClasse(String classeId) {
    return _executer(() async {
      final lignes = await _client
          .from('inscriptions')
          .select('id, fiche_eleve_id, mention_finale, fiches_eleves(nom, prenom)')
          .eq('classe_id', classeId)
          .eq('statut', 'active')
          .isFilter('deleted_at', null);
      final eleves = lignes.map((l) => EleveMention.depuisJson(l)).toList(growable: false);
      return eleves.sortedParNom();
    });
  }

  @override
  Future<void> definirMentionFinale({
    required String inscriptionId,
    required String mention,
  }) {
    return _executer(() async {
      await _client.rpc(
        'definir_mention_finale',
        params: {'p_inscription': inscriptionId, 'p_mention': mention},
      );
    });
  }

  @override
  Future<void> proclamerClasse({
    required String classeId,
    required String anneeScolaireId,
  }) {
    return _executer(() async {
      await _client.rpc(
        'proclamer_classe',
        params: {'p_classe': classeId, 'p_annee': anneeScolaireId},
      );
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurProclamation(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}

extension on List<EleveMention> {
  List<EleveMention> sortedParNom() =>
      [...this]..sort((a, b) => a.nom.compareTo(b.nom));
}
