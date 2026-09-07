/// Projection cliente de `public.classes` (M5) — structure d'accueil des élèves.
class Classe {
  const Classe({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.code,
    required this.nom,
    this.uniteId,
    this.niveauId,
    this.capacite,
    this.enseignantPrincipalId,
    this.actif = true,
  });

  factory Classe.depuisJson(Map<String, dynamic> json) {
    return Classe(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      code: json['code'] as String,
      nom: json['nom'] as String,
      uniteId: json['unite_id'] as String?,
      niveauId: json['niveau_id'] as String?,
      capacite: json['capacite'] as int?,
      enseignantPrincipalId: json['enseignant_principal_id'] as String?,
      actif: json['actif'] as bool? ?? true,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'code': code,
        'nom': nom,
        'unite_id': uniteId,
        'niveau_id': niveauId,
        'capacite': capacite,
        'enseignant_principal_id': enseignantPrincipalId,
        'actif': actif,
      };

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String code;
  final String nom;
  final String? uniteId;
  final String? niveauId;
  final int? capacite;
  final String? enseignantPrincipalId;
  final bool actif;
}
