import 'enums_rapports.dart';

/// Projection cliente de `public.recommandations_strategiques` (M10) —
/// action corrective proposée par la RPC `recommander_actions` (tutorat,
/// renforcement) pour une classe à risque, validée par la direction/RH
/// (`rapports.administrer`). Signal IA, jamais une décision automatisée.
class RecommandationStrategique {
  const RecommandationStrategique({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    this.classeId,
    required this.type,
    required this.titre,
    required this.description,
    required this.priorite,
    this.statut = StatutRecommandation.proposee,
    required this.creeLe,
  });

  factory RecommandationStrategique.depuisJson(Map<String, dynamic> json) => RecommandationStrategique(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        classeId: json['classe_id'] as String?,
        type: json['type'] as String,
        titre: json['titre'] as String,
        description: json['description'] as String,
        priorite: json['priorite'] as String,
        statut: StatutRecommandation.depuisCode(json['statut'] as String?),
        creeLe: DateTime.parse(json['cree_le'] as String),
      );

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String? classeId;
  final String type;
  final String titre;
  final String description;
  final String priorite;
  final StatutRecommandation statut;
  final DateTime creeLe;
}
