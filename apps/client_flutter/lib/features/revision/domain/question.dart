/// Banque de questions du moteur de révision (REG-37, cahier ch. 10).
///
/// Le même modèle sert au CMS de l'Administrateur de contenu pédagogique
/// (lot R1) et aux quiz des élèves (lot R2) : la correction est faite ici,
/// sur le téléphone, pour fonctionner sans réseau.
library;

enum TypeQuestion {
  qcmSimple('qcm_simple', 'QCM à une réponse', petitesClasses: true),
  qcmMultiple('qcm_multiple', 'QCM à plusieurs réponses'),
  vraiFaux('vrai_faux', 'Vrai ou faux', petitesClasses: true),
  reponseCourte('reponse_courte', 'Réponse courte'),
  texteATrous('texte_a_trous', 'Texte à trous'),
  association('association', 'Association', petitesClasses: true),
  classement('classement', 'Classement', petitesClasses: true),
  calcul('calcul', 'Calcul');

  const TypeQuestion(this.code, this.libelle, {this.petitesClasses = false});

  final String code;
  final String libelle;

  /// Autorisé du CP1 au CE2 (cahier 9.6, 10.2).
  final bool petitesClasses;

  static TypeQuestion depuisCode(String? code) =>
      values.firstWhere((t) => t.code == code, orElse: () => TypeQuestion.qcmSimple);
}

enum Difficulte {
  facile('facile', 'Facile'),
  moyen('moyen', 'Moyen'),
  difficile('difficile', 'Difficile'),
  expert('expert', 'Expert');

  const Difficulte(this.code, this.libelle);

  final String code;
  final String libelle;

  static Difficulte depuisCode(String? code) =>
      values.firstWhere((d) => d.code == code, orElse: () => Difficulte.moyen);
}

/// Circuit unique du contenu pédagogique (cahier 30.5).
enum StatutContenu {
  brouillon('brouillon', 'Brouillon'),
  revision('revision', 'À valider'),
  validee('validee', 'Validée'),
  publiee('publiee', 'Publiée');

  const StatutContenu(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutContenu depuisCode(String? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => StatutContenu.brouillon);
}

/// Un choix, un élément à classer ou un terme à associer.
class ItemQuestion {
  const ItemQuestion(this.id, this.texte);

  final String id;
  final String texte;

  Map<String, dynamic> versJson() => {'id': id, 'texte': texte};

  static List<ItemQuestion> liste(Object? json) => [
        for (final e in (json as List?) ?? const [])
          ItemQuestion('${(e as Map)['id']}', '${e['texte'] ?? ''}'),
      ];

  @override
  bool operator ==(Object other) => other is ItemQuestion && other.id == id && other.texte == texte;

  @override
  int get hashCode => Object.hash(id, texte);
}

/// Contenu d'une version de question (ce que l'élève voit et ce qui le
/// corrige).
class ContenuQuestion {
  const ContenuQuestion({
    required this.type,
    required this.difficulte,
    required this.competenceId,
    required this.enonce,
    required this.contenu,
    required this.reponse,
    required this.explication,
    this.chapitreId,
    this.leconId,
    this.tempsRecommandeS = 60,
    this.source,
    this.tags = const [],
    this.mediaChemin,
    this.mediaType,
    this.version = 1,
  });

  final TypeQuestion type;
  final Difficulte difficulte;
  final String? competenceId;
  final String? chapitreId;
  final String? leconId;
  final String enonce;
  final Map<String, dynamic> contenu;
  final Map<String, dynamic> reponse;
  final String explication;
  final int tempsRecommandeS;
  final String? source;
  final List<String> tags;
  final String? mediaChemin;
  final String? mediaType;
  final int version;

