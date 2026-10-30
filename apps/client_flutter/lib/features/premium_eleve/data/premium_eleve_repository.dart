import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../domain/premium_eleve.dart';

/// Premium élève (REG-36) : l'état se lit aussi sans réseau (copie de
/// l'appareil) ; le paiement passe par la page CinetPay, en ligne.
/// Aucun portefeuille : on paie un service de la plateforme, rien n'est
/// gardé pour le compte de l'utilisateur.
class PremiumEleveRepository {
  PremiumEleveRepository(this._client, this._lecture);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;

  static const cleMensuel = 'tarif_abonnement_premium_eleve_mensuel';
  static const cleAnnuel = 'tarif_abonnement_premium_eleve_annuel';

  Future<EtatPremium> etat(String ficheEleveId) => _lecture.lire(
        type: 'etat',
        cle: ficheEleveId,
        source: () async {
          final abonnement = await _client
              .from('abonnements_premium_eleve')
              .select('formule, expire_le')
              .eq('fiche_eleve_id', ficheEleveId)
              .maybeSingle();
          final tarifs = await _client
              .from('parametres_globaux')
              .select('cle, valeur')
              .inFilter('cle', [cleMensuel, cleAnnuel, 'devise_defaut', 'quota_tuteur_ia_free_mensuel']);
          return {'abonnement': abonnement, 'tarifs': tarifs};
        },
        decoder: decoder,
      );

  static EtatPremium decoder(Object? json) {
    final j = (json as Map?)?.cast<String, dynamic>() ?? const {};
    final a = (j['abonnement'] as Map?)?.cast<String, dynamic>();
    final valeurs = <String, Object?>{
      for (final t in (j['tarifs'] as List?) ?? const [])
        (t as Map)['cle'] as String: ((t['valeur'] as Map?) ?? const {})['valeur'],
    };
    final devise = valeurs['devise_defaut'];
    return EtatPremium(
      expireLe: a?['expire_le'] == null ? null : DateTime.parse(a!['expire_le'] as String),
      formule: FormulePremium.depuisCode(a?['formule'] as String?),
      tarifMensuel: valeurs[cleMensuel] as num?,
      tarifAnnuel: valeurs[cleAnnuel] as num?,
      devise: devise is String && devise.isNotEmpty ? devise : 'GNF',
      quotaGratuit: (valeurs['quota_tuteur_ia_free_mensuel'] as num?)?.toInt(),
    );
  }

  /// Ouvre un paiement ; renvoie l'adresse de la page CinetPay.
  Future<Uri> payer(String ficheEleveId, FormulePremium formule) async {
    try {
      final reponse = await _client.functions.invoke('initier_paiement_cinetpay', body: {
        'typeObjetPaye': 'abonnement_premium_eleve',
        'beneficiaireFicheEleveId': ficheEleveId,
        'formule': formule.code,
      });
      final url = Uri.tryParse(((reponse.data as Map?)?['urlPaiement'] as String?) ?? '');
      if (url == null || !url.hasScheme) throw const ErreurPremium('URL_PAIEMENT_INDISPONIBLE');
      return url;
    } on ErreurPremium {
      rethrow;
    } on FunctionException catch (e) {
      final detail = e.details;
      final code = detail is Map ? (detail['error'] as String? ?? '') : '';
      throw ErreurPremium(_code(code));
    } catch (e) {
      if (estErreurReseau(e)) throw const ErreurPremium('HORS_LIGNE');
      throw const ErreurPremium('ERREUR_SERVEUR');
    }
  }

  /// « TARIF_NON_CONFIGURE: … » → « TARIF_NON_CONFIGURE ».
  static String _code(String brut) {
    final premier = brut.trim().split(RegExp(r'[\s:]+')).first;
    return premier.isEmpty ? 'ERREUR_SERVEUR' : premier;
  }
}
