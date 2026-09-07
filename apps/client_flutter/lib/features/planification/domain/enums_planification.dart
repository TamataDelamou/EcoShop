/// Vocabulaires `CHECK` de M11 (aucun type SQL énuméré natif — la migration
/// utilise des contraintes `check (... in (...))` sur des colonnes `text`).
library;

enum TypeSeance {
  cours('cours'),
  pause('pause'),
  activite('activite'),
  etude('etude'),
  examen('examen');

  const TypeSeance(this.code);
  final String code;

  static TypeSeance depuisCode(String? code) {
    for (final v in TypeSeance.values) {
      if (v.code == code) return v;
    }
    return TypeSeance.cours;
  }

  String get libelle => switch (this) {
        cours => 'Cours',
        pause => 'Pause',
        activite => 'Activité',
        etude => 'Étude',
        examen => 'Examen',
      };
}

enum TypeEvenementAgenda {
  examen('examen'),
  reunion('reunion'),
  conseilClasse('conseil_classe'),
  sortie('sortie'),
  fete('fete'),
  rappel('rappel'),
  autre('autre');

  const TypeEvenementAgenda(this.code);
  final String code;

  static TypeEvenementAgenda depuisCode(String? code) {
    for (final v in TypeEvenementAgenda.values) {
      if (v.code == code) return v;
    }
    return TypeEvenementAgenda.autre;
  }

  String get libelle => switch (this) {
        examen => 'Examen',
        reunion => 'Réunion',
        conseilClasse => 'Conseil de classe',
        sortie => 'Sortie',
        fete => 'Fête',
        rappel => 'Rappel',
        autre => 'Autre',
      };
}

enum StatutProgression {
  planifiee('planifiee'),
  realisee('realisee'),
  reportee('reportee'),
  annulee('annulee'),
  proposee('proposee');

  const StatutProgression(this.code);
  final String code;

  static StatutProgression depuisCode(String? code) {
    for (final v in StatutProgression.values) {
      if (v.code == code) return v;
    }
    return StatutProgression.planifiee;
  }

  String get libelle => switch (this) {
        planifiee => 'Planifiée',
        realisee => 'Réalisée',
        reportee => 'Reportée',
        annulee => 'Annulée',
        proposee => 'Proposée (IA)',
      };
}