  factory ContenuQuestion.depuisJson(Map<String, dynamic> j) => ContenuQuestion(
        type: TypeQuestion.depuisCode(j['type'] as String?),
        difficulte: Difficulte.depuisCode(j['difficulte'] as String?),
        competenceId: j['competence_id'] as String?,
        chapitreId: j['chapitre_id'] as String?,
        leconId: j['lecon_id'] as String?,
        enonce: j['enonce'] as String? ?? '',
        contenu: ((j['contenu'] as Map?) ?? const {}).cast<String, dynamic>(),
        reponse: ((j['reponse'] as Map?) ?? const {}).cast<String, dynamic>(),
        explication: j['explication'] as String? ?? '',
        tempsRecommandeS: (j['temps_recommande_s'] as num?)?.toInt() ?? 60,
        source: j['source'] as String?,
        tags: [for (final t in (j['tags'] as List?) ?? const []) '$t'],
        mediaChemin: j['media_chemin'] as String?,
        mediaType: j['media_type'] as String?,
        version: (j['version'] as num?)?.toInt() ?? 1,
      );

  List<ItemQuestion> get choix => ItemQuestion.liste(contenu['choix']);
  List<ItemQuestion> get gauche => ItemQuestion.liste(contenu['gauche']);
  List<ItemQuestion> get droite => ItemQuestion.liste(contenu['droite']);
  List<ItemQuestion> get elements => ItemQuestion.liste(contenu['elements']);

  /// Numéros des trous de l'énoncé (« [[1]] », « [[2]] »…), dans l'ordre.
  List<String> get trous => [for (final m in motifTrou.allMatches(enonce)) m.group(1)!];

  static final motifTrou = RegExp(r'\[\[(\w+)\]\]');

  /// Paramètres de `enregistrer_question` (sans identifiant ni matière).
  Map<String, dynamic> versParametres() => {
        'p_type': type.code,
        'p_difficulte': difficulte.code,
        'p_competence': competenceId,
        'p_enonce': enonce.trim(),
        'p_contenu': contenu,
        'p_reponse': reponse,
        'p_explication': explication.trim(),
        'p_chapitre': chapitreId,
        'p_lecon': leconId,
        'p_temps_recommande_s': tempsRecommandeS,
        'p_source': (source?.trim().isEmpty ?? true) ? null : source!.trim(),
        'p_tags': tags,
        'p_media_chemin': mediaChemin,
        'p_media_type': mediaType,
      };

  /// Même contrôle que le serveur (`erreur_forme_question` et règles de
  /// 10.3) : null si la question peut être enregistrée.
  String? erreur({bool petitesClasses = false}) {
    if (enonce.trim().isEmpty) return 'ENONCE_REQUIS';
    if (competenceId == null) return 'COMPETENCE_REQUISE';
    if (explication.trim().isEmpty) return 'EXPLICATION_REQUISE';
    final forme = erreurForme(type, enonce, contenu, reponse);
    if (forme != null) return forme;
    if (petitesClasses) {
      if (!type.petitesClasses) return 'TYPE_NON_ADAPTE_PETITES_CLASSES';
      if (type == TypeQuestion.qcmSimple && choix.length > 3) return 'TROP_DE_CHOIX_PETITES_CLASSES';
    }
    return null;
  }

  // ------------------------------------------------------------- correction

