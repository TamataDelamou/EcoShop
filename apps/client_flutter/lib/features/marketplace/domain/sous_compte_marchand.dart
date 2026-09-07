import 'enums_marketplace.dart';

/// Projection cliente de `public.sous_comptes_marchands` (M13) — identifiant
/// de paiement PUBLIC (`referenceCompte`, un merchant id) par établissement.
/// Aucun secret n'est jamais transporté ni affiché ici (clés API/tokens
/// vivent en Edge Function / Vault, hors du client).
class SousCompteMarchand {
  const SousCompteMarchand({
    required this.id,
    required this.etablissementId,
    required this.fournisseur,
    required this.libelle,
    required this.referenceCompte,
    this.actif = true,
  });

  factory SousCompteMarchand.depuisJson(Map<String, dynamic> json) => SousCompteMarchand(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        fournisseur: TypeFournisseurPaiement.depuisCode(json['fournisseur'] as String?),
        libelle: json['libelle'] as String,
        referenceCompte: json['reference_compte'] as String,
        actif: json['actif'] as bool? ?? true,
      );

  /// Colonnes réelles de `public.sous_comptes_marchands` — pour l'upsert
  /// (contrainte unique `(etablissement_id, fournisseur)`).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'fournisseur': fournisseur.code,
        'libelle': libelle,
        'reference_compte': referenceCompte,
        'actif': actif,
      };

  final String id;
  final String etablissementId;
  final TypeFournisseurPaiement fournisseur;
  final String libelle;
  final String referenceCompte;
  final bool actif;
}
