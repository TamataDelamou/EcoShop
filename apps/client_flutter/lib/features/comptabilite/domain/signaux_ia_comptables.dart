/// Ligne de `detecter_anomalies_comptables` — montant élevé ou double saisie.
///
/// Signaux IA de supervision comptable (M14) — toujours descriptifs, jamais
/// d'écriture générée automatiquement (cahier v4.1, principe transverse IA).
class AnomalieComptable {
  const AnomalieComptable({
    required this.ecritureId,
    required this.dateEcriture,
    required this.libelle,
    required this.montant,
    required this.anomalie,
  });

  factory AnomalieComptable.depuisJson(Map<String, dynamic> json) => AnomalieComptable(
        ecritureId: json['ecriture_id'] as String,
        dateEcriture: DateTime.parse(json['date_ecriture'] as String),
        libelle: json['libelle'] as String,
        montant: (json['montant'] as num).toDouble(),
        anomalie: json['anomalie'] as String,
      );

  final String ecritureId;
  final DateTime dateEcriture;
  final String libelle;
  final double montant;
  final String anomalie;

  String get libelleAnomalie => switch (anomalie) {
        'montant_eleve' => 'Montant élevé',
        'double_saisie' => 'Double saisie suspectée',
        _ => anomalie,
      };
}

/// Point de `predire_tresorerie` — projection linéaire du solde banque/caisse.
class ProjectionTresorerie {
  const ProjectionTresorerie({required this.jour, required this.soldeProjete});

  factory ProjectionTresorerie.depuisJson(Map<String, dynamic> json) => ProjectionTresorerie(
        jour: DateTime.parse(json['jour'] as String),
        soldeProjete: (json['solde_projete'] as num).toDouble(),
      );

  final DateTime jour;
  final double soldeProjete;
}

/// Ligne de `recommander_ecritures` — écriture récurrente détectée (≥ 2 mois
/// distincts), proposée à la ressaisie, jamais rejouée automatiquement.
class EcritureRecommandee {
  const EcritureRecommandee({
    required this.libelle,
    required this.compteDebit,
    required this.compteCredit,
    required this.montant,
    required this.moisDistincts,
  });

  factory EcritureRecommandee.depuisJson(Map<String, dynamic> json) => EcritureRecommandee(
        libelle: json['libelle'] as String,
        compteDebit: json['compte_debit'] as String,
        compteCredit: json['compte_credit'] as String,
        montant: (json['montant'] as num).toDouble(),
        moisDistincts: (json['mois_distincts'] as num).toInt(),
      );

  final String libelle;
  final String compteDebit;
  final String compteCredit;
  final double montant;
  final int moisDistincts;
}

/// Ligne de `analyser_tendances` — charges/produits agrégés par mois.
class TendanceMensuelle {
  const TendanceMensuelle({
    required this.mois,
    required this.totalCharges,
    required this.totalProduits,
    required this.soldeNet,
  });

  factory TendanceMensuelle.depuisJson(Map<String, dynamic> json) => TendanceMensuelle(
        mois: DateTime.parse(json['mois'] as String),
        totalCharges: (json['total_charges'] as num).toDouble(),
        totalProduits: (json['total_produits'] as num).toDouble(),
        soldeNet: (json['solde_net'] as num).toDouble(),
      );

  final DateTime mois;
  final double totalCharges;
  final double totalProduits;
  final double soldeNet;
}
