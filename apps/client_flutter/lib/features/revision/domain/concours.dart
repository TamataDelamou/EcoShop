/// Concours, olympiades et certificats (REG-38 lot E2a, cahier 13.2, 23).
library;

import 'question.dart';
import 'quiz.dart';

enum TypeConcours {
  concoursInterne('concours_interne', 'Concours de l’école'),
  concoursInterEcoles('concours_inter_ecoles', 'Concours inter-écoles'),
  olympiade('olympiade', 'Olympiade'),
  tournoi('tournoi', 'Tournoi'),
  championnat('championnat', 'Championnat'),
  concoursEntree('concours_entree', 'Concours d’entrée (entraînement)');

  const TypeConcours(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypeConcours depuisCode(String? c) =>
      values.firstWhere((t) => t.code == c, orElse: () => TypeConcours.concoursInterne);
}

enum EtatManche { aVenir, ouverte, fermee }

class MancheConcours {
  const MancheConcours({
    required this.id,
    required this.ordre,
    required this.titre,
    required this.ouverture,
    required this.fermeture,
    required this.dureeMin,
    this.questions = 0,
    this.commencee = false,
    this.remise = false,
    this.score,
    this.horsDelai = false,
  });

  final String id;
  final int ordre;
  final String titre;
  final DateTime ouverture;
  final DateTime fermeture;
  final int dureeMin;
  final int questions;
  final bool commencee;
  final bool remise;
  final double? score;
  final bool horsDelai;

  EtatManche etat(DateTime maintenant) => maintenant.isBefore(ouverture)
      ? EtatManche.aVenir
      : maintenant.isAfter(fermeture)
          ? EtatManche.fermee
          : EtatManche.ouverte;

  factory MancheConcours.depuisJson(Map<String, dynamic> j) => MancheConcours(
        id: j['id'] as String,
        ordre: (j['ordre'] as num?)?.toInt() ?? 1,
        titre: '${j['titre'] ?? ''}',
        ouverture: DateTime.parse('${j['ouverture']}'),
        fermeture: DateTime.parse('${j['fermeture']}'),
        dureeMin: (j['duree_min'] as num?)?.toInt() ?? 30,
        questions: (j['questions'] as num?)?.toInt() ?? 0,
        commencee: j['commencee'] == true,
        remise: j['remise'] == true,
        score: (j['score'] as num?)?.toDouble(),
        horsDelai: j['hors_delai'] == true,
      );
}

class Concours {
  const Concours({
    required this.id,
    required this.titre,
    this.description,
    this.type = TypeConcours.concoursInterne,
    this.organisateur = '',
    this.international = false,
    this.paysCode,
    this.recompenses,
    this.statut = 'ouvert',
    this.inscriptionJusquau,
    this.inscrit = false,
    this.manches = const [],
    this.certificat,
  });

  final String id;
  final String titre;
  final String? description;
  final TypeConcours type;
  final String organisateur;
  final bool international;
  final String? paysCode;
  final String? recompenses;
  final String statut;
  final DateTime? inscriptionJusquau;
  final bool inscrit;
  final List<MancheConcours> manches;

  /// Code du certificat obtenu, s'il y en a un.
  final String? certificat;

  bool get ouvert => statut == 'ouvert';

  bool inscriptionsOuvertes(DateTime maintenant) =>
      ouvert && (inscriptionJusquau == null || maintenant.isBefore(inscriptionJusquau!));

  /// Prochaine manche à jouer (ouverte et pas encore remise).
  MancheConcours? mancheAJouer(DateTime maintenant) =>
      manches.where((m) => m.etat(maintenant) == EtatManche.ouverte && !m.remise).firstOrNull;

  factory Concours.depuisJson(Map<String, dynamic> j) => Concours(
        id: j['id'] as String,
        titre: '${j['titre'] ?? ''}',
        description: j['description'] as String?,
        type: TypeConcours.depuisCode(j['type'] as String?),
        organisateur: '${j['organisateur'] ?? ''}',
        international: j['international'] == true,
        paysCode: j['pays_code'] as String?,
        recompenses: j['recompenses'] as String?,
        statut: '${j['statut'] ?? 'ouvert'}',
        inscriptionJusquau: j['inscription_jusquau'] == null ? null : DateTime.tryParse('${j['inscription_jusquau']}'),
        inscrit: j['inscrit'] == true,
        manches: [for (final m in (j['manches'] as List?) ?? const []) MancheConcours.depuisJson((m as Map).cast<String, dynamic>())],
        certificat: j['certificat'] as String?,
      );

  static List<Concours> liste(Object? json) => [
        for (final c in (json as List?) ?? const []) Concours.depuisJson((c as Map).cast<String, dynamic>()),
      ];
}

/// Sujet d'une manche (sans les bonnes réponses : le serveur corrige).
class SujetManche {
  const SujetManche({required this.limite, required this.questions, required this.commenceLe});

  final DateTime limite;
  final DateTime commenceLe;
  final List<QuestionQuiz> questions;

  factory SujetManche.depuisJson(Map<String, dynamic> j) => SujetManche(
        limite: DateTime.parse('${j['limite']}'),
        commenceLe: DateTime.parse('${j['commence_le']}'),
        questions: [for (final q in (j['questions'] as List?) ?? const []) QuestionQuiz.depuisJson((q as Map).cast<String, dynamic>())],
      );
}

/// Résultat renvoyé par le serveur, avec la correction détaillée.
class ResultatManche {
  const ResultatManche({
    required this.score,
    required this.questions,
    this.horsDelai = false,
    this.enAttente = false,
    this.corrections = const {},
  });

