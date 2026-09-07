/// Projection cliente de `public.commercants` (M13) — commerçant externe,
/// hors établissement. Catalogue public, sans notion de tenant.
class Commercant {
  const Commercant({
    required this.id,
    required this.nom,
    this.raisonSociale,
    this.telephone,
    this.email,
    this.actif = true,
  });

  factory Commercant.depuisJson(Map<String, dynamic> json) => Commercant(
        id: json['id'] as String,
        nom: json['nom'] as String,
        raisonSociale: json['raison_sociale'] as String?,
        telephone: json['telephone'] as String?,
        email: json['email'] as String?,
        actif: json['actif'] as bool? ?? true,
      );

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'nom': nom,
        'raison_sociale': raisonSociale,
        'telephone': telephone,
        'email': email,
        'actif': actif,
      };

  final String id;
  final String nom;
  final String? raisonSociale;
  final String? telephone;
  final String? email;
  final bool actif;
}
