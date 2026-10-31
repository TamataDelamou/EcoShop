/// Back-office du référentiel pédagogique (REG-38 lot E2b) : pays, cycles,
/// niveaux, examens, programmes nationaux, brouillons compris.
library;

int? _int(Object? v) => (v as num?)?.toInt();
List<Map<String, dynamic>> _liste(Object? v) => [for (final x in (v as List?) ?? const []) (x as Map).cast<String, dynamic>()];

enum ZonePays {
  cedeao('cedeao', 'CEDEAO'),
  aes('aes', 'AES (Mali, Burkina Faso, Niger)'),
  autre('autre', 'Au-delà de la sous-région');

  const ZonePays(this.code, this.libelle);

  final String code;
  final String libelle;

  static ZonePays depuisCode(String? c) => values.firstWhere((z) => z.code == c, orElse: () => ZonePays.autre);
}

const systemesEducatifs = {
  'francophone_cfa': 'Francophone',
  'anglophone_waec': 'Anglophone (WAEC)',
  'lusophone': 'Lusophone',
  'arabophone_mixte': 'Arabophone ou mixte',
};

class PaysBackOffice {
  const PaysBackOffice({
    required this.code,
    required this.nom,
    this.typeSysteme = 'francophone_cfa',
    this.zone = ZonePays.cedeao,
    this.publie = false,
    this.aVerifier = false,
    this.niveaux = 0,
    this.brouillons = 0,
    this.examens = 0,
    this.programmes = 0,
  });

  final String code;
  final String nom;
  final String typeSysteme;
  final ZonePays zone;
  final bool publie;
  final bool aVerifier;
  final int niveaux;
  final int brouillons;
  final int examens;
  final int programmes;

  factory PaysBackOffice.depuisJson(Map<String, dynamic> j) => PaysBackOffice(
        code: '${j['code']}',
        nom: '${j['nom']}',
        typeSysteme: '${j['type_systeme'] ?? 'francophone_cfa'}',
        zone: ZonePays.depuisCode(j['zone'] as String?),
        publie: j['statut'] == 'deploye',
        aVerifier: j['a_verifier'] == true,
        niveaux: _int(j['niveaux']) ?? 0,
        brouillons: _int(j['brouillons']) ?? 0,
        examens: _int(j['examens']) ?? 0,
        programmes: _int(j['programmes']) ?? 0,
      );

  static List<PaysBackOffice> liste(Object? json) => [for (final p in _liste(json)) PaysBackOffice.depuisJson(p)];
}

class FichePays {
  const FichePays({
    required this.code,
    required this.nom,
    this.typeSysteme = 'francophone_cfa',
    this.langue = 'fr',
    this.organisme,
    this.devise = 'XOF',
    this.zone = ZonePays.cedeao,
    this.sources,
    this.pointsAVerifier,
    this.publie = false,
  });

  final String code;
  final String nom;
  final String typeSysteme;
  final String langue;
  final String? organisme;
  final String devise;
  final ZonePays zone;
  final String? sources;
  final String? pointsAVerifier;
  final bool publie;

  factory FichePays.depuisJson(Map<String, dynamic> j) => FichePays(
        code: '${j['code_iso']}',
        nom: '${j['nom']}',
        typeSysteme: '${j['type_systeme'] ?? 'francophone_cfa'}',
        langue: '${j['langue_enseignement_principale'] ?? 'fr'}',
        organisme: j['organisme_examinateur'] as String?,
        devise: '${j['devise_code'] ?? 'XOF'}',
        zone: ZonePays.depuisCode(j['zone'] as String?),
        sources: j['sources'] as String?,
        pointsAVerifier: j['points_a_verifier'] as String?,
        publie: j['statut_deploiement'] == 'deploye',
      );
}

class MatiereNationale {
  const MatiereNationale({required this.id, required this.code, required this.nom, this.ordre = 0, this.nature = 'tronc_commun', this.questions = 0});

  final String id;
  final String code;
  final String nom;
  final int ordre;
  final String nature;
  final int questions;

  factory MatiereNationale.depuisJson(Map<String, dynamic> j) => MatiereNationale(
        id: '${j['id']}',
        code: '${j['code']}',
        nom: '${j['nom']}',
        ordre: _int(j['ordre']) ?? 0,
        nature: '${j['nature'] ?? 'tronc_commun'}',
        questions: _int(j['questions']) ?? 0,
      );
}

class ProgrammeNational {
  const ProgrammeNational({required this.id, required this.nom, this.publie = false, this.serie, this.annee, this.matieres = const []});

  final String id;
  final String nom;
  final bool publie;
  final String? serie;
  final String? annee;
  final List<MatiereNationale> matieres;

  factory ProgrammeNational.depuisJson(Map<String, dynamic> j) => ProgrammeNational(
        id: '${j['id']}',
        nom: '${j['nom']}',
        publie: j['statut'] == 'publie',
        serie: j['filiere'] as String?,
        annee: j['annee'] as String?,
        matieres: [for (final m in _liste(j['matieres'])) MatiereNationale.depuisJson(m)],
      );
}

