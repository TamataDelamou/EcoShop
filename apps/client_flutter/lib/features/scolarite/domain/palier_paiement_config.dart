/// Projection cliente de `public.paliers_paiement_config` (M15quater).
///
/// La somme des pourcentages actifs d'un (établissement, année) ne peut pas
/// dépasser 100 — vérifié côté serveur (`paliers_verifie_somme`), jamais
/// recalculé côté client pour décider d'un blocage.
class PalierPaiementConfig {
  const PalierPaiementConfig({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.nom,
    required this.pourcentage,
    required this.ordre,
    this.dateLimite,
  });

  factory PalierPaiementConfig.depuisJson(Map<String, dynamic> json) {
    return PalierPaiementConfig(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      nom: json['nom'] as String,
      pourcentage: (json['pourcentage'] as num).toDouble(),
      ordre: json['ordre'] as int,
      dateLimite: json['date_limite'] == null ? null : DateTime.parse(json['date_limite'] as String),
    );
  }

  Map<String, dynamic> versJsonEcriture() => {
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'nom': nom,
        'pourcentage': pourcentage,
        'ordre': ordre,
        'date_limite': dateLimite == null
            ? null
            : '${dateLimite!.year.toString().padLeft(4, '0')}-'
                '${dateLimite!.month.toString().padLeft(2, '0')}-'
                '${dateLimite!.day.toString().padLeft(2, '0')}',
      };

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String nom;
  final double pourcentage;
  final int ordre;
  final DateTime? dateLimite;
}
