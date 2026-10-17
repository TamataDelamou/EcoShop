/// Rapprochement d'une journée (RPC `rapprochement_mobile_money`, REG-02 L7) :
/// paiements confirmés par Orange comparés aux écritures qu'ils ont produites.
/// Calculé côté serveur ; à confronter au relevé Orange Money du même jour.
class RapprochementMobileMoney {
  const RapprochementMobileMoney({
    required this.jour,
    required this.devise,
    required this.nombreConfirmes,
    required this.montantConfirme,
    required this.montantScolarite,
    required this.montantMarketplace,
    required this.nonAboutis,
    required this.enCours,
    required this.anomalies,
  });

  factory RapprochementMobileMoney.depuisJson(Map<String, dynamic> json) {
    final confirmes = json['confirmes'] as Map<String, dynamic>;
    return RapprochementMobileMoney(
      jour: DateTime.parse(json['jour'] as String),
      devise: json['devise'] as String? ?? 'GNF',
      nombreConfirmes: (confirmes['nombre'] as num).toInt(),
      montantConfirme: (confirmes['montant'] as num).toDouble(),
      montantScolarite: (confirmes['scolarite'] as num).toDouble(),
      montantMarketplace: (confirmes['marketplace'] as num).toDouble(),
      nonAboutis: (json['non_aboutis'] as num).toInt(),
      enCours: (json['en_cours'] as num).toInt(),
      anomalies: [
        for (final a in (json['anomalies'] as List<dynamic>? ?? const []))
          AnomalieRapprochement.depuisJson(a as Map<String, dynamic>),
      ],
    );
  }

  final DateTime jour;
  final String devise;
  final int nombreConfirmes;
  final double montantConfirme;
  final double montantScolarite;
  final double montantMarketplace;
  final int nonAboutis;
  final int enCours;
  final List<AnomalieRapprochement> anomalies;
}

class AnomalieRapprochement {
  const AnomalieRapprochement({required this.type, required this.montant, this.reference});

  factory AnomalieRapprochement.depuisJson(Map<String, dynamic> json) => AnomalieRapprochement(
        type: json['type'] as String,
        montant: (json['montant'] as num?)?.toDouble() ?? 0,
        reference: (json['reference_operateur'] ?? json['reference_paiement']) as String?,
      );

  final String type;
  final double montant;
  final String? reference;

  String get libelle => switch (type) {
        'PAIEMENT_SANS_ECRITURE' => 'Paiement confirmé par Orange sans écriture valide dans EcoShop',
        'ENCAISSEMENT_OM_SANS_TRANSACTION' => 'Encaissement « Orange Money » sans paiement en ligne correspondant',
        'ENCAISSEMENT_OM_ANNULE' => 'Encaissement automatique annulé alors que l’argent est arrivé chez Orange',
        _ => 'Écart à vérifier',
      };
}
