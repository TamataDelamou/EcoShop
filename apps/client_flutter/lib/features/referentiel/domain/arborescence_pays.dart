import 'cycle_educatif.dart';
import 'examen_national.dart';
import 'niveau_educatif.dart';

/// Sous-arbre du référentiel pour un pays : cycles, niveaux et examens.
///
/// Regroupé en une seule lecture/mise en cache pour correspondre à l'unité
/// naturelle de consultation hors-ligne (un pays à la fois), plutôt que de
/// multiplier les allers-retours par table.
class ArborescencePays {
  const ArborescencePays({
    required this.cycles,
    required this.niveaux,
    required this.examens,
  });

  factory ArborescencePays.depuisJson(Map<String, dynamic> json) {
    return ArborescencePays(
      cycles: (json['cycles'] as List<dynamic>)
          .map((e) => CycleEducatif.depuisJson(e as Map<String, dynamic>))
          .toList(growable: false),
      niveaux: (json['niveaux'] as List<dynamic>)
          .map((e) => NiveauEducatif.depuisJson(e as Map<String, dynamic>))
          .toList(growable: false),
      examens: (json['examens'] as List<dynamic>)
          .map((e) => ExamenNational.depuisJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> versJson() => {
        'cycles': cycles.map((c) => c.versJson()).toList(growable: false),
        'niveaux': niveaux.map((n) => n.versJson()).toList(growable: false),
        'examens': examens.map((e) => e.versJson()).toList(growable: false),
      };

  final List<CycleEducatif> cycles;
  final List<NiveauEducatif> niveaux;
  final List<ExamenNational> examens;

  /// Niveaux d'un cycle donné, triés par [NiveauEducatif.ordre].
  List<NiveauEducatif> niveauxDuCycle(String cycleId) {
    final liste = niveaux.where((n) => n.cycleId == cycleId).toList();
    liste.sort((a, b) => a.ordre.compareTo(b.ordre));
    return liste;
  }

  /// Cycles triés par [CycleEducatif.ordre].
  List<CycleEducatif> get cyclesTries {
    final liste = List<CycleEducatif>.from(cycles);
    liste.sort((a, b) => a.ordre.compareTo(b.ordre));
    return liste;
  }
}
