import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/sync/sync_engine.dart';
import 'cached_scolarite_repository.dart';

/// Rejoue au serveur les encaissements faits au guichet sans réseau.
///
/// Panne de réseau : l'erreur remonte, l'entrée reste en file. Refus du
/// serveur (droits retirés, élève changé d'école…) : [RejetDefinitif] avec
/// l'explication, montrée dans le bandeau — l'argent a été reçu, la
/// Direction doit régulariser. Le serveur reconnaît la clé : un renvoi ne
/// crée jamais de doublon ni de trou dans la numérotation.
class RejeuEncaissements {
  const RejeuEncaissements(this._client);

  final SupabaseClient _client;

  static const entites = [
    CachedScolariteRepository.entiteEncaissement,
    CachedScolariteRepository.entiteAnnulationEncaissement,
  ];

  Future<void> rejouer(SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      if (entree.entite == CachedScolariteRepository.entiteEncaissement) {
        final params = Map<String, dynamic>.of(p)..remove('_cache');
        await _client.rpc<dynamic>('enregistrer_encaissement_scolarite', params: params);
      } else {
        try {
          await _client
              .from('encaissements_scolarite')
              .update({'statut': 'annule', 'motif_annulation': p['motif']})
              .eq('id', p['id'] as String);
        } on PostgrestException catch (e) {
          // Déjà annulé (depuis un autre appareil) : c'est fait.
          if (!e.message.startsWith('ENCAISSEMENT_DEJA_ANNULE')) rethrow;
        }
      }
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      final metier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier);
      if (metier || e.code == '42501' || e.code == '23503' || e.code == '23505' || e.code == '23514') {
        throw RejetDefinitif(metier ? premier : (e.code ?? 'REFUS'), messageRejet(metier ? premier : 'REFUS'));
      }
      rethrow;
    }
  }

  static String messageRejet(String code) => switch (code) {
        'REFUS' || 'PERMISSION_REFUSEE' || 'ACCES_REFUSE' =>
          "Le serveur a refusé l'encaissement : vos droits ont peut-être changé. L'argent reçu doit être régularisé par la direction.",
        'CLE_DEJA_UTILISEE' => 'Cet encaissement existe déjà dans une autre école.',
        'INSCRIPTION_FICHE_INCOHERENTE' || 'INSCRIPTION_AUTRE_ETABLISSEMENT' || 'FICHE_AUTRE_ETABLISSEMENT' =>
          "L'inscription de l'élève a changé entre-temps : enregistrez de nouveau l'encaissement.",
        _ => "Le serveur a refusé l'encaissement ($code). L'argent reçu doit être régularisé par la direction.",
      };

  /// Ce qui avait été saisi, pour le reconnaître dans les refus.
  static String libelle(SyncEntree entree) {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    if (entree.entite == CachedScolariteRepository.entiteEncaissement) {
      return 'Encaissement de ${p['p_montant']} (reçu ${p['p_numero_provisoire'] ?? '—'})';
    }
    return "Annulation d'un encaissement";
  }
}
