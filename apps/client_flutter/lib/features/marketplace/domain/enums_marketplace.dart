/// Fournisseur de paiement — port agnostique (`public.type_fournisseur_paiement`).
enum TypeFournisseurPaiement {
  cinetpay('cinetpay'),
  mobileMoney('mobile_money');

  const TypeFournisseurPaiement(this.code);

  final String code;

  String get libelle => switch (this) {
        TypeFournisseurPaiement.cinetpay => 'CinetPay',
        TypeFournisseurPaiement.mobileMoney => 'Mobile Money',
      };

  static TypeFournisseurPaiement depuisCode(String? code) => TypeFournisseurPaiement.values.firstWhere(
        (v) => v.code == code,
        orElse: () => TypeFournisseurPaiement.cinetpay,
      );
}

/// Statut d'une commande (`public.statut_commande`).
enum StatutCommande {
  brouillon('brouillon'),
  confirmee('confirmee'),
  payee('payee'),
  expediee('expediee'),
  livree('livree'),
  annulee('annulee');

  const StatutCommande(this.code);

  final String code;

  String get libelle => switch (this) {
        StatutCommande.brouillon => 'Brouillon',
        StatutCommande.confirmee => 'Confirmée',
        StatutCommande.payee => 'Payée',
        StatutCommande.expediee => 'Expédiée',
        StatutCommande.livree => 'Livrée',
        StatutCommande.annulee => 'Annulée',
      };

  static StatutCommande depuisCode(String? code) => StatutCommande.values.firstWhere(
        (v) => v.code == code,
        orElse: () => StatutCommande.brouillon,
      );
}

/// Statut d'un paiement (`public.statut_paiement`).
enum StatutPaiement {
  initie('initie'),
  enAttente('en_attente'),
  reussi('reussi'),
  echoue('echoue'),
  rembourse('rembourse');

  const StatutPaiement(this.code);

  final String code;

  String get libelle => switch (this) {
        StatutPaiement.initie => 'Initié',
        StatutPaiement.enAttente => 'En attente',
        StatutPaiement.reussi => 'Réussi',
        StatutPaiement.echoue => 'Échoué',
        StatutPaiement.rembourse => 'Remboursé',
      };

  static StatutPaiement depuisCode(String? code) => StatutPaiement.values.firstWhere(
        (v) => v.code == code,
        orElse: () => StatutPaiement.initie,
      );
}