  /// Corrige une réponse d'élève. Formes attendues :
  /// QCM : `Set<String>` ou `List<String>` d'identifiants ; vrai/faux :
  /// `bool` ; réponse courte et calcul : `String` ; texte à trous :
  /// `Map<String, String>` (trou → texte) ; association : `Map<String,
  /// String>` (gauche → droite) ; classement : `List<String>` d'identifiants.
  Correction corriger(Object? donnee) {
    switch (type) {
      case TypeQuestion.qcmSimple:
      case TypeQuestion.qcmMultiple:
        final attendues = {for (final b in (reponse['bonnes'] as List?) ?? const []) '$b'};
        final donnees = donnee is Iterable ? {for (final d in donnee) '$d'} : <String>{};
        return Correction.tout(donnees.length == attendues.length && donnees.containsAll(attendues));
      case TypeQuestion.vraiFaux:
        return Correction.tout(donnee is bool && donnee == reponse['valeur']);
      case TypeQuestion.reponseCourte:
        final saisie = normaliser('${donnee ?? ''}', sensibleCasse: reponse['sensible_casse'] == true);
        return Correction.tout(saisie.isNotEmpty &&
            [for (final a in (reponse['acceptees'] as List?) ?? const []) normaliser('$a', sensibleCasse: reponse['sensible_casse'] == true)]
                .contains(saisie));
      case TypeQuestion.texteATrous:
        final attendus = ((reponse['trous'] as Map?) ?? const {}).cast<String, dynamic>();
        if (attendus.isEmpty) return Correction.tout(false);
        final saisis = donnee is Map ? donnee : const {};
        var justes = 0;
        for (final e in attendus.entries) {
          final s = normaliser('${saisis[e.key] ?? ''}');
          if (s.isNotEmpty && [for (final a in (e.value as List)) normaliser('$a')].contains(s)) justes++;
        }
        return Correction(justes / attendus.length);
      case TypeQuestion.association:
        final paires = ((reponse['paires'] as Map?) ?? const {}).cast<String, dynamic>();
        if (paires.isEmpty) return Correction.tout(false);
        final saisis = donnee is Map ? donnee : const {};
        var justes = 0;
        for (final e in paires.entries) {
          if ('${saisis[e.key]}' == '${e.value}') justes++;
        }
        return Correction(justes / paires.length);
      case TypeQuestion.classement:
        final ordre = [for (final o in (reponse['ordre'] as List?) ?? const []) '$o'];
        final saisi = donnee is List ? [for (final d in donnee) '$d'] : const <String>[];
        if (ordre.isEmpty || saisi.length != ordre.length) return Correction.tout(false);
        var bienPlaces = 0;
        for (var i = 0; i < ordre.length; i++) {
          if (saisi[i] == ordre[i]) bienPlaces++;
        }
        return Correction(bienPlaces / ordre.length);
      case TypeQuestion.calcul:
        final saisi = lireNombre('${donnee ?? ''}');
        final attendu = (reponse['valeur'] as num?)?.toDouble();
        if (saisi == null || attendu == null) return Correction.tout(false);
        final tolerance = (reponse['tolerance'] as num?)?.toDouble() ?? 0;
        return Correction.tout((saisi - attendu).abs() <= tolerance + 1e-9);
    }
  }

  /// La bonne réponse, en mots (affichée après correction).
  String bonneReponseLisible() {
    switch (type) {
      case TypeQuestion.qcmSimple:
      case TypeQuestion.qcmMultiple:
        final bonnes = {for (final b in (reponse['bonnes'] as List?) ?? const []) '$b'};
        return [for (final c in choix) if (bonnes.contains(c.id)) c.texte].join(' ; ');
      case TypeQuestion.vraiFaux:
        return reponse['valeur'] == true ? 'Vrai' : 'Faux';
      case TypeQuestion.reponseCourte:
        return '${((reponse['acceptees'] as List?) ?? const []).firstOrNull ?? ''}';
      case TypeQuestion.texteATrous:
        final attendus = ((reponse['trous'] as Map?) ?? const {}).cast<String, dynamic>();
        return enonce.replaceAllMapped(motifTrou, (m) => '${(attendus[m.group(1)] as List?)?.firstOrNull ?? '…'}');
      case TypeQuestion.association:
        final paires = ((reponse['paires'] as Map?) ?? const {}).cast<String, dynamic>();
        final d = {for (final e in droite) e.id: e.texte};
        return [for (final g in gauche) '${g.texte} → ${d[paires[g.id]] ?? '?'}'].join(' ; ');
      case TypeQuestion.classement:
        final t = {for (final e in elements) e.id: e.texte};
        return [for (final o in (reponse['ordre'] as List?) ?? const []) t['$o'] ?? '?'].join(' < ');
      case TypeQuestion.calcul:
        final v = reponse['valeur'];
        final unite = reponse['unite'];
        return unite == null || '$unite'.isEmpty ? '$v' : '$v $unite';
    }
  }
}

/// Résultat d'une correction : part juste entre 0 et 1.
class Correction {
  const Correction(this.score);