  final double score;
  final int questions;
  final bool horsDelai;

  /// Copie gardée sur l'appareil, envoyée au retour du réseau.
  final bool enAttente;

  /// Question → (score, contenu complet avec la bonne réponse).
  final Map<String, ({double score, Map<String, dynamic> reponse, String explication})> corrections;

  factory ResultatManche.depuisJson(Map<String, dynamic> j) => ResultatManche(
        score: (j['score'] as num?)?.toDouble() ?? 0,
        questions: (j['questions'] as num?)?.toInt() ?? 0,
        horsDelai: j['hors_delai'] == true,
        corrections: {
          for (final c in (j['correction'] as List?) ?? const [])
            '${(c as Map)['question_id']}': (
              score: (c['score'] as num?)?.toDouble() ?? 0,
              reponse: ((c['reponse'] as Map?) ?? const {}).cast<String, dynamic>(),
              explication: '${c['explication'] ?? ''}',
            ),
        },
      );

  /// Question telle qu'elle était, avec sa bonne réponse (pour l'afficher).
  ContenuQuestion? contenuCorrige(QuestionQuiz q) {
    final c = corrections[q.id];
    if (c == null) return null;
    final x = q.contenu;
    return ContenuQuestion(
      type: x.type,
      difficulte: x.difficulte,
      competenceId: x.competenceId,
      enonce: x.enonce,
      contenu: x.contenu,
      reponse: c.reponse,
      explication: c.explication,
    );
  }
}

class LigneClassementConcours {
  const LigneClassementConcours({
    required this.rang,
    required this.nom,
    required this.score,
    this.ecole,
    this.pays,
    this.dureeS = 0,
    this.moi = false,
  });

  final int rang;
  final String nom;
  final double score;
  final String? ecole;
  final String? pays;
  final int dureeS;
  final bool moi;
}

class ClassementConcours {
  const ClassementConcours({
    this.participants = 0,
    this.lignes = const [],
    this.enVerification,
    this.aVerifier = const [],
    this.monPays,
    this.monEtablissement,
  });

  final int participants;

  /// Pays et école de l'élève dans ce concours (filtres).
  final String? monPays;
  final String? monEtablissement;
  final List<LigneClassementConcours> lignes;

  /// Organisateur seulement : copies écartées (23.4).
  final int? enVerification;
  final List<({String ficheId, String nom, double score, int dureeS})> aVerifier;

  factory ClassementConcours.depuisJson(Map<String, dynamic> j) => ClassementConcours(
        participants: (j['participants'] as num?)?.toInt() ?? 0,
        monPays: j['mon_pays'] as String?,
        monEtablissement: j['mon_etablissement'] as String?,
        enVerification: (j['en_verification'] as num?)?.toInt(),
        lignes: [
          for (final l in (j['lignes'] as List?) ?? const [])
            LigneClassementConcours(
              rang: ((l as Map)['rang'] as num?)?.toInt() ?? 0,
              nom: '${l['nom'] ?? ''}',
              score: (l['score'] as num?)?.toDouble() ?? 0,
              ecole: l['ecole'] as String?,
              pays: l['pays'] as String?,
              dureeS: (l['duree_s'] as num?)?.toInt() ?? 0,
              moi: l['moi'] == true,
            ),
        ],
        aVerifier: [
          for (final a in (j['a_verifier'] as List?) ?? const [])
            (
              ficheId: '${(a as Map)['fiche_eleve_id']}',
              nom: '${a['nom'] ?? ''}',
              score: (a['score'] as num?)?.toDouble() ?? 0,
              dureeS: (a['duree_s'] as num?)?.toInt() ?? 0,
            ),
        ],
      );
}

/// Adresse publique de vérification des certificats.
const adresseVerificationCertificat = 'globalservicegroupe.com/certificat';

/// Regroupe des questions choisies en emplacements de [variantes] questions
/// équivalentes (tirées au hasard pour chaque élève).
List<Map<String, dynamic>> emplacementsDepuis(List<String> questionIds, {int variantes = 1}) {
  final v = variantes.clamp(1, 4);
  return [
    for (final (i, id) in questionIds.indexed) {'emplacement': i ~/ v + 1, 'question_id': id},
  ];
}

/// Question publiée proposée pour composer une manche.
class QuestionProposee {
  const QuestionProposee({
    required this.id,
    required this.enonce,
    this.pays = '',
    this.niveau = '',
    this.matiere = '',
    this.difficulte = '',
  });

  final String id;
  final String enonce;
  final String pays;
  final String niveau;
  final String matiere;
  final String difficulte;

  String get groupe => '$pays · $niveau · $matiere';

  static List<QuestionProposee> liste(Object? json) => [
        for (final q in (json as List?) ?? const [])
          QuestionProposee(
            id: '${(q as Map)['id']}',
            enonce: '${q['enonce'] ?? ''}',
            pays: '${q['pays'] ?? ''}',
            niveau: '${q['niveau'] ?? ''}',
            matiere: '${q['matiere'] ?? ''}',
            difficulte: '${q['difficulte'] ?? ''}',
          ),
      ];
}
