import 'filiere_educative.dart';
import 'programme_matiere.dart';
import 'programme_officiel.dart';

/// Sous-arbre du référentiel pour un niveau : filières, programmes et matières.
class ArborescenceNiveau {
  const ArborescenceNiveau({
    required this.filieres,
    required this.programmes,
    required this.matieres,
  });

  factory ArborescenceNiveau.depuisJson(Map<String, dynamic> json) {
    return ArborescenceNiveau(
      filieres: (json['filieres'] as List<dynamic>)
          .map((e) => FiliereEducative.depuisJson(e as Map<String, dynamic>))
          .toList(growable: false),
      programmes: (json['programmes'] as List<dynamic>)
          .map((e) => ProgrammeOfficiel.depuisJson(e as Map<String, dynamic>))
          .toList(growable: false),
      matieres: (json['matieres'] as List<dynamic>)
          .map((e) => ProgrammeMatiere.depuisJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> versJson() => {
        'filieres': filieres.map((f) => f.versJson()).toList(growable: false),
        'programmes':
            programmes.map((p) => p.versJson()).toList(growable: false),
        'matieres': matieres.map((m) => m.versJson()).toList(growable: false),
      };

  final List<FiliereEducative> filieres;
  final List<ProgrammeOfficiel> programmes;
  final List<ProgrammeMatiere> matieres;

  /// Matières d'un programme donné, triées par [ProgrammeMatiere.ordre].
  List<ProgrammeMatiere> matieresDuProgramme(String programmeId) {
    final liste =
        matieres.where((m) => m.programmeId == programmeId).toList();
    liste.sort((a, b) => a.ordre.compareTo(b.ordre));
    return liste;
  }

  /// Le programme le plus récent pour une filière donnée (ou générique si
  /// [filiereId] est null), en cas de versions multiples.
  ProgrammeOfficiel? programmePrincipal({String? filiereId}) {
    final candidats =
        programmes.where((p) => p.filiereId == filiereId).toList();
    if (candidats.isEmpty) return null;
    candidats.sort((a, b) => b.version.compareTo(a.version));
    return candidats.first;
  }
}
