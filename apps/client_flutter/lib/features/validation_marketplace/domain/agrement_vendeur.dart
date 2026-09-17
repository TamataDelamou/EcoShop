/// Un vendeur déjà validé par GSG, avec le statut d'agrément (palier 2,
/// cahier §27.2 — chaîne d'agrément multi-établissements) de l'établissement
/// consulté. `statut` : `'en_attente'` (aucune décision prise par cet
/// établissement), `'valide'` ou `'refuse'`.
class AgrementVendeur {
  const AgrementVendeur({
    required this.commercantId,
    required this.nomVendeur,
    required this.statut,
    this.motifRefus,
    this.decideLe,
  });

  final String commercantId;
  final String nomVendeur;
  final String statut;
  final String? motifRefus;
  final DateTime? decideLe;
}
