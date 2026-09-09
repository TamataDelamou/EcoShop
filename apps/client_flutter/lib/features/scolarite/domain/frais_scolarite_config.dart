/// Projection cliente de `public.frais_scolarite_config` (M15quater).
///
/// [niveauId] à `null` = tarif par défaut de l'établissement pour l'année ;
/// un tarif par niveau spécifique le remplace quand il existe
/// (`solde_scolarite`, résolution côté serveur).
class FraisScolariteConfig {
  const FraisScolariteConfig({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.montantAnnuel,
    this.niveauId,
    this.fraisInscription = 0,
  });

  factory FraisScolariteConfig.depuisJson(Map<String, dynamic> json) {
    return FraisScolariteConfig(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      niveauId: json['niveau_id'] as String?,
      montantAnnuel: (json['montant_annuel'] as num).toDouble(),
      fraisInscription: (json['frais_inscription'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> versJsonEcriture() => {
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'niveau_id': niveauId,
        'montant_annuel': montantAnnuel,
        'frais_inscription': fraisInscription,
      };

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String? niveauId;
  final double montantAnnuel;
  final double fraisInscription;

  bool get estTarifParDefaut => niveauId == null;
}
