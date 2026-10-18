/// Objet d'un paiement mobile money — circuit établissement (REG-02).
/// Codes identiques à la colonne `transactions_mobile_money.objet`.
enum ObjetPaiementMobile {
  scolarite('scolarite'),
  commandeMarketplace('commande_marketplace'),

  /// Frais d'inscription d'une demande acceptée (REG-08).
  fraisInscription('frais_inscription');

  const ObjetPaiementMobile(this.code);

  final String code;

  static ObjetPaiementMobile depuisCode(String? code) => ObjetPaiementMobile.values.firstWhere(
        (v) => v.code == code,
        orElse: () => ObjetPaiementMobile.scolarite,
      );
}

/// Statut d'une transaction (`public.statut_paiement`, sous-ensemble utile).
enum StatutTransactionMobile {
  initie('initie'),
  enAttente('en_attente'),
  reussi('reussi'),
  echoue('echoue');

  const StatutTransactionMobile(this.code);

  final String code;

  /// Un statut final ne changera plus : le suivi peut s'arrêter.
  bool get estFinal => this == reussi || this == echoue;

  String get libelle => switch (this) {
        StatutTransactionMobile.initie => 'En attente de validation',
        StatutTransactionMobile.enAttente => 'En cours de confirmation',
        StatutTransactionMobile.reussi => 'Paiement confirmé',
        StatutTransactionMobile.echoue => 'Paiement non abouti',
      };

  static StatutTransactionMobile depuisCode(String? code) => StatutTransactionMobile.values.firstWhere(
        (v) => v.code == code,
        orElse: () => StatutTransactionMobile.initie,
      );
}

/// Projection cliente de `public.transactions_mobile_money` (REG-02).
/// Lecture seule : aucune écriture directe n'est permise par la base, le
/// statut n'évolue que côté serveur (notification Orange reconfirmée).
class TransactionMobileMoney {
  const TransactionMobileMoney({
    required this.id,
    required this.objet,
    required this.montant,
    required this.devise,
    required this.statut,
    required this.creeLe,
    this.referenceOperateur,
    this.message,
    this.traiteLe,
  });

  factory TransactionMobileMoney.depuisJson(Map<String, dynamic> json) => TransactionMobileMoney(
        id: json['id'] as String,
        objet: ObjetPaiementMobile.depuisCode(json['objet'] as String?),
        montant: (json['montant'] as num).toDouble(),
        devise: json['devise'] as String? ?? 'GNF',
        statut: StatutTransactionMobile.depuisCode(json['statut'] as String?),
        creeLe: DateTime.parse(json['created_at'] as String),
        referenceOperateur: json['reference_operateur'] as String?,
        message: json['message'] as String?,
        traiteLe: json['traite_le'] == null ? null : DateTime.parse(json['traite_le'] as String),
      );

  /// Colonnes lues — jamais pay_token ni empreinte du jeton de notification.
  static const colonnes = 'id, objet, montant, devise, statut, reference_operateur, message, created_at, traite_le';

  final String id;
  final ObjetPaiementMobile objet;
  final double montant;
  final String devise;
  final StatutTransactionMobile statut;
  final DateTime creeLe;
  final String? referenceOperateur;
  final String? message;
  final DateTime? traiteLe;
}
