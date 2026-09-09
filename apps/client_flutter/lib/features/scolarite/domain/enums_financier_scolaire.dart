/// Enums SQL de M15quater (`type_frais_scolaire`, `moyen_paiement`,
/// `statut_encaissement`).
library;

enum TypeFraisScolaire {
  scolarite('scolarite'),
  inscription('inscription'),
  cantine('cantine'),
  transport('transport'),
  autre('autre');

  const TypeFraisScolaire(this.code);
  final String code;

  static TypeFraisScolaire depuisCode(String? code) {
    for (final v in TypeFraisScolaire.values) {
      if (v.code == code) return v;
    }
    return TypeFraisScolaire.scolarite;
  }

  String get libelle => switch (this) {
        scolarite => 'Scolarité',
        inscription => 'Frais d\'inscription',
        cantine => 'Cantine',
        transport => 'Transport',
        autre => 'Autre',
      };
}

enum MoyenPaiement {
  especes('especes'),
  mobileMoney('mobile_money'),
  virement('virement'),
  cheque('cheque'),
  autre('autre');

  const MoyenPaiement(this.code);
  final String code;

  static MoyenPaiement depuisCode(String? code) {
    for (final v in MoyenPaiement.values) {
      if (v.code == code) return v;
    }
    return MoyenPaiement.especes;
  }

  String get libelle => switch (this) {
        especes => 'Espèces',
        mobileMoney => 'Mobile Money',
        virement => 'Virement',
        cheque => 'Chèque',
        autre => 'Autre',
      };
}

enum StatutEncaissement {
  valide('valide'),
  annule('annule');

  const StatutEncaissement(this.code);
  final String code;

  static StatutEncaissement depuisCode(String? code) {
    for (final v in StatutEncaissement.values) {
      if (v.code == code) return v;
    }
    return StatutEncaissement.valide;
  }
}
