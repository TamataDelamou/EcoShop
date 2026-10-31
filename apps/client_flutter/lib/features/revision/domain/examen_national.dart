/// Espaces de préparation aux examens nationaux (REG-38, cahier ch. 13).
/// Tout vient du référentiel : examens, épreuves, sessions et annales de
/// chaque pays ; rien n'est codé en dur.
library;

import 'maitrise.dart';
import 'quiz.dart';

class EpreuveExamen {
  const EpreuveExamen({
    required this.id,
    required this.libelle,
    required this.dureeMin,
    required this.coefficient,
    this.matiereCode = '',
    this.questionsBlanc = 20,
    this.matiereId,
  });

  final String id;
  final String libelle;
  final int dureeMin;
  final double coefficient;
  final String matiereCode;
  final int questionsBlanc;

  /// Matière du programme du niveau d'examen (questions et maîtrise).
  final String? matiereId;

  factory EpreuveExamen.depuisJson(Map<String, dynamic> j) => EpreuveExamen(
        id: j['id'] as String,
        libelle: '${j['libelle'] ?? ''}',
        dureeMin: (j['duree_min'] as num?)?.toInt() ?? 60,
        coefficient: (j['coefficient'] as num?)?.toDouble() ?? 1,
        matiereCode: '${j['matiere_code'] ?? ''}',
        questionsBlanc: (j['questions_blanc'] as num?)?.toInt() ?? 20,
        matiereId: j['matiere_id'] as String?,
      );
}

class AnnaleExamen {
  const AnnaleExamen({
    required this.id,
    required this.annee,
    required this.titre,
    this.session = 'normale',
    this.source = '',
    this.epreuveId,
    this.sujetChemin,
    this.corrigeChemin,
    this.questionIds = const [],
  });

  final String id;
  final int annee;
  final String titre;
  final String session;
  final String source;
  final String? epreuveId;
  final String? sujetChemin;
  final String? corrigeChemin;

  /// Version interactive : questions de la banque.
  final List<String> questionIds;

  bool get interactive => questionIds.isNotEmpty;

  factory AnnaleExamen.depuisJson(Map<String, dynamic> j) => AnnaleExamen(
        id: j['id'] as String,
        annee: (j['annee'] as num?)?.toInt() ?? 0,
        titre: '${j['titre'] ?? ''}',
        session: '${j['session'] ?? 'normale'}',
        source: '${j['source'] ?? ''}',
        epreuveId: j['epreuve_id'] as String?,
        sujetChemin: j['sujet_chemin'] as String?,
        corrigeChemin: j['corrige_chemin'] as String?,
        questionIds: [for (final q in (j['questions'] as List?) ?? const []) '$q'],
      );
}

class StatsBlanc {
  const StatsBlanc({this.nombre = 0, this.derniere, this.meilleure});

  final int nombre;
  final double? derniere;
  final double? meilleure;
}

class EspaceExamen {
  const EspaceExamen({
    required this.id,
    required this.code,
    required this.nom,
    this.organisme,
    this.paysCode = '',
    this.finPrimaire = false,
    this.moisSession,
    this.dateSession,
    this.epreuves = const [],
    this.annales = const [],
    this.blancs = const {},
    this.chronoStrict = false,
  });

  final String id;
  final String code;
  final String nom;
  final String? organisme;
  final String paysCode;

  /// Examen de fin de primaire (CEE, CFEE…) : chronomètre indicatif par
  /// défaut (cahier 13.3).
  final bool finPrimaire;
  final int? moisSession;

  /// Date déclarée de la prochaine session (sinon estimée).
  final DateTime? dateSession;
  final List<EpreuveExamen> epreuves;
  final List<AnnaleExamen> annales;

  /// Épreuve → examens blancs déjà faits.
  final Map<String?, StatsBlanc> blancs;

  /// Fin de primaire : le parent a activé la remise automatique.
  final bool chronoStrict;

  /// Remise automatique à la fin du temps ?
  bool get remiseAutomatique => !finPrimaire || chronoStrict;

