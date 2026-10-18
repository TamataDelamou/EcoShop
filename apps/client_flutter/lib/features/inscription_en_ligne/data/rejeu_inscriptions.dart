import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/inscription_en_ligne.dart';
import 'inscription_hors_ligne_repository.dart';
import 'supabase_inscription_en_ligne_repository.dart';

/// Rejoue au serveur les opérations d'inscription faites hors connexion.
///
/// Panne de réseau : l'erreur remonte, l'entrée reste en file. Refus du
/// serveur (date limite dépassée de plus de 7 jours, droits…) :
/// [RejetDefinitif] avec une explication lisible, affichée dans le bandeau.
/// Une pièce attend que son dossier soit arrivé ; si le dossier a été
/// refusé, la pièce l'est aussi.
class RejeuInscriptions {
  const RejeuInscriptions(this._client, this._file);

  final SupabaseClient _client;
  final DriftSyncRepository _file;

  Future<void> rejouer(SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      switch (entree.entite) {
        case InscriptionHorsLigneRepository.entiteDemande:
          final params = Map<String, dynamic>.of(p)..remove('_affichage');
          await _client.rpc<dynamic>('soumettre_demande_inscription', params: params);
        case InscriptionHorsLigneRepository.entitePiece:
          final demandeId = p['demande_id'] as String;
          final recue = await _client.from('demandes_inscription').select('id').eq('id', demandeId).maybeSingle();
          if (recue == null) {
            final dossierRefuse = (await _file.entreesRejetees())
                .any((e) => e.entite == InscriptionHorsLigneRepository.entiteDemande && e.id == demandeId);
            if (dossierRefuse) {
              throw const RejetDefinitif('DOSSIER_REFUSE', 'Le dossier de cette pièce a été refusé par le serveur.');
            }
            // Le dossier n'est pas encore arrivé : nouvel essai plus tard.
            throw StateError('DOSSIER_PAS_ENCORE_RECU');
          }
          await SupabaseInscriptionEnLigneRepository.deposerPieceBrute(
            _client,
            demandeId,
            p['code'] as String,
            base64Decode(p['octets'] as String),
            p['extension'] as String? ?? 'jpg',
          );
        case InscriptionHorsLigneRepository.entiteRetrait:
          try {
            await _client.rpc<dynamic>('retirer_demande_inscription', params: p);
          } on PostgrestException catch (e) {
            // Déjà clos (inscrit, refusé, expiré…) : plus rien à retirer.
            if (!e.message.startsWith('DEMANDE_CLOSE')) rethrow;
          }
        case InscriptionHorsLigneRepository.entiteDecision:
          await _client.rpc<dynamic>('traiter_demande_inscription', params: p);
        case InscriptionHorsLigneRepository.entiteGuichet:
          await _client.rpc<dynamic>('finaliser_inscription_guichet', params: p);
        case InscriptionHorsLigneRepository.entiteCampagne:
          await _client.rpc<dynamic>('enregistrer_campagne_inscription', params: p);
      }
    } on PostgrestException catch (e) {
      final code = SupabaseInscriptionEnLigneRepository.codeMetier(e.message);
      if (code != null || e.code == '42501' || e.code == '23503' || e.code == '23505') {
        final c = code ?? 'ACCES_REFUSE';
        throw RejetDefinitif(c, ErreurInscriptionEnLigne(c).messageUtilisateur);
      }
      rethrow;
    } on StorageException catch (e) {
      if (e.statusCode == '403' || e.statusCode == '413') {
        final c = e.statusCode == '413' ? 'FICHIER_TROP_LOURD' : 'ACCES_REFUSE';
        throw RejetDefinitif(c, ErreurInscriptionEnLigne(c).messageUtilisateur);
      }
      rethrow;
    } on ErreurInscriptionEnLigne catch (e) {
      throw RejetDefinitif(e.code, e.messageUtilisateur);
    }
  }

  /// Ce que l'utilisateur avait saisi, pour le reconnaître dans les refus.
  static String libelle(SyncEntree entree) {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    switch (entree.entite) {
      case InscriptionHorsLigneRepository.entiteDemande:
        final a = (p['_affichage'] as Map<String, dynamic>?) ?? const {};
        final qui = [a['prenom'], a['nom']].whereType<String>().join(' ');
        final quoi = a['type'] == 'reinscription' ? 'Réinscription' : "Demande d'inscription";
        return '$quoi${qui.isEmpty ? '' : ' de $qui'} (dossier ${p['p_numero_provisoire'] ?? '—'})';
      case InscriptionHorsLigneRepository.entitePiece:
        return 'Pièce « ${p['code']} » d\'un dossier d\'inscription';
      case InscriptionHorsLigneRepository.entiteRetrait:
        return "Retrait d'un dossier d'inscription";
      case InscriptionHorsLigneRepository.entiteDecision:
        return "Décision sur un dossier d'inscription";
      case InscriptionHorsLigneRepository.entiteGuichet:
        return 'Paiement au guichet (${p['p_montant'] ?? 'montant prévu'})';
      case InscriptionHorsLigneRepository.entiteCampagne:
        return "Paramètres de la campagne d'inscription";
    }
    return 'Opération d\'inscription';
  }
}
