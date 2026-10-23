import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/securite/gardien_actions_sensibles.dart';

import '../domain/paiement_mobile_repository.dart';
import '../domain/rapprochement_mobile_money.dart';
import '../domain/transaction_mobile_money.dart';

/// Implémentation Supabase du port [PaiementMobileRepository] (REG-02).
///
/// Le client n'appelle jamais Orange directement : l'initiation passe par
/// l'Edge Function `initier_paiement_orange_money` (JWT du payeur relayé),
/// la lecture par PostgREST sous RLS, l'activation par une RPC réservée à
/// la Direction de l'établissement concerné.
class SupabasePaiementMobileRepository implements PaiementMobileRepository {
  const SupabasePaiementMobileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<InitiationPaiementMobile> initierPaiementOrange({
    required ObjetPaiementMobile objet,
    required String cibleId,
    double? montant,
  }) {
    return avecCode('Payer avec Orange Money', () => _executer(() async {
      final reponse = await _client.functions.invoke(
        'initier_paiement_orange_money',
        body: {
          'objet': objet.code,
          'cibleId': cibleId,
          'montant': ?montant,
        },
      );
      final corps = reponse.data as Map<String, dynamic>;
      final url = Uri.tryParse(corps['urlPaiement'] as String? ?? '');
      if (url == null || !url.hasScheme) {
        throw const ErreurPaiementMobile('URL_PAIEMENT_INDISPONIBLE');
      }
      return InitiationPaiementMobile(
        transactionId: corps['transactionId'] as String,
        urlPaiement: url,
        montant: (corps['montant'] as num).toDouble(),
        devise: corps['devise'] as String? ?? 'GNF',
      );
    }));
  }

  @override
  Future<TransactionMobileMoney> lireTransaction(String transactionId) {
    return _executer(() async {
      final ligne = await _client
          .from('transactions_mobile_money')
          .select(TransactionMobileMoney.colonnes)
          .eq('id', transactionId)
          .single();
      return TransactionMobileMoney.depuisJson(ligne);
    });
  }

  @override
  Future<List<TransactionMobileMoney>> transactionsEtablissement(String etablissementId, {int limite = 50}) {
    return _executer(() async {
      final lignes = await _client
          .from('transactions_mobile_money')
          .select(TransactionMobileMoney.colonnes)
          .eq('etablissement_id', etablissementId)
          .order('created_at', ascending: false)
          .limit(limite);
      return lignes.map(TransactionMobileMoney.depuisJson).toList(growable: false);
    });
  }

  @override
  Future<void> activerOrangeMoney({
    required String etablissementId,
    required String clientId,
    required String clientSecret,
    required String merchantKey,
    required bool production,
  }) {
    return _executer(() async {
      await _client.rpc<dynamic>(
        'enregistrer_identifiants_orange_money',
        params: {
          'p_etablissement_id': etablissementId,
          'p_client_id': clientId.trim(),
          'p_client_secret': clientSecret.trim(),
          'p_merchant_key': merchantKey.trim(),
          'p_environnement': production ? 'production' : 'test',
        },
      );
    });
  }

  @override
  Future<EtatOrangeMoney> etatOrangeMoney(String etablissementId) {
    return _executer(() async {
      final ligne = await _client
          .from('sous_comptes_marchands')
          .select('reference_compte, actif')
          .eq('etablissement_id', etablissementId)
          .eq('fournisseur', 'orange_money_gn')
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (ligne == null) return const EtatOrangeMoney.inactif();
      return EtatOrangeMoney(
        active: ligne['actif'] as bool? ?? false,
        referencePublique: ligne['reference_compte'] as String?,
      );
    });
  }

  @override
  Future<RapprochementMobileMoney> rapprochement(String etablissementId, DateTime jour) {
    return _executer(() async {
      final mois = jour.month.toString().padLeft(2, '0');
      final j = jour.day.toString().padLeft(2, '0');
      final json = await _client.rpc<Map<String, dynamic>>(
        'rapprochement_mobile_money',
        params: {'p_etablissement_id': etablissementId, 'p_jour': '${jour.year}-$mois-$j'},
      );
      return RapprochementMobileMoney.depuisJson(json);
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ErreurPaiementMobile {
      rethrow;
    } on FunctionException catch (e) {
      throw ErreurPaiementMobile(_codeDepuisDetails(e.details), e.reasonPhrase);
    } on PostgrestException catch (e) {
      throw ErreurPaiementMobile(_codeDepuisMessage(e.message), e.message);
    } catch (e) {
      throw ErreurPaiementMobile('ERREUR_RESEAU', e.toString());
    }
  }

  static String _codeDepuisDetails(Object? details) {
    if (details is Map && details['error'] is String) {
      return (details['error'] as String).toUpperCase();
    }
    return 'ERREUR_RESEAU';
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
