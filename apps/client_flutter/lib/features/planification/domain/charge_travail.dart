/// Charge horaire hebdomadaire d'un enseignant (RPC `charger_travail_enseignant`,
/// IA prédictive) — heures planifiées contre volume contractuel (M8).
class ChargeTravailEnseignant {
  const ChargeTravailEnseignant({
    required this.heuresHebdo,
    required this.nbSeances,
    required this.volumeContractuelHebdo,
    required this.surcharge,
  });

  factory ChargeTravailEnseignant.depuisJson(Map<String, dynamic> json) => ChargeTravailEnseignant(
        heuresHebdo: (json['heures_hebdo'] as num).toDouble(),
        nbSeances: json['nb_seances'] as int,
        volumeContractuelHebdo: json['volume_contractuel_hebdo'] as int,
        surcharge: json['surcharge'] as bool,
      );

  final double heuresHebdo;
  final int nbSeances;
  final int volumeContractuelHebdo;
  final bool surcharge;
}

/// Charge horaire hebdomadaire d'une classe (RPC `charger_travail_eleve`, IA
/// prédictive) — seuil d'alerte à 35 h/semaine.
class ChargeTravailEleve {
  const ChargeTravailEleve({
    required this.heuresHebdo,
    required this.nbSeances,
    required this.joursOccupes,
    required this.surcharge,
  });

  factory ChargeTravailEleve.depuisJson(Map<String, dynamic> json) => ChargeTravailEleve(
        heuresHebdo: (json['heures_hebdo'] as num).toDouble(),
        nbSeances: json['nb_seances'] as int,
        joursOccupes: json['jours_occupes'] as int,
        surcharge: json['surcharge'] as bool,
      );

  final double heuresHebdo;
  final int nbSeances;
  final int joursOccupes;
  final bool surcharge;
}
