/// Enums SQL de M6 (`type_evaluation`, `statut_evaluation`, `type_bulletin`,
/// `statut_bulletin`, `type_appreciation`, `ton_appreciation`).
library;

enum TypeEvaluation {
  devoir('devoir'),
  interrogation('interrogation'),
  controle('controle'),
  examenBlanc('examen_blanc'),
  composition('composition'),
  tp('tp'),
  autre('autre');

  const TypeEvaluation(this.code);
  final String code;

  static TypeEvaluation depuisCode(String? code) {
    for (final v in TypeEvaluation.values) {
      if (v.code == code) return v;
    }
    return TypeEvaluation.controle;
  }

  String get libelle => switch (this) {
        devoir => 'Devoir',
        interrogation => 'Interrogation',
        controle => 'Contrôle',
        examenBlanc => 'Examen blanc',
        composition => 'Composition',
        tp => 'TP',
        autre => 'Autre',
      };
}

enum StatutEvaluation {
  brouillon('brouillon'),
  publiee('publiee'),
  cloturee('cloturee');

  const StatutEvaluation(this.code);
  final String code;

  static StatutEvaluation depuisCode(String? code) {
    for (final v in StatutEvaluation.values) {
      if (v.code == code) return v;
    }
    return StatutEvaluation.brouillon;
  }
}

enum TypeBulletin {
  trimestriel('trimestriel'),
  semestriel('semestriel'),
  annuel('annuel');

  const TypeBulletin(this.code);
  final String code;

  static TypeBulletin depuisCode(String? code) {
    for (final v in TypeBulletin.values) {
      if (v.code == code) return v;
    }
    return TypeBulletin.trimestriel;
  }
}

enum StatutBulletin {
  brouillon('brouillon'),
  publie('publie'),
  archive('archive');

  const StatutBulletin(this.code);
  final String code;

  static StatutBulletin depuisCode(String? code) {
    for (final v in StatutBulletin.values) {
      if (v.code == code) return v;
    }
    return StatutBulletin.brouillon;
  }
}

enum TypeAppreciation {
  generale('generale'),
  matiere('matiere'),
  conseil('conseil');

  const TypeAppreciation(this.code);
  final String code;

  static TypeAppreciation depuisCode(String? code) {
    for (final v in TypeAppreciation.values) {
      if (v.code == code) return v;
    }
    return TypeAppreciation.generale;
  }
}

enum TonAppreciation {
  positif('positif'),
  neutre('neutre'),
  negatif('negatif');

  const TonAppreciation(this.code);
  final String code;

  static TonAppreciation? depuisCode(String? code) {
    for (final v in TonAppreciation.values) {
      if (v.code == code) return v;
    }
    return null;
  }
}
