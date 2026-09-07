/// Enums SQL de M7 (`statut_presence`, `type_seance`, `type_sanction`,
/// `statut_sanction`, `origine_sanction`, `statut_alerte`, `type_evenement`).
library;

enum StatutPresence {
  present('present'),
  absent('absent'),
  retard('retard'),
  exclu('exclu'),
  dispense('dispense');

  const StatutPresence(this.code);
  final String code;

  static StatutPresence depuisCode(String? code) {
    for (final v in StatutPresence.values) {
      if (v.code == code) return v;
    }
    return StatutPresence.present;
  }

  String get libelle => switch (this) {
        present => 'Présent',
        absent => 'Absent',
        retard => 'Retard',
        exclu => 'Exclu',
        dispense => 'Dispensé',
      };
}

enum TypeSeance {
  demiJournee('demi_journee'),
  cours('cours');

  const TypeSeance(this.code);
  final String code;

  static TypeSeance depuisCode(String? code) {
    for (final v in TypeSeance.values) {
      if (v.code == code) return v;
    }
    return TypeSeance.demiJournee;
  }
}

enum TypeSanction {
  avertissement('avertissement'),
  blame('blame'),
  retenue('retenue'),
  travailInteret('travail_interet'),
  exclusionTemporaire('exclusion_temporaire'),
  conseilDiscipline('conseil_discipline'),
  entretienFamilleEtTutorat('entretien_famille_et_tutorat');

  const TypeSanction(this.code);
  final String code;

  static TypeSanction depuisCode(String? code) {
    for (final v in TypeSanction.values) {
      if (v.code == code) return v;
    }
    return TypeSanction.avertissement;
  }

  String get libelle => switch (this) {
        avertissement => 'Avertissement',
        blame => 'Blâme',
        retenue => 'Retenue',
        travailInteret => "Travail d'intérêt",
        exclusionTemporaire => 'Exclusion temporaire',
        conseilDiscipline => 'Conseil de discipline',
        entretienFamilleEtTutorat => 'Entretien famille & tutorat',
      };
}

enum StatutSanction {
  proposee('proposee'),
  notifiee('notifiee'),
  executee('executee'),
  annulee('annulee');

  const StatutSanction(this.code);
  final String code;

  static StatutSanction depuisCode(String? code) {
    for (final v in StatutSanction.values) {
      if (v.code == code) return v;
    }
    return StatutSanction.proposee;
  }
}

enum OrigineSanction {
  humaine('humaine'),
  ia('ia');

  const OrigineSanction(this.code);
  final String code;

  static OrigineSanction depuisCode(String? code) {
    for (final v in OrigineSanction.values) {
      if (v.code == code) return v;
    }
    return OrigineSanction.humaine;
  }
}

enum StatutAlerte {
  ouverte('ouverte'),
  transmise('transmise'),
  traitee('traitee'),
  ignoree('ignoree');

  const StatutAlerte(this.code);
  final String code;

  static StatutAlerte depuisCode(String? code) {
    for (final v in StatutAlerte.values) {
      if (v.code == code) return v;
    }
    return StatutAlerte.ouverte;
  }
}

enum TypeEvenement {
  ferie('ferie'),
  vacances('vacances'),
  greve('greve'),
  meteo('meteo'),
  manifestation('manifestation'),
  examen('examen'),
  sortie('sortie');

  const TypeEvenement(this.code);
  final String code;

  static TypeEvenement depuisCode(String? code) {
    for (final v in TypeEvenement.values) {
      if (v.code == code) return v;
    }
    return TypeEvenement.manifestation;
  }
}
