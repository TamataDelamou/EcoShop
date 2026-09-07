/// Ligne du tableau de bord effectifs (RPC `analyser_effectifs`, niveau IA
/// descriptif) — un total par catégorie d'employé.
class EffectifCategorie {
  const EffectifCategorie({
    required this.categorie,
    required this.effectif,
    required this.ancienneteMoyenneJours,
    required this.masseSalarialeBase,
  });

  factory EffectifCategorie.depuisJson(Map<String, dynamic> json) => EffectifCategorie(
        categorie: json['categorie'] as String,
        effectif: (json['effectif'] as num).toInt(),
        ancienneteMoyenneJours: (json['anciennete_moyenne_jours'] as num?)?.toDouble() ?? 0,
        masseSalarialeBase: (json['masse_salariale_base'] as num?)?.toDouble() ?? 0,
      );

  final String categorie;
  final int effectif;
  final double ancienneteMoyenneJours;
  final double masseSalarialeBase;
}
