/// Ligne renvoyée par la RPC `detecter_anomalies_commandes` (M13) — signal IA
/// non bloquant, à valider humainement (aucune action automatique).
class AnomalieCommande {
  const AnomalieCommande({
    required this.commandeId,
    required this.reference,
    required this.montantTotal,
    required this.paiementsEnAttente,
    required this.anomalie,
  });

  factory AnomalieCommande.depuisJson(Map<String, dynamic> json) => AnomalieCommande(
        commandeId: json['commande_id'] as String,
        reference: json['reference'] as String,
        montantTotal: (json['montant_total'] as num).toDouble(),
        paiementsEnAttente: (json['paiements_en_attente'] as num).toInt(),
        anomalie: json['anomalie'] as String,
      );

  final String commandeId;
  final String reference;
  final double montantTotal;
  final int paiementsEnAttente;
  final String anomalie;

  String get libelle => switch (anomalie) {
        'montant_eleve' => 'Montant élevé',
        'paiement_attente_multiple' => 'Paiements multiples en attente',
        _ => anomalie,
      };
}
