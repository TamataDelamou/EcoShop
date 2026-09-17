/// Projection cliente de `public.commercants` limitée aux champs de
/// validation GSG (cahier §27.2, §30.2 — palier 1, global, indépendant de
/// tout établissement). `statutValidation` : `'en_attente'`, `'valide'` ou
/// `'refuse'`.
class VendeurValidation {
  const VendeurValidation({
    required this.commercantId,
    required this.nom,
    this.raisonSociale,
    required this.statutValidation,
    this.motifRefus,
    this.valideLe,
  });

  factory VendeurValidation.depuisJson(Map<String, dynamic> json) => VendeurValidation(
        commercantId: json['id'] as String,
        nom: json['nom'] as String,
        raisonSociale: json['raison_sociale'] as String?,
        statutValidation: json['statut_validation'] as String? ?? 'en_attente',
        motifRefus: json['motif_refus'] as String?,
        valideLe: json['valide_le'] == null ? null : DateTime.parse(json['valide_le'] as String),
      );

  final String commercantId;
  final String nom;
  final String? raisonSociale;
  final String statutValidation;
  final String? motifRefus;
  final DateTime? valideLe;
}
