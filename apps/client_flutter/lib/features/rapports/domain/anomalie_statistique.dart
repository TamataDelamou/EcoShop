import 'enums_rapports.dart';

/// Projection cliente de `public.anomalies_statistiques` (M10) — donnée
/// aberrante détectée par la RPC `detecter_anomalies` (note incohérente,
/// absentéisme excessif…), soumise à validation humaine (`rapports.administrer`
/// pour confirmer/rejeter/traiter). Un signal, jamais une décision automatisée.
class AnomalieStatistique {
  const AnomalieStatistique({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    this.classeId,
    this.ficheEleveId,
    this.employeId,
    required this.type,
    required this.severite,
    required this.description,
    this.valeurObservee,
    this.valeurAttendue,
    this.ecart,
    this.statut = StatutAnomalie.ouverte,
    required this.detecteeLe,
  });

  factory AnomalieStatistique.depuisJson(Map<String, dynamic> json) => AnomalieStatistique(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        classeId: json['classe_id'] as String?,
        ficheEleveId: json['fiche_eleve_id'] as String?,
        employeId: json['employe_id'] as String?,
        type: json['type'] as String,
        severite: json['severite'] as String,
        description: json['description'] as String,
        valeurObservee: (json['valeur_observee'] as num?)?.toDouble(),
        valeurAttendue: (json['valeur_attendue'] as num?)?.toDouble(),
        ecart: (json['ecart'] as num?)?.toDouble(),
        statut: StatutAnomalie.depuisCode(json['statut'] as String?),
        detecteeLe: DateTime.parse(json['detectee_le'] as String),
      );

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String? classeId;
  final String? ficheEleveId;
  final String? employeId;
  final String type;
  final String severite;
  final String description;
  final double? valeurObservee;
  final double? valeurAttendue;
  final double? ecart;
  final StatutAnomalie statut;
  final DateTime detecteeLe;
}
