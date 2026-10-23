/// Cahier de liaison (REG-19, lot 2) : l'enseignant de la classe ou la
/// direction écrit au sujet d'un élève ; seuls les parents confirmés de cet
/// élève le lisent, confirment la lecture et répondent en texte.
library;

DateTime _date(Object? v) => DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime.now();

/// Réponse dans un fil.
class MessageLiaison {
  const MessageLiaison({
    required this.id,
    required this.corps,
    required this.creeLe,
    this.auteur,
    this.deMoi = false,
    this.auteurParent = false,
    this.masqueLe,
    this.motifMasquage,
    this.enAttenteEnvoi = false,
  });

  factory MessageLiaison.depuisJson(Map<String, dynamic> j) => MessageLiaison(
        id: j['id'] as String,
        corps: j['corps'] as String? ?? '',
        creeLe: _date(j['cree_le']),
        auteur: j['auteur'] as String?,
        deMoi: j['de_moi'] == true,
        auteurParent: j['auteur_parent'] == true,
        masqueLe: DateTime.tryParse(j['masque_le'] as String? ?? '')?.toLocal(),
        motifMasquage: j['motif_masquage'] as String?,
      );

  final String id;
  final String corps;
  final DateTime creeLe;
  final String? auteur;
  final bool deMoi;
  final bool auteurParent;
  final DateTime? masqueLe;
  final String? motifMasquage;
  final bool enAttenteEnvoi;

  bool get masque => masqueLe != null;
}

/// Mot qui ouvre un fil, avec ses réponses.
class MotLiaison {
  const MotLiaison({
    required this.id,
    required this.ficheEleveId,
    required this.corps,
    required this.creeLe,
    this.auteur,
    this.deMoi = false,
    this.masqueLe,
    this.motifMasquage,
    this.lu = false,
    this.lectures,
    this.parents,
    this.reponses = const [],
    this.enAttenteEnvoi = false,
  });

  factory MotLiaison.depuisJson(Map<String, dynamic> j) => MotLiaison(
        id: j['id'] as String,
        ficheEleveId: j['fiche_eleve_id'] as String? ?? '',
        corps: j['corps'] as String? ?? '',
        creeLe: _date(j['cree_le']),
        auteur: j['auteur'] as String?,
        deMoi: j['de_moi'] == true,
        masqueLe: DateTime.tryParse(j['masque_le'] as String? ?? '')?.toLocal(),
        motifMasquage: j['motif_masquage'] as String?,
        lu: j['lu'] == true,
        lectures: (j['lectures'] as num?)?.toInt(),
        parents: (j['parents'] as num?)?.toInt(),
        reponses: [
          for (final r in (j['reponses'] as List?) ?? const []) MessageLiaison.depuisJson((r as Map).cast<String, dynamic>()),
        ],
      );

  final String id;
  final String ficheEleveId;
  final String corps;
  final DateTime creeLe;
  final String? auteur;
  final bool deMoi;
  final DateTime? masqueLe;
  final String? motifMasquage;

  /// Lecture confirmée par le parent connecté.
  final bool lu;

  /// Personnel : parents qui ont confirmé la lecture, sur le total.
  final int? lectures;
  final int? parents;
  final List<MessageLiaison> reponses;
  final bool enAttenteEnvoi;

  bool get masque => masqueLe != null;

  MotLiaison copierAvec({bool? lu, List<MessageLiaison>? reponses}) => MotLiaison(
        id: id,
        ficheEleveId: ficheEleveId,
        corps: corps,
        creeLe: creeLe,
        auteur: auteur,
        deMoi: deMoi,
        masqueLe: masqueLe,
        motifMasquage: motifMasquage,
        lu: lu ?? this.lu,
        lectures: lectures,
        parents: parents,
        reponses: reponses ?? this.reponses,
        enAttenteEnvoi: enAttenteEnvoi,
      );
}

/// Élève du cahier : un enfant (parent) ou un élève de la classe (personnel).
class EleveLiaison {
  const EleveLiaison({required this.ficheEleveId, required this.nom, this.classe, this.aLire = 0});

  factory EleveLiaison.depuisJson(Map<String, dynamic> j) => EleveLiaison(
        ficheEleveId: j['fiche_eleve_id'] as String,
        nom: (j['nom'] as String?)?.trim() ?? '',
        classe: j['classe'] as String?,
        aLire: (j['a_lire'] as num?)?.toInt() ?? 0,
      );

  final String ficheEleveId;
  final String nom;
  final String? classe;

  /// Parent : messages non lus. Personnel : réponses de parents (7 jours).
  final int aLire;
}

class ErreurCahier implements Exception {
  const ErreurCahier(this.code);
  final String code;

  String get message => switch (code) {
        'PERMISSION_REFUSEE' => 'Ce cahier ne vous est pas accessible.',
        'TEXTE_VIDE' => 'Écrivez votre message.',
        'MOTIF_REQUIS' => 'Indiquez la raison (3 caractères au moins).',
        'HORS_CONNEXION' => 'Pas de connexion. Réessayez une fois en ligne.',
        _ => 'Une erreur est survenue. Réessayez.',
      };

  @override
  String toString() => 'ErreurCahier($code)';
}

abstract interface class CahierLiaisonRepository {
  /// Parent : ses enfants (null). Personnel : les élèves de l'école sur
  /// lesquels il peut écrire.
  Future<List<EleveLiaison>> eleves({String? etablissementId});

  /// Fil d'un élève ; sans réseau, le dernier reçu.
  Future<List<MotLiaison>> cahier(String ficheEleveId);

  /// Personnel : nouveau mot. Sans réseau, gardé et envoyé au retour.
  Future<bool> ecrireMot(String ficheEleveId, String corps);

  /// Réponse dans un fil (parent ou personnel). Sans réseau, gardée.
  Future<bool> repondre({required String ficheEleveId, required String motId, required String corps});

  /// Parent : « J'ai lu ». Sans réseau, gardée.
  Future<void> confirmerLecture(String motId);

  /// Direction : masque un message (journalisé). En ligne seulement.
  Future<void> masquer(String messageId, String motif);
}
