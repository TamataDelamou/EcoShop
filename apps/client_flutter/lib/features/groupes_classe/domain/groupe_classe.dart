/// Groupes de classe (REG-34).
///
/// Un groupe par classe et par année, créé par un enseignant de la classe ou
/// la direction — jamais par un élève. Y écrivent les élèves de la classe et
/// leurs enseignants ; la direction et les postes de modération voient tout.
/// Aucun échange privé adulte ↔ élève, aucun parent dans les groupes, texte
/// seulement. Rien n'est effacé : un message retiré reste lisible par les
/// adultes, avec le motif, et l'action est journalisée.
library;

import '../../cahier_liaison/domain/cahier_liaison.dart';

export '../../cahier_liaison/domain/cahier_liaison.dart' show HeuresMessagerie;

DateTime _date(Object? v) => DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime.now();

class GroupeClasse {
  const GroupeClasse({
    required this.id,
    required this.nom,
    required this.classeId,
    required this.classe,
    this.actif = true,
    this.elevesPeuventEcrire = true,
    this.moderateur = false,
    this.nonLus = 0,
    this.dernierAuteur,
    this.dernierExtrait,
    this.dernierLe,
    this.signalements = 0,
  });

  factory GroupeClasse.depuisJson(Map<String, dynamic> j) {
    final dernier = (j['dernier'] as Map?)?.cast<String, dynamic>();
    return GroupeClasse(
      id: j['id'] as String,
      nom: j['nom'] as String? ?? '',
      classeId: j['classe_id'] as String? ?? '',
      classe: j['classe'] as String? ?? '',
      actif: (j['statut'] as String? ?? 'active') == 'active',
      elevesPeuventEcrire: j['eleves_peuvent_ecrire'] != false,
      moderateur: j['moderateur'] == true,
      nonLus: (j['non_lus'] as num?)?.toInt() ?? 0,
      dernierAuteur: dernier?['auteur'] as String?,
      dernierExtrait: dernier?['extrait'] as String?,
      dernierLe: dernier == null ? null : _date(dernier['cree_le']),
      signalements: (j['signalements'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String nom;
  final String classeId;
  final String classe;

  /// Faux : groupe suspendu par la modération (lecture seule pour les élèves).
  final bool actif;

  /// Faux : seuls les enseignants écrivent (annonces de la classe).
  final bool elevesPeuventEcrire;

  /// Enseignant de la classe, direction ou poste de modération.
  final bool moderateur;
  final int nonLus;
  final String? dernierAuteur;

  /// Null si le dernier message a été retiré.
  final String? dernierExtrait;
  final DateTime? dernierLe;

  /// Modération : signalements ouverts.
  final int signalements;
}

class ClasseSansGroupe {
  const ClasseSansGroupe({required this.classeId, required this.classe});

  final String classeId;
  final String classe;
}

class MesGroupes {
  const MesGroupes({this.groupes = const [], this.classesSansGroupe = const []});

  factory MesGroupes.depuisJson(Map<String, dynamic> j) => MesGroupes(
        groupes: [
          for (final g in (j['groupes'] as List?) ?? const []) GroupeClasse.depuisJson((g as Map).cast<String, dynamic>()),
        ],
        classesSansGroupe: [
          for (final c in (j['classes_sans_groupe'] as List?) ?? const [])
            ClasseSansGroupe(classeId: (c as Map)['classe_id'] as String, classe: c['classe'] as String? ?? ''),
        ],
      );

  final List<GroupeClasse> groupes;

  /// Personnel : classes où il peut ouvrir le groupe.
  final List<ClasseSansGroupe> classesSansGroupe;
}

class MessageGroupe {
  const MessageGroupe({
    required this.id,
    required this.creeLe,
    this.auteur,
    this.deMoi = false,
    this.adulte = false,
    this.corps,
    this.masque = false,
    this.motif,
    this.enAttenteEnvoi = false,
  });

  factory MessageGroupe.depuisJson(Map<String, dynamic> j) => MessageGroupe(
        id: j['id'] as String,
        creeLe: _date(j['cree_le']),
        auteur: j['auteur'] as String?,
        deMoi: j['de_moi'] == true,
        adulte: j['adulte'] == true,
        corps: j['corps'] as String?,
        masque: j['masque'] == true,
        motif: j['motif'] as String?,
      );

  final String id;
  final DateTime creeLe;
  final String? auteur;
  final bool deMoi;

  /// Message d'un enseignant ou de la direction (mis en valeur).
  final bool adulte;

  /// Null pour un élève quand le message a été retiré.
  final String? corps;
  final bool masque;

  /// Modération : motif du retrait.
  final String? motif;
  final bool enAttenteEnvoi;
}

class SignalementGroupe {
  const SignalementGroupe({
    required this.id,
    required this.messageId,
    required this.motif,
    this.par,
    this.extrait,
    this.auteur,
  });

  factory SignalementGroupe.depuisJson(Map<String, dynamic> j) => SignalementGroupe(
        id: j['id'] as String,
        messageId: j['message_id'] as String,
        motif: j['motif'] as String? ?? '',
        par: j['par'] as String?,
        extrait: j['extrait'] as String?,
        auteur: j['auteur'] as String?,
      );

  final String id;
  final String messageId;
  final String motif;
  final String? par;
  final String? extrait;
  final String? auteur;
}

class ErreurGroupe implements Exception {
  const ErreurGroupe(this.code);
  final String code;

  String get message => switch (code) {
        'PERMISSION_REFUSEE' => 'Ce groupe ne vous est pas accessible.',
        'TEXTE_VIDE' => 'Écrivez votre message.',
        'MOTIF_REQUIS' => 'Indiquez la raison (3 caractères au moins).',
        'GROUPE_LECTURE_SEULE' => 'Ce groupe ne sert qu’aux messages des enseignants.',
        'GROUPE_SUSPENDU' => 'Ce groupe est suspendu pour le moment.',
        'HORS_HEURES_MESSAGERIE' => 'Le groupe est fermé en dehors des heures de l’école. Réessayez demain.',
        'HEURES_INVALIDES' => 'L’heure de fin doit venir après l’heure de début.',
        'JOURS_INVALIDES' => 'Choisissez au moins un jour.',
        'HORS_CONNEXION' => 'Pas de connexion. Réessayez une fois en ligne.',
        _ => 'Une erreur est survenue. Réessayez.',
      };

  @override
  String toString() => 'ErreurGroupe($code)';
}

abstract interface class GroupesClasseRepository {
  /// Groupes du compte dans cette école ; sans réseau, la dernière liste.
  Future<MesGroupes> mesGroupes(String etablissementId);

  /// Fil d'un groupe (200 derniers) ; sans réseau, le dernier reçu, avec les
  /// messages en attente d'envoi.
  Future<List<MessageGroupe>> fil(String groupeId);

  /// Envoie un message. Sans réseau, gardé et envoyé au retour (faux).
  Future<bool> envoyer(String groupeId, String corps);

  /// Marque le fil comme lu (sans effet sans réseau).
  Future<void> marquerLu(String groupeId);

  /// Personnel : ouvre le groupe d'une classe (renvoie son identifiant).
  Future<String> creer(String classeId);

  /// Modération : groupe ouvert aux élèves ou réservé aux annonces ; actif ou
  /// suspendu.
  Future<void> regler(String groupeId, {required bool elevesPeuventEcrire, required bool actif});

  /// Tout membre : signale un message à la modération.
  Future<void> signaler(String messageId, String motif);

  /// Modération : retire un message (motif, journal d'audit).
  Future<void> masquer(String messageId, String motif);

  Future<List<SignalementGroupe>> signalements(String groupeId);

  /// Modération : signalement écarté, message conservé.
  Future<void> ecarter(String signalementId);

  /// Heures de messagerie de l'école ; sans réseau, les dernières lues.
  Future<HeuresMessagerie?> heures(String etablissementId);

  /// Direction : règle les heures de messagerie (heures « HH:MM », jours ISO).
  Future<void> definirHeures(String etablissementId, {required String debut, required String fin, required List<int> jours});
}
