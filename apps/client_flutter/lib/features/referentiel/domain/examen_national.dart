/// Projection cliente de `public.examens_nationaux` (M4) — ex. BEPC, BAC, WASSCE.
class ExamenNational {
  const ExamenNational({
    required this.id,
    required this.paysCode,
    required this.code,
    required this.nom,
    this.cycleId,
    this.organisme,
    this.moisSession,
    this.periodicite,
  });

  factory ExamenNational.depuisJson(Map<String, dynamic> json) {
    return ExamenNational(
      id: json['id'] as String,
      paysCode: json['pays_code'] as String,
      code: json['code'] as String,
      nom: json['nom'] as String,
      cycleId: json['cycle_id'] as String?,
      organisme: json['organisme'] as String?,
      moisSession: json['mois_session'] as int?,
      periodicite: json['periodicite'] as String?,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'pays_code': paysCode,
        'code': code,
        'nom': nom,
        'cycle_id': cycleId,
        'organisme': organisme,
        'mois_session': moisSession,
        'periodicite': periodicite,
      };

  final String id;
  final String paysCode;
  final String code;
  final String nom;
  final String? cycleId;
  final String? organisme;
  final int? moisSession;
  final String? periodicite;
}
