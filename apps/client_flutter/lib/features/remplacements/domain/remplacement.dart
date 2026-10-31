/// Absences des enseignants, remplacements, cours assurés (REG-41).
library;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');
String _hm(Object? v) {
  final t = '${v ?? ''}';
  return t.length >= 5 ? t.substring(0, 5) : t;
}

String dateIsoRemplacement(DateTime d) {
  String deux(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${deux(d.month)}-${deux(d.day)}';
}

/// Les quatre solutions pour un cours dont l'enseignant est absent.
enum SolutionSeance {
  remplacement('remplacement', 'Remplacé'),
  etude('etude', 'Étude surveillée'),
  deplace('deplace', 'Déplacé'),
  annule('annule', 'Annulé');

  const SolutionSeance(this.code, this.libelle);

  final String code;
  final String libelle;

  static SolutionSeance? depuisCode(String? code) {
    for (final s in SolutionSeance.values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

class ModificationSeance {
  const ModificationSeance({
    required this.id,
    required this.solution,
    this.remplacantId,
    this.remplacant,
    this.note,
    this.deplaceLe,
    this.deplaceDebut,
    this.deplaceFin,
  });

  factory ModificationSeance.depuisJson(Map<String, dynamic> j) => ModificationSeance(
        id: '${j['id']}',
        solution: SolutionSeance.depuisCode(j['solution'] as String?) ?? SolutionSeance.annule,
        remplacantId: j['remplacant_id'] as String?,
        remplacant: (j['remplacant'] as String?)?.trim().isEmpty == true ? null : j['remplacant'] as String?,
        note: j['note'] as String?,
        deplaceLe: _date(j['deplace_le']),
        deplaceDebut: j['deplace_heure_debut'] == null ? null : _hm(j['deplace_heure_debut']),
        deplaceFin: j['deplace_heure_fin'] == null ? null : _hm(j['deplace_heure_fin']),
      );

  final String id;
  final SolutionSeance solution;
  final String? remplacantId;
  final String? remplacant;
  final String? note;
  final DateTime? deplaceLe;
  final String? deplaceDebut;
  final String? deplaceFin;
}

/// Cours d'un enseignant absent, un jour donné.
class CoursARemplacer {
  const CoursARemplacer({
    required this.emploiId,
    required this.date,
    required this.classe,
    required this.debut,
    required this.fin,
    this.classeId,
    this.matiere,
    this.salle,
    this.enseignant,
    this.modification,
  });

  factory CoursARemplacer.depuisJson(Map<String, dynamic> j) => CoursARemplacer(
        emploiId: '${j['emploi_id']}',
        date: _date(j['date']) ?? DateTime.now(),
        classeId: j['classe_id'] as String?,
        classe: '${j['classe'] ?? ''}',
        matiere: j['matiere'] as String?,
        debut: _hm(j['heure_debut']),
        fin: _hm(j['heure_fin']),
        salle: j['salle'] as String?,
        enseignant: j['enseignant'] as String?,
        modification: j['modification'] is Map
            ? ModificationSeance.depuisJson((j['modification'] as Map).cast<String, dynamic>())
            : null,
      );

  static List<CoursARemplacer> liste(Object? j) => [
        for (final x in (j as List?) ?? const []) CoursARemplacer.depuisJson((x as Map).cast<String, dynamic>()),
      ];

  final String emploiId;
  final DateTime date;
  final String? classeId;
  final String classe;
  final String? matiere;
  final String debut;
  final String fin;
  final String? salle;
  final String? enseignant;
  final ModificationSeance? modification;

  bool get traite => modification != null;
}

class AbsenceEnseignant {
  const AbsenceEnseignant({
    required this.id,
    required this.du,
    required this.au,
    required this.statut,
    this.enseignantId,
    this.enseignant,
    this.heureDebut,
    this.heureFin,
    this.motif,
  });

  factory AbsenceEnseignant.depuisJson(Map<String, dynamic> j) => AbsenceEnseignant(
        id: '${j['id']}',
        enseignantId: j['enseignant_id'] as String?,
        enseignant: j['enseignant'] as String?,
        du: _date(j['date_debut']) ?? DateTime.now(),
        au: _date(j['date_fin']) ?? DateTime.now(),
        heureDebut: j['heure_debut'] == null ? null : _hm(j['heure_debut']),
        heureFin: j['heure_fin'] == null ? null : _hm(j['heure_fin']),
        motif: j['motif'] as String?,
        statut: '${j['statut'] ?? 'validee'}',
      );

  static List<AbsenceEnseignant> liste(Object? j) => [
        for (final x in (j as List?) ?? const []) AbsenceEnseignant.depuisJson((x as Map).cast<String, dynamic>()),
      ];

  final String id;
  final String? enseignantId;
  final String? enseignant;
  final DateTime du;
  final DateTime au;
  final String? heureDebut;
  final String? heureFin;
  final String? motif;

  /// `signalee` (par l'enseignant, à valider), `validee`, `refusee`.
  final String statut;

  bool get aValider => statut == 'signalee';
  String get heures => heureDebut == null ? 'toute la journée' : '$heureDebut – ${heureFin ?? ''}';
}

/// Remplaçant proposé, du meilleur au moins bon.
class RemplacantPossible {
  const RemplacantPossible({
    required this.profileId,
    required this.nom,
    required this.role,
    this.memeMatiere = false,
    this.connaitClasse = false,
    this.ceMois = 0,
  });

  factory RemplacantPossible.depuisJson(Map<String, dynamic> j) => RemplacantPossible(
        profileId: '${j['profile_id']}',
        nom: '${j['nom'] ?? ''}',
        role: '${j['role'] ?? ''}',
        memeMatiere: j['meme_matiere'] == true,
        connaitClasse: j['connait_classe'] == true,
        ceMois: (j['ce_mois'] as num?)?.toInt() ?? 0,
      );

  final String profileId;
  final String nom;
  final String role;
  final bool memeMatiere;
  final bool connaitClasse;

  /// Remplacements déjà faits ce mois-ci (équité).
  final int ceMois;

  bool get enseignant => role == 'enseignant' || role == 'direction';
}

/// Changement de l'emploi du temps vu par une classe (élève, parent).
class ChangementCours {
  const ChangementCours({
    required this.id,
    required this.date,
    required this.debut,
    required this.fin,
    required this.solution,
    this.matiere,
    this.remplacant,
    this.salle,
    this.deplaceLe,
    this.deplaceDebut,
    this.note,
  });

  factory ChangementCours.depuisJson(Map<String, dynamic> j) => ChangementCours(
        id: '${j['id']}',
        date: _date(j['date']) ?? DateTime.now(),
        debut: _hm(j['heure_debut']),
        fin: _hm(j['heure_fin']),
        solution: SolutionSeance.depuisCode(j['solution'] as String?) ?? SolutionSeance.annule,
        matiere: j['matiere'] as String?,
        remplacant: (j['remplacant'] as String?)?.trim().isEmpty == true ? null : j['remplacant'] as String?,
        salle: j['salle'] as String?,
        deplaceLe: _date(j['deplace_le']),
        deplaceDebut: j['deplace_heure_debut'] == null ? null : _hm(j['deplace_heure_debut']),
        note: j['note'] as String?,
      );

  static List<ChangementCours> liste(Object? j) => [
        for (final x in (j as List?) ?? const []) ChangementCours.depuisJson((x as Map).cast<String, dynamic>()),
      ];

  final String id;
  final DateTime date;
  final String debut;
  final String fin;
  final SolutionSeance solution;
  final String? matiere;
  final String? remplacant;
  final String? salle;
  final DateTime? deplaceLe;
  final String? deplaceDebut;
  final String? note;
}

/// Séance que j'assure en remplacement.
class RemplacementAAssurer {
  const RemplacementAAssurer({
    required this.id,
    required this.date,
    required this.debut,
    required this.fin,
    required this.classe,
    required this.solution,
    this.matiere,
    this.salle,
    this.absent,
    this.note,
  });

  factory RemplacementAAssurer.depuisJson(Map<String, dynamic> j) => RemplacementAAssurer(
        id: '${j['id']}',
        date: _date(j['date']) ?? DateTime.now(),
        debut: _hm(j['heure_debut']),
        fin: _hm(j['heure_fin']),
        classe: '${j['classe'] ?? ''}',
        solution: SolutionSeance.depuisCode(j['solution'] as String?) ?? SolutionSeance.remplacement,
        matiere: j['matiere'] as String?,
        salle: j['salle'] as String?,
        absent: j['absent'] as String?,
        note: j['note'] as String?,
      );

  final String id;
  final DateTime date;
  final String debut;
  final String fin;
  final String classe;
  final SolutionSeance solution;
  final String? matiere;
  final String? salle;
  final String? absent;
  final String? note;
}

class MesRemplacements {
  const MesRemplacements({this.aAssurer = const [], this.absences = const []});

  factory MesRemplacements.depuisJson(Map<String, dynamic> j) => MesRemplacements(
        aAssurer: [
          for (final x in (j['a_assurer'] as List?) ?? const [])
            RemplacementAAssurer.depuisJson((x as Map).cast<String, dynamic>()),
        ],
        absences: AbsenceEnseignant.liste(j['absences']),
      );

  final List<RemplacementAAssurer> aAssurer;
  final List<AbsenceEnseignant> absences;
}

/// Cours assurés : une ligne par classe et matière.
class LigneCoursAssures {
  const LigneCoursAssures({
    required this.classe,
    required this.prevus,
    required this.assures,
    this.matiere,
    this.enseignant,
    this.minutesPerdues = 0,
    this.alerte = false,
  });

  factory LigneCoursAssures.depuisJson(Map<String, dynamic> j) => LigneCoursAssures(
        classe: '${j['classe'] ?? ''}',
        matiere: j['matiere'] as String?,
        enseignant: j['enseignant'] as String?,
        prevus: (j['prevus'] as num?)?.toInt() ?? 0,
        assures: (j['assures'] as num?)?.toInt() ?? 0,
        minutesPerdues: (j['minutes_perdues'] as num?)?.toInt() ?? 0,
        alerte: j['alerte'] == true,
      );

  final String classe;
  final String? matiere;
  final String? enseignant;
  final int prevus;
  final int assures;
  final int minutesPerdues;

  /// Plus de 10 % des heures perdues sur la période.
  final bool alerte;

  double get taux => prevus == 0 ? 1 : assures / prevus;
}

class CoursAssures {
  const CoursAssures({
    this.prevus = 0,
    this.assures = 0,
    this.minutesPerdues = 0,
    this.lignes = const [],
    this.enseignants = const [],
  });

  factory CoursAssures.depuisJson(Map<String, dynamic> j) => CoursAssures(
        prevus: (j['prevus'] as num?)?.toInt() ?? 0,
        assures: (j['assures'] as num?)?.toInt() ?? 0,
        minutesPerdues: (j['minutes_perdues'] as num?)?.toInt() ?? 0,
        lignes: [
          for (final x in (j['lignes'] as List?) ?? const []) LigneCoursAssures.depuisJson((x as Map).cast<String, dynamic>()),
        ],
        enseignants: [
          for (final x in (j['enseignants'] as List?) ?? const [])
            (
              nom: '${(x as Map)['enseignant'] ?? ''}',
              prevus: (x['prevus'] as num?)?.toInt() ?? 0,
              assures: (x['assures'] as num?)?.toInt() ?? 0,
            ),
        ],
      );

  final int prevus;
  final int assures;
  final int minutesPerdues;
  final List<LigneCoursAssures> lignes;
  final List<({String nom, int prevus, int assures})> enseignants;

  double get taux => prevus == 0 ? 1 : assures / prevus;
}

/// Compteur des heures de remplacement (paie au choix de l'école).
class CompteurRemplacements {
  const CompteurRemplacements({this.payes = false, this.tarifHeure, this.lignes = const []});

  factory CompteurRemplacements.depuisJson(Map<String, dynamic> j) => CompteurRemplacements(
        payes: j['payes'] == true,
        tarifHeure: (j['tarif_heure'] as num?)?.toDouble(),
        lignes: [
          for (final x in (j['lignes'] as List?) ?? const [])
            (
              nom: '${(x as Map)['nom'] ?? ''}',
              remplacements: (x['remplacements'] as num?)?.toInt() ?? 0,
              etudes: (x['etudes'] as num?)?.toInt() ?? 0,
              minutes: (x['minutes_faites'] as num?)?.toInt() ?? 0,
              manques: (x['cours_manques'] as num?)?.toInt() ?? 0,
              montant: (x['montant'] as num?)?.toDouble(),
            ),
        ],
      );

  final bool payes;
  final double? tarifHeure;
  final List<({String nom, int remplacements, int etudes, int minutes, int manques, double? montant})> lignes;
}
