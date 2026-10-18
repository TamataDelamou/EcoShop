import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/sync/sync_engine.dart';
import '../domain/dons.dart';
import '../domain/etats_financiers.dart';
import '../domain/pieces_comptables.dart';
import 'dons_hors_ligne_repository.dart';
import 'etats_financiers_hors_ligne_repository.dart';
import 'pieces_hors_ligne_repository.dart';

/// Entités de la file rejouées par [RejeuComptabilite] (REG-03 C7).
const entitesComptabiliteHorsLigne = [
  DonsHorsLigneRepository.entiteDon,
  DonsHorsLigneRepository.entiteDonateur,
  DonsHorsLigneRepository.entiteArchivageDonateur,
  DonsHorsLigneRepository.entiteAffectation,
  DonsHorsLigneRepository.entiteEngagement,
  DonsHorsLigneRepository.entiteAnnulation,
  PiecesHorsLigneRepository.entite,
  EtatsFinanciersHorsLigneRepository.entite,
];

/// Rejoue au serveur les saisies comptables faites hors connexion.
///
/// Panne de réseau : l'erreur remonte, l'entrée reste en file (nouvel essai).
/// Refus du serveur (période clôturée entre-temps, droits…) : [RejetDefinitif]
/// avec l'explication lisible — l'entrée n'est plus rejouée et l'utilisateur
/// la voit dans le bandeau. Le serveur reconnaît la clé de l'appareil : un
/// envoi répété ne crée jamais de doublon.
class RejeuComptabilite {
  const RejeuComptabilite(this._client);

  final SupabaseClient _client;

  Future<void> rejouer(SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      switch (entree.entite) {
        case DonsHorsLigneRepository.entiteDon:
          await _client.rpc<dynamic>('enregistrer_don', params: p);
        case DonsHorsLigneRepository.entiteAnnulation:
          try {
            await _client.rpc<dynamic>('annuler_don', params: p);
          } on PostgrestException catch (e) {
            // Déjà annulé (par exemple depuis un autre appareil) : c'est fait.
            if (!e.message.startsWith('DON_DEJA_ANNULE')) rethrow;
          }
        case DonsHorsLigneRepository.entiteDonateur:
          await _client.from('donateurs').upsert(p);
        case DonsHorsLigneRepository.entiteArchivageDonateur:
          await _client.from('donateurs').update({'deleted_at': p['deleted_at']}).eq('id', p['id'] as String);
        case DonsHorsLigneRepository.entiteAffectation:
          await _client.from('affectations_dons').upsert(p);
        case DonsHorsLigneRepository.entiteEngagement:
          await _client.from('engagements_dons').upsert(p);
        case PiecesHorsLigneRepository.entite:
          await _client.rpc<dynamic>('enregistrer_piece_hors_ligne', params: p);
        case EtatsFinanciersHorsLigneRepository.entite:
          await _client.rpc<dynamic>('enregistrer_note_annexe', params: p);
      }
    } on PostgrestException catch (e) {
      final code = e.message.trim().split(RegExp(r'\s+')).first;
      final metier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(code);
      // Refus métier ou de droits : définitif. Autre erreur serveur : on
      // réessaiera (incident passager).
      if (metier || e.code == '42501' || e.code == '23503' || e.code == '23505') {
        throw RejetDefinitif(metier ? code : (e.code ?? 'REFUS'), messageRejet(entree.entite, metier ? code : 'REFUS'));
      }
      rethrow;
    }
  }

  /// Explication d'un refus, dans les mots de l'écran concerné.
  static String messageRejet(String entite, String code) {
    if (code == 'REFUS' || code == 'COMPTABLE_ECRITURE_REQUIS' || code == 'ACCES_REFUSE') {
      return 'Le serveur a refusé l\'opération : vos droits de comptabilité ont peut-être changé.';
    }
    if (entite == PiecesHorsLigneRepository.entite) return ErreurPiecesComptables(code).messageUtilisateur;
    if (entite == EtatsFinanciersHorsLigneRepository.entite) return ErreurEtatsFinanciers(code).messageUtilisateur;
    return ErreurDons(code).messageUtilisateur;
  }

  /// Ce que l'utilisateur avait saisi, pour le reconnaître dans la liste
  /// des refus.
  static String libelle(SyncEntree entree) {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    String date(Object? iso) {
      if (iso is! String) return '';
      final d = DateTime.parse(iso);
      return ' du ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    }

    return switch (entree.entite) {
      DonsHorsLigneRepository.entiteDon =>
        '${NatureDon.depuisCode(p['p_nature'] as String?).libelle} de ${formaterMontant((p['p_montant'] as num).toDouble())}'
            '${date(p['p_date'])}${p['p_numero_provisoire'] == null ? '' : ' (reçu ${p['p_numero_provisoire']})'}',
      DonsHorsLigneRepository.entiteAnnulation => 'Annulation d\'un don',
      DonsHorsLigneRepository.entiteDonateur => 'Donateur ${p['nom'] ?? ''}',
      DonsHorsLigneRepository.entiteArchivageDonateur => 'Archivage d\'un donateur',
      DonsHorsLigneRepository.entiteAffectation => 'Campagne « ${p['libelle'] ?? ''} »',
      DonsHorsLigneRepository.entiteEngagement => 'Engagement d\'un donateur',
      PiecesHorsLigneRepository.entite => 'Brouillard « ${p['p_libelle'] ?? ''} »${date(p['p_date'])}',
      EtatsFinanciersHorsLigneRepository.entite => 'Note annexe rédigée',
      _ => 'Opération comptable',
    };
  }
}
