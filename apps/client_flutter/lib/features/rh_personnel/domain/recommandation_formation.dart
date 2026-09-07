/// Recommandation de formation (RPC `recommander_formation`, niveau IA
/// prescriptif) — matière du référentiel M4 non encore couverte par
/// l'enseignant sur l'année donnée. Signal, jamais une obligation : la
/// décision d'inscrire l'employé à une formation reste RH/direction.
class RecommandationFormation {
  const RecommandationFormation({
    required this.programmeMatiereId,
    required this.code,
    required this.libelle,
    required this.raison,
  });

  factory RecommandationFormation.depuisJson(Map<String, dynamic> json) => RecommandationFormation(
        programmeMatiereId: json['programme_matiere_id'] as String,
        code: json['code'] as String,
        libelle: json['libelle'] as String,
        raison: json['raison'] as String,
      );

  final String programmeMatiereId;
  final String code;
  final String libelle;
  final String raison;
}