class NiveauBackOffice {
  const NiveauBackOffice({
    required this.id,
    required this.cycleId,
    required this.code,
    required this.nom,
    required this.grade,
    this.isced = 1,
    this.ordre = 1,
    this.examinateur = false,
    this.publie = false,
    this.utilise = false,
    this.programmes = const [],
  });

  final String id;
  final String cycleId;
  final String code;
  final String nom;

  /// Rang commun à tous les pays (1 = première année du primaire).
  final int grade;
  final int isced;
  final int ordre;
  final bool examinateur;
  final bool publie;
  final bool utilise;
  final List<ProgrammeNational> programmes;

  factory NiveauBackOffice.depuisJson(String cycleId, Map<String, dynamic> j) => NiveauBackOffice(
        id: '${j['id']}',
        cycleId: cycleId,
        code: '${j['code']}',
        nom: '${j['nom']}',
        grade: _int(j['grade']) ?? 1,
        isced: _int(j['isced']) ?? 1,
        ordre: _int(j['ordre']) ?? 1,
        examinateur: j['examinateur'] == true,
        publie: j['statut'] == 'publie',
        utilise: j['utilise'] == true,
        programmes: [for (final p in _liste(j['programmes'])) ProgrammeNational.depuisJson(p)],
      );
}

class CycleBackOffice {
  const CycleBackOffice({
    required this.id,
    required this.code,
    required this.nom,
    this.ordre = 1,
    this.ageMin,
    this.ageMax,
    this.duree,
    this.iscedMin = 1,
    this.iscedMax = 1,
    this.publie = false,
    this.niveaux = const [],
  });

  final String id;
  final String code;
  final String nom;
  final int ordre;
  final int? ageMin;
  final int? ageMax;
  final int? duree;
  final int iscedMin;
  final int iscedMax;
  final bool publie;
  final List<NiveauBackOffice> niveaux;

  factory CycleBackOffice.depuisJson(Map<String, dynamic> j) {
    final id = '${j['id']}';
    return CycleBackOffice(
      id: id,
      code: '${j['code']}',
      nom: '${j['nom']}',
      ordre: _int(j['ordre']) ?? 1,
      ageMin: _int(j['age_min']),
      ageMax: _int(j['age_max']),
      duree: _int(j['duree']),
      iscedMin: _int(j['isced_min']) ?? 1,
      iscedMax: _int(j['isced_max']) ?? 1,
      publie: j['statut'] == 'publie',
      niveaux: [for (final n in _liste(j['niveaux'])) NiveauBackOffice.depuisJson(id, n)],
    );
  }
}

class ExamenBackOffice {
  const ExamenBackOffice({required this.id, required this.code, required this.nom, this.organisme, this.mois, this.cycleId, this.publie = false});

  final String id;
  final String code;
  final String nom;
  final String? organisme;
  final int? mois;
  final String? cycleId;
  final bool publie;

  factory ExamenBackOffice.depuisJson(Map<String, dynamic> j) => ExamenBackOffice(
        id: '${j['id']}',
        code: '${j['code']}',
        nom: '${j['nom']}',
        organisme: j['organisme'] as String?,
        mois: _int(j['mois']),
        cycleId: j['cycle_id'] as String?,
        publie: j['statut'] == 'publie',
      );
}

class ConstatControle {
  const ConstatControle(this.message, {this.bloquant = false});

  final String message;
  final bool bloquant;
}

class ReferentielPays {
  const ReferentielPays({
    required this.pays,
    this.controle = const [],
    this.cycles = const [],
    this.examens = const [],
    this.series = const [],
  });

  final FichePays pays;
  final List<ConstatControle> controle;
  final List<CycleBackOffice> cycles;
  final List<ExamenBackOffice> examens;
  final List<({String id, String code, String nom})> series;

  bool get publiable => controle.every((c) => !c.bloquant);

  Iterable<NiveauBackOffice> get niveaux => cycles.expand((c) => c.niveaux);

  /// Rang proposé pour un nouveau niveau : à la suite des existants.
  int get prochainRang {
    final rangs = [for (final n in niveaux) n.grade];
    return rangs.isEmpty ? 1 : rangs.reduce((a, b) => a > b ? a : b) + 1;
  }

  /// Ce qui reste à publier (brouillons).
  int get brouillons =>
      cycles.where((c) => !c.publie).length + niveaux.where((n) => !n.publie).length + examens.where((e) => !e.publie).length;

  String? nomCycle(String? id) => cycles.where((c) => c.id == id).firstOrNull?.nom;

  factory ReferentielPays.depuisJson(Map<String, dynamic> j) => ReferentielPays(
        pays: FichePays.depuisJson(((j['pays'] as Map?) ?? const {}).cast<String, dynamic>()),
        controle: [
          for (final c in _liste(j['controle'])) ConstatControle('${c['message']}', bloquant: c['bloquant'] == true),
        ],
        cycles: [for (final c in _liste(j['cycles'])) CycleBackOffice.depuisJson(c)],
        examens: [for (final e in _liste(j['examens'])) ExamenBackOffice.depuisJson(e)],
        series: [for (final s in _liste(j['series'])) (id: '${s['id']}', code: '${s['code']}', nom: '${s['nom']}')],
      );
}

const moisDeLAnnee = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];