  const Correction.tout(bool juste) : score = juste ? 1.0 : 0.0;

  final double score;

  bool get juste => score >= 1;
}

/// Compare des réponses saisies : sans accents, majuscules (sauf demande),
/// espaces en trop ni ponctuation finale.
String normaliser(String texte, {bool sensibleCasse = false}) {
  var t = texte.trim().replaceAll(RegExp(r'\s+'), ' ');
  t = t.replaceAll(RegExp(r'[.!?;:]+$'), '').trim();
  if (!sensibleCasse) t = t.toLowerCase();
  const accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ç': 'c', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae',
    'À': 'A', 'Â': 'A', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Î': 'I', 'Ô': 'O', 'Ù': 'U', 'Û': 'U', 'Ç': 'C',
  };
  final b = StringBuffer();
  for (final r in t.runes) {
    final c = String.fromCharCode(r);
    b.write(accents[c] ?? c);
  }
  return b.toString();
}

/// « 3,5 », « 3.5 », « 1 200 » → nombre ; null si ce n'en est pas un.
double? lireNombre(String texte) =>
    double.tryParse(texte.trim().replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.'));

/// Contrôle de forme, identique à `erreur_forme_question` côté serveur.
String? erreurForme(TypeQuestion type, String enonce, Map<String, dynamic> contenu, Map<String, dynamic> reponse) {
  bool idsValides(List<ItemQuestion> l) =>
      l.every((e) => e.id.trim().isNotEmpty && e.texte.trim().isNotEmpty) && l.map((e) => e.id).toSet().length == l.length;
  bool listeTextes(Object? v) =>
      v is List && v.isNotEmpty && v.every((a) => a is String && a.trim().isNotEmpty);

  switch (type) {
    case TypeQuestion.qcmSimple:
    case TypeQuestion.qcmMultiple:
      final choix = contenu['choix'];
      if (choix is! List || choix.length < 2 || choix.length > 6) return 'CHOIX_INVALIDES';
      final l = ItemQuestion.liste(choix);
      if (!idsValides(l)) return 'CHOIX_INVALIDES';
      final bonnes = reponse['bonnes'];
      if (bonnes is! List || bonnes.isEmpty) return 'REPONSE_INVALIDE';
      if (type == TypeQuestion.qcmSimple && bonnes.length != 1) return 'REPONSE_INVALIDE';
      final ids = l.map((e) => e.id).toSet();
      if (bonnes.toSet().length != bonnes.length || !bonnes.every((b) => ids.contains('$b'))) return 'REPONSE_INVALIDE';
    case TypeQuestion.vraiFaux:
      if (reponse['valeur'] is! bool) return 'REPONSE_INVALIDE';
    case TypeQuestion.reponseCourte:
      if (!listeTextes(reponse['acceptees'])) return 'REPONSE_INVALIDE';
    case TypeQuestion.texteATrous:
      final trous = reponse['trous'];
      if (trous is! Map || trous.isEmpty) return 'REPONSE_INVALIDE';
      for (final e in trous.entries) {
        if (!enonce.contains('[[${e.key}]]')) return 'TROU_ABSENT_ENONCE';
        if (!listeTextes(e.value)) return 'REPONSE_INVALIDE';
      }
    case TypeQuestion.association:
      final g = contenu['gauche'], d = contenu['droite'];
      if (g is! List || d is! List || g.length < 2 || g.length > 8 || d.length < 2 || d.length > 8) {
        return 'CHOIX_INVALIDES';
      }
      final lg = ItemQuestion.liste(g), ld = ItemQuestion.liste(d);
      if (!lg.every((e) => e.id.trim().isNotEmpty && e.texte.trim().isNotEmpty) ||
          !ld.every((e) => e.id.trim().isNotEmpty && e.texte.trim().isNotEmpty)) {
        return 'CHOIX_INVALIDES';
      }
      final paires = reponse['paires'];
      if (paires is! Map) return 'REPONSE_INVALIDE';
      final idsD = ld.map((e) => e.id).toSet();
      if (!lg.every((e) => paires.containsKey(e.id)) ||
          !paires.entries.every((p) => lg.any((e) => e.id == p.key) && idsD.contains('${p.value}'))) {
        return 'REPONSE_INVALIDE';
      }
    case TypeQuestion.classement:
      final el = contenu['elements'];
      if (el is! List || el.length < 2 || el.length > 8) return 'CHOIX_INVALIDES';
      final l = ItemQuestion.liste(el);
      if (!l.every((e) => e.id.trim().isNotEmpty && e.texte.trim().isNotEmpty)) return 'CHOIX_INVALIDES';
      final ordre = reponse['ordre'];
      if (ordre is! List) return 'REPONSE_INVALIDE';
      final a = [for (final o in ordre) '$o']..sort();
      final b = [for (final e in l) e.id]..sort();
      if (a.join('\u0000') != b.join('\u0000')) return 'REPONSE_INVALIDE';
    case TypeQuestion.calcul:
      if (reponse['valeur'] is! num) return 'REPONSE_INVALIDE';
      final t = reponse['tolerance'];
      if (t != null && (t is! num || t < 0)) return 'REPONSE_INVALIDE';
  }
  return null;
}

/// Question de la banque (vue de l'Administrateur de contenu).
class Question {
  const Question({
    required this.id,
    required this.matiereId,
    required this.statut,
    required this.versionTravail,
    required this.travail,
    this.versionPubliee,
    this.suspendue = false,
    this.remarqueRevision,
    this.enAttenteEnvoi = false,
    this.signalements = 0,
  });

  final String id;
  final String matiereId;
  final StatutContenu statut;
  final int versionTravail;
  final int? versionPubliee;
  final bool suspendue;
  final String? remarqueRevision;

  /// Version en cours d'écriture (celle que l'éditeur montre).
  final ContenuQuestion travail;

  /// Brouillon gardé sur l'appareil, pas encore reçu par le serveur.
  final bool enAttenteEnvoi;

  /// Signalements non traités.
  final int signalements;

  /// Une version publiée est servie aux élèves pendant qu'une suivante est
  /// en préparation.
  bool get diffuseePendantModification => versionPubliee != null && versionPubliee != versionTravail;

  factory Question.depuisJson(Map<String, dynamic> j) {
    final versionTravail = (j['version_travail'] as num?)?.toInt() ?? 1;
    final versions = [
      for (final v in (j['questions_versions'] as List?) ?? const []) (v as Map).cast<String, dynamic>(),
    ];
    final travail = versions.firstWhere(
      (v) => (v['version'] as num?)?.toInt() == versionTravail,
      orElse: () => versions.isEmpty ? const <String, dynamic>{} : versions.last,
    );
    final signalements = (j['signalements_questions'] as List?) ?? const [];
    return Question(
      id: j['id'] as String,
      matiereId: j['matiere_id'] as String,
      statut: StatutContenu.depuisCode(j['statut'] as String?),
      versionTravail: versionTravail,
      versionPubliee: (j['version_publiee'] as num?)?.toInt(),
      suspendue: j['suspendue_le'] != null,
      remarqueRevision: j['remarque_revision'] as String?,
      travail: ContenuQuestion.depuisJson(travail),
      signalements: signalements.where((s) => (s as Map)['traite'] != true).length,
    );
  }
}

class ChapitreMatiere {
  const ChapitreMatiere({required this.id, required this.titre, this.ordre = 0, this.lecons = const []});

  final String id;
  final String titre;
  final int ordre;
  final List<LeconChapitre> lecons;

  factory ChapitreMatiere.depuisJson(Map<String, dynamic> j) => ChapitreMatiere(
        id: j['id'] as String,
        titre: j['titre'] as String,
        ordre: (j['ordre'] as num?)?.toInt() ?? 0,
        lecons: [
          for (final l in (j['lecons_chapitre'] as List?) ?? const [])
            LeconChapitre.depuisJson((l as Map).cast<String, dynamic>()),
        ]..sort((a, b) => a.ordre.compareTo(b.ordre)),
      );
}

class LeconChapitre {
  const LeconChapitre({required this.id, required this.titre, this.ordre = 0});

  final String id;
  final String titre;
  final int ordre;

  factory LeconChapitre.depuisJson(Map<String, dynamic> j) => LeconChapitre(
        id: j['id'] as String,
        titre: j['titre'] as String,
        ordre: (j['ordre'] as num?)?.toInt() ?? 0,
      );
}

class Competence {
  const Competence({required this.id, required this.code, required this.libelle});

  final String id;
  final String code;
  final String libelle;

  factory Competence.depuisJson(Map<String, dynamic> j) =>
      Competence(id: j['id'] as String, code: j['code'] as String, libelle: j['libelle'] as String);
}

/// Chapitres, leçons et compétences d'une matière.
class StructureMatiere {
  const StructureMatiere({this.chapitres = const [], this.competences = const []});

  final List<ChapitreMatiere> chapitres;
  final List<Competence> competences;
}

class ErreurBanque implements Exception {
  const ErreurBanque(this.code);

  final String code;

  String get message => switch (code) {
        'HORS_LIGNE' => 'Pas de réseau : cette action se fait en ligne.',
        'PERMISSION_REFUSEE' => 'Réservé à l’Administrateur de contenu pédagogique.',
        'ENONCE_REQUIS' => 'Écrivez l’énoncé.',
        'COMPETENCE_REQUISE' => 'Choisissez la compétence travaillée.',
        'DIFFICULTE_REQUISE' => 'Choisissez la difficulté.',
        'EXPLICATION_REQUISE' => 'Écrivez l’explication montrée à l’élève après sa réponse.',
        'CHOIX_INVALIDES' => 'Remplissez tous les choix (2 à 6 ; 2 à 8 pour associer ou classer).',
        'REPONSE_INVALIDE' => 'Indiquez la bonne réponse.',
        'TROU_ABSENT_ENONCE' => 'Chaque trou doit figurer dans l’énoncé, par exemple [[1]].',
        'TYPE_NON_ADAPTE_PETITES_CLASSES' =>
          'Du CP1 au CE2 : QCM à une réponse, vrai ou faux, association ou classement seulement.',
        'TROP_DE_CHOIX_PETITES_CLASSES' => 'Du CP1 au CE2 : trois choix au plus.',
        'COMPETENCE_HORS_MATIERE' || 'CHAPITRE_HORS_MATIERE' || 'LECON_HORS_CHAPITRE' =>
          'Le chapitre, la leçon ou la compétence n’appartient pas à cette matière.',
        'VALIDATEUR_DISTINCT_REQUIS' => 'Une autre personne habilitée doit valider cette question.',
        'VALIDATION_REQUISE' => 'La question doit être validée avant d’être publiée.',
        'REMARQUE_REQUISE' => 'Dites ce qui est à reprendre.',
        'STATUT_INATTENDU' => 'La question a changé entre-temps : actualisez.',
        'FICHIER_TROP_LOURD' => 'Fichier trop lourd (3 Mo au plus).',
        _ => 'Action impossible pour le moment. Réessayez.',
      };

  @override
  String toString() => code;
}
