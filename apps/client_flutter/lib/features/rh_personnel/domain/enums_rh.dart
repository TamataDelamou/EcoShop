/// Enums SQL de M8 (`type_contrat`, `statut_employe`, `type_conge`,
/// `statut_conge`, `statut_paie`, `type_absence_personnel`).
library;

enum CategorieEmploye {
  enseignant('enseignant'),
  administratif('administratif'),
  direction('direction'),
  personnel('personnel');

  const CategorieEmploye(this.code);
  final String code;

  static CategorieEmploye depuisCode(String? code) {
    for (final v in CategorieEmploye.values) {
      if (v.code == code) return v;
    }
    return CategorieEmploye.personnel;
  }

  String get libelle => switch (this) {
        enseignant => 'Enseignant',
        administratif => 'Administratif',
        direction => 'Direction',
        personnel => 'Personnel',
      };
}

enum StatutEmploye {
  actif('actif'),
  enConge('en_conge'),
  suspendu('suspendu'),
  demissionnaire('demissionnaire'),
  retraite('retraite');

  const StatutEmploye(this.code);
  final String code;

  static StatutEmploye depuisCode(String? code) {
    for (final v in StatutEmploye.values) {
      if (v.code == code) return v;
    }
    return StatutEmploye.actif;
  }

  String get libelle => switch (this) {
        actif => 'Actif',
        enConge => 'En congé',
        suspendu => 'Suspendu',
        demissionnaire => 'Démissionnaire',
        retraite => 'Retraité',
      };
}

enum TypeContrat {
  cdi('cdi'),
  cdd('cdd'),
  vacataire('vacataire'),
  stage('stage'),
  prestataire('prestataire');

  const TypeContrat(this.code);
  final String code;

  static TypeContrat depuisCode(String? code) {
    for (final v in TypeContrat.values) {
      if (v.code == code) return v;
    }
    return TypeContrat.cdd;
  }

  String get libelle => switch (this) {
        cdi => 'CDI',
        cdd => 'CDD',
        vacataire => 'Vacataire',
        stage => 'Stage',
        prestataire => 'Prestataire',
      };
}

enum TypeConge {
  annuel('annuel'),
  maladie('maladie'),
  maternite('maternite'),
  exceptionnel('exceptionnel'),
  sansSolde('sans_solde');

  const TypeConge(this.code);
  final String code;

  static TypeConge depuisCode(String? code) {
    for (final v in TypeConge.values) {
      if (v.code == code) return v;
    }
    return TypeConge.annuel;
  }

  String get libelle => switch (this) {
        annuel => 'Congé annuel',
        maladie => 'Maladie',
        maternite => 'Maternité',
        exceptionnel => 'Exceptionnel',
        sansSolde => 'Sans solde',
      };
}

enum StatutConge {
  demande('demande'),
  valide('valide'),
  refuse('refuse');

  const StatutConge(this.code);
  final String code;

  static StatutConge depuisCode(String? code) {
    for (final v in StatutConge.values) {
      if (v.code == code) return v;
    }
    return StatutConge.demande;
  }

  String get libelle => switch (this) {
        demande => 'Demandé',
        valide => 'Validé',
        refuse => 'Refusé',
      };
}

enum StatutPaie {
  brouillon('brouillon'),
  valide('valide'),
  paye('paye');

  const StatutPaie(this.code);
  final String code;

  static StatutPaie depuisCode(String? code) {
    for (final v in StatutPaie.values) {
      if (v.code == code) return v;
    }
    return StatutPaie.brouillon;
  }

  String get libelle => switch (this) {
        brouillon => 'Brouillon',
        valide => 'Validé',
        paye => 'Payé',
      };
}

enum TypeAbsencePersonnel {
  maladie('maladie'),
  injustifiee('injustifiee'),
  autorisee('autorisee'),
  autre('autre');

  const TypeAbsencePersonnel(this.code);
  final String code;

  static TypeAbsencePersonnel depuisCode(String? code) {
    for (final v in TypeAbsencePersonnel.values) {
      if (v.code == code) return v;
    }
    return TypeAbsencePersonnel.injustifiee;
  }

  String get libelle => switch (this) {
        maladie => 'Maladie',
        injustifiee => 'Injustifiée',
        autorisee => 'Autorisée',
        autre => 'Autre',
      };
}