  factory EspaceExamen.depuisJson(Map<String, dynamic> j) {
    final s = (j['session'] as Map?)?.cast<String, dynamic>();
    return EspaceExamen(
      id: j['id'] as String,
      code: '${j['code'] ?? ''}',
      nom: '${j['nom'] ?? ''}',
      organisme: j['organisme'] as String?,
      paysCode: '${j['pays_code'] ?? ''}',
      finPrimaire: j['fin_primaire'] == true,
      moisSession: (j['mois_session'] as num?)?.toInt(),
      dateSession: s == null ? null : DateTime.tryParse('${s['date_debut']}'),
      epreuves: [for (final e in (j['epreuves'] as List?) ?? const []) EpreuveExamen.depuisJson((e as Map).cast<String, dynamic>())],
      annales: [for (final a in (j['annales'] as List?) ?? const []) AnnaleExamen.depuisJson((a as Map).cast<String, dynamic>())],
      blancs: {
        for (final b in (j['blancs'] as List?) ?? const [])
          (b as Map)['epreuve_id'] as String?: StatsBlanc(
            nombre: (b['nombre'] as num?)?.toInt() ?? 0,
            derniere: (b['derniere_note'] as num?)?.toDouble(),
            meilleure: (b['meilleure_note'] as num?)?.toDouble(),
          ),
      },
      chronoStrict: j['chrono_strict'] == true,
    );
  }

  static List<EspaceExamen> liste(Object? json) => [
        for (final e in (json as List?) ?? const []) EspaceExamen.depuisJson((e as Map).cast<String, dynamic>()),
      ];

  /// Date de l'examen : celle déclarée, sinon le 15 du mois habituel de la
  /// session (estimation).
  ({DateTime date, bool estimee})? dateExamen(DateTime maintenant) {
    if (dateSession != null) return (date: dateSession!, estimee: false);
    final mois = moisSession;
    if (mois == null) return null;
    var d = DateTime(maintenant.year, mois, 15);
    if (!d.isAfter(maintenant)) d = DateTime(maintenant.year + 1, mois, 15);
    return (date: d, estimee: true);
  }

  int? joursRestants(DateTime maintenant) {
    final d = dateExamen(maintenant)?.date;
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day).difference(DateTime(maintenant.year, maintenant.month, maintenant.day)).inDays;
  }

  /// Matières des épreuves reliées au programme.
  List<String> get matieres => [for (final e in epreuves) ?e.matiereId];

  /// Note estimée d'une épreuve sur 20 : le dernier examen blanc s'il existe,
  /// sinon la maîtrise des compétences de la matière (indication).
  ({double note, bool blanc})? noteEpreuve(EpreuveExamen e, ProfilMaitrise profil, PaquetRevision paquet) {
    final b = blancs[e.id];
    if (b?.derniere != null) return (note: b!.derniere!, blanc: true);
    final m = e.matiereId == null ? null : profil.matiere(e.matiereId!, paquet);
    return m == null ? null : (note: m * 20, blanc: false);
  }

  /// Note prévisionnelle sur 20, pondérée par les coefficients des épreuves
  /// déjà évaluées, et la part des coefficients couverte (RG-013-02).
  ({double note, double couverture})? notePrevisionnelle(ProfilMaitrise profil, PaquetRevision paquet) {
    var somme = 0.0, coefs = 0.0, total = 0.0;
    for (final e in epreuves) {
      total += e.coefficient;
      final n = noteEpreuve(e, profil, paquet);
      if (n == null) continue;
      somme += n.note * e.coefficient;
      coefs += e.coefficient;
    }
    if (coefs == 0 || total == 0) return null;
    return (note: (somme / coefs * 4).round() / 4, couverture: coefs / total);
  }

  /// Épreuve la plus faible (à travailler en premier), parmi celles qui ont
  /// une note ; à défaut, celle de plus fort coefficient.
  EpreuveExamen? epreuvePrioritaire(ProfilMaitrise profil, PaquetRevision paquet) {
    final avecQuestions = [for (final e in epreuves) if (e.matiereId != null && paquet.questionsDe(e.matiereId!) > 0) e];
    if (avecQuestions.isEmpty) return null;
    final notees = [
      for (final e in avecQuestions)
        if (noteEpreuve(e, profil, paquet) case final n?) (e: e, note: n.note),
    ]..sort((a, b) => a.note.compareTo(b.note));
    if (notees.isNotEmpty && notees.first.note < 12) return notees.first.e;
    return ([...avecQuestions]..sort((a, b) => b.coefficient.compareTo(a.coefficient))).first;
  }
}
