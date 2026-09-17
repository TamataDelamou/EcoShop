import 'agrement_vendeur.dart';
import 'vendeur_validation.dart';

/// Erreur métier ou réseau du port [ValidationMarketplaceRepository]. Codes
/// serveur attendus : `PERMISSION_REFUSEE`, `DECISION_INVALIDE`,
/// `COMMERCANT_INTROUVABLE`, `VENDEUR_NON_VALIDE_GSG`.
class ErreurValidationMarketplace implements Exception {
  const ErreurValidationMarketplace(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurValidationMarketplace($code)';
}

/// Port de la validation vendeur (GSG) + agrément établissement <-> vendeur
/// (Direction) avant activation marketplace (cahier §27.1-27.2, §30.1-30.2).
///
/// Deux paliers distincts, jamais confondus : [validerVendeur] est réservée
/// à l'Administrateur GSG (compte Vendeur, global) ; [deciderAgrement] est
/// réservée à la Direction de l'établissement concerné (affiliation
/// vendeur <-> établissement, refusée tant que le vendeur n'est pas déjà
/// validé par GSG).
abstract interface class ValidationMarketplaceRepository {
  /// Tous les commerçants (vue GSG), avec leur statut de validation.
  Future<List<VendeurValidation>> vendeurs();

  Future<void> validerVendeur({
    required String commercantId,
    required String decision,
    String? motif,
  });

  /// Vendeurs déjà validés par GSG, avec le statut d'agrément de
  /// [etablissementId] (`'en_attente'` si l'établissement ne s'est pas
  /// encore prononcé).
  Future<List<AgrementVendeur>> agrementsPourEtablissement(String etablissementId);

  Future<void> deciderAgrement({
    required String commercantId,
    required String etablissementId,
    required String decision,
    String? motif,
  });
}
