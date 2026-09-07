/// Enums SQL de M10 (`type_export`, `statut_rapport`, `statut_anomalie`,
/// `statut_recommandation`).
library;

enum TypeExport {
  pdf('pdf'),
  excel('excel'),
  csv('csv'),
  json('json');

  const TypeExport(this.code);
  final String code;

  static TypeExport depuisCode(String? code) {
    for (final v in TypeExport.values) {
      if (v.code == code) return v;
    }
    return TypeExport.pdf;
  }

  String get libelle => switch (this) {
        pdf => 'PDF',
        excel => 'Excel',
        csv => 'CSV',
        json => 'JSON',
      };
}

enum StatutRapport {
  demande('demande'),
  enAttente('en_attente'),
  genere('genere'),
  echec('echec'),
  expire('expire');

  const StatutRapport(this.code);
  final String code;

  static StatutRapport depuisCode(String? code) {
    for (final v in StatutRapport.values) {
      if (v.code == code) return v;
    }
    return StatutRapport.demande;
  }

  String get libelle => switch (this) {
        demande => 'Demandé',
        enAttente => 'En attente',
        genere => 'Généré',
        echec => 'Échec',
        expire => 'Expiré',
      };
}

enum StatutAnomalie {
  ouverte('ouverte'),
  confirmee('confirmee'),
  rejetee('rejetee'),
  traitee('traitee');

  const StatutAnomalie(this.code);
  final String code;

  static StatutAnomalie depuisCode(String? code) {
    for (final v in StatutAnomalie.values) {
      if (v.code == code) return v;
    }
    return StatutAnomalie.ouverte;
  }

  String get libelle => switch (this) {
        ouverte => 'Ouverte',
        confirmee => 'Confirmée',
        rejetee => 'Rejetée',
        traitee => 'Traitée',
      };
}

enum StatutRecommandation {
  proposee('proposee'),
  validee('validee'),
  miseEnOeuvre('mise_en_oeuvre'),
  rejetee('rejetee');

  const StatutRecommandation(this.code);
  final String code;

  static StatutRecommandation depuisCode(String? code) {
    for (final v in StatutRecommandation.values) {
      if (v.code == code) return v;
    }
    return StatutRecommandation.proposee;
  }

  String get libelle => switch (this) {
        proposee => 'Proposée',
        validee => 'Validée',
        miseEnOeuvre => 'Mise en œuvre',
        rejetee => 'Rejetée',
      };
}
