import 'annee_scolaire.dart';
import 'classe.dart';
import 'periode_scolaire.dart';
import 'unite_operationnelle.dart';

/// Annuaire d'un établissement pour une année scolaire donnée : unités
/// opérationnelles (campus/annexes), années scolaires disponibles, classes et
/// périodes de l'année retenue.
///
/// Regroupé en un seul document de cache (même parti pris que
/// `ArborescencePays` en M4) : l'annuaire se consulte par établissement,
/// jamais table par table.
class StructureEtablissement {
  const StructureEtablissement({
    required this.unites,
    required this.anneesScolaires,
    required this.classes,
    required this.periodes,
  });

  factory StructureEtablissement.depuisJson(Map<String, dynamic> json) {
    return StructureEtablissement(
      unites: (json['unites'] as List<dynamic>)
          .map((e) => UniteOperationnelle.depuisJson(e as Map<String, dynamic>))
          .toList(growable: false),
      anneesScolaires: (json['annees_scolaires'] as List<dynamic>)
          .map((e) => AnneeScolaire.depuisJson(e as Map<String, dynamic>))
          .toList(growable: false),
      classes: (json['classes'] as List<dynamic>)
          .map((e) => Classe.depuisJson(e as Map<String, dynamic>))
          .toList(growable: false),
      periodes: (json['periodes'] as List<dynamic>)
          .map((e) => PeriodeScolaire.depuisJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> versJson() => {
        'unites': unites.map((u) => u.versJson()).toList(growable: false),
        'annees_scolaires':
            anneesScolaires.map((a) => a.versJson()).toList(growable: false),
        'classes': classes.map((c) => c.versJson()).toList(growable: false),
        'periodes': periodes.map((p) => p.versJson()).toList(growable: false),
      };

  final List<UniteOperationnelle> unites;
  final List<AnneeScolaire> anneesScolaires;
  final List<Classe> classes;
  final List<PeriodeScolaire> periodes;

  AnneeScolaire? get anneeCourante {
    for (final annee in anneesScolaires) {
      if (annee.courante) return annee;
    }
    return anneesScolaires.isEmpty ? null : anneesScolaires.first;
  }

  List<PeriodeScolaire> get periodesTriees {
    final liste = List<PeriodeScolaire>.from(periodes);
    liste.sort((a, b) => a.ordre.compareTo(b.ordre));
    return liste;
  }
}
