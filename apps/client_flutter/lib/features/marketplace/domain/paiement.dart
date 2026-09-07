import 'enums_marketplace.dart';

/// Projection cliente de `public.paiements` (M13) — port agnostique : la
/// création ici initie un enregistrement `statut = initie` ; l'exécution
/// réelle (appel CinetPay/Mobile Money) est un adaptateur Edge Function
/// différé au module M14 (hors périmètre de ce module).
class Paiement {
  const Paiement({
    required this.id,
    required this.etablissementId,
    required this.commandeId,
    this.sousCompteId,
    required this.fournisseur,
    required this.montant,
    this.statut = StatutPaiement.initie,
    this.referenceFournisseur,
    this.message,
  });

  factory Paiement.depuisJson(Map<String, dynamic> json) => Paiement(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        commandeId: json['commande_id'] as String,
        sousCompteId: json['sous_compte_id'] as String?,
        fournisseur: TypeFournisseurPaiement.depuisCode(json['fournisseur'] as String?),
        montant: (json['montant'] as num).toDouble(),
        statut: StatutPaiement.depuisCode(json['statut'] as String?),
        referenceFournisseur: json['reference_fournisseur'] as String?,
        message: json['message'] as String?,
      );

  /// Colonnes réelles de `public.paiements` — pour l'insert.
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'commande_id': commandeId,
        'sous_compte_id': sousCompteId,
        'fournisseur': fournisseur.code,
        'montant': montant,
        'statut': statut.code,
        'reference_fournisseur': referenceFournisseur,
        'message': message,
      };

  final String id;
  final String etablissementId;
  final String commandeId;
  final String? sousCompteId;
  final TypeFournisseurPaiement fournisseur;
  final double montant;
  final StatutPaiement statut;
  final String? referenceFournisseur;
  final String? message;
}
