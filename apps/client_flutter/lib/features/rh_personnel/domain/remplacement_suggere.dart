/// Suggestion de remplacement (RPC `optimiser_remplacements`, niveau IA
/// prescriptif) — pour un enseignant absent à une date donnée, le remplaçant
/// actif le moins chargé. Signal d'aide à la décision : l'affectation
/// effective reste une action humaine (RH/direction), aucune écriture n'est
/// déclenchée automatiquement.
class RemplacementSuggere {
  const RemplacementSuggere({
    required this.employeAbsentId,
    required this.absentMatricule,
    required this.remplacantId,
    required this.remplacantMatricule,
  });

  factory RemplacementSuggere.depuisJson(Map<String, dynamic> json) => RemplacementSuggere(
        employeAbsentId: json['employe_absent_id'] as String,
        absentMatricule: json['absent_matricule'] as String,
        remplacantId: json['remplacant_id'] as String,
        remplacantMatricule: json['remplacant_matricule'] as String,
      );

  final String employeAbsentId;
  final String absentMatricule;
  final String remplacantId;
  final String remplacantMatricule;
}
