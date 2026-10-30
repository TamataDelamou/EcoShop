/// Cahier de liaison (REG-19, lot 2) : l'enseignant de la classe ou la
/// direction écrit au sujet d'un élève ; seuls les parents confirmés de cet
/// élève le lisent, confirment la lecture et répondent en texte.
///
/// REG-34 : le parent écrit aussi à l'école — à un enseignant de son enfant
/// ou à la direction. Ce fil-là n'est lu que par ce destinataire, la
/// direction et les parents ; hors des heures de messagerie de l'école, le
/// destinataire n'est prévenu qu'à l'ouverture.
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
    this.lu = false,
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
        lu: j['lu'] == true,
      );

  final String id;
  final String corps;
  final DateTime creeLe;
  final String? auteur;
  final bool deMoi;
  final bool auteurParent;
  final DateTime? masqueLe;
  final String? motifMasquage;

  /// Lecture confirmée par le compte connecté.
  final bool lu;
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
    this.auteurParent = false,
    this.destinataire,
    this.luParEcole = false,
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
        auteurParent: j['auteur_parent'] == true,
        destinataire: j['destinataire'] as String?,
        luParEcole: j['lu_par_ecole'] == true,
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

  /// Fil ouvert par un parent (REG-34).
  final bool auteurParent;

  /// Fil ouvert par un parent : membre du personnel à qui il écrit.
  final String? destinataire;

  /// Fil ouvert par un parent : un membre du personnel l'a lu.
  final bool luParEcole;
  final DateTime? masqueLe;
  final String? motifMasquage;

  /// Lecture confirmée par le compte connecté.
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
        auteurParent: auteurParent,
        destinataire: destinataire,
        luParEcole: luParEcole,
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
  const EleveLiaison({required this.ficheEleveId, required this.nom, this.classe, this.etablissementId, this.aLire = 0});

  factory EleveLiaison.depuisJson(Map<String, dynamic> j) => EleveLiaison(
        ficheEleveId: j['fiche_eleve_id'] as String,
        nom: (j['nom'] as String?)?.trim() ?? '',
        classe: j['classe'] as String?,
        etablissementId: j['etablissement_id'] as String?,
        aLire: (j['a_lire'] as num?)?.toInt() ?? 0,
      );

  final String ficheEleveId;
  final String nom;
  final String? classe;
  final String? etablissementId;

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
        'DESTINATAIRE_INVALIDE' => 'Cette personne ne suit plus votre enfant. Choisissez un autre destinataire.',
        'HORS_CONNEXION' => 'Pas de connexion. Réessayez une fois en ligne.',
        _ => 'Une erreur est survenue. Réessayez.',
      };

  @override
  String toString() => 'ErreurCahier($code)';
}

/// Personne de l'école à qui un parent peut écrire.
class DestinataireLiaison {
  const DestinataireLiaison({required this.id, required this.nom, required this.role});

  factory DestinataireLiaison.depuisJson(Map<String, dynamic> j) => DestinataireLiaison(
        id: j['id'] as String,
        nom: (j['nom'] as String?)?.trim().isNotEmpty == true ? (j['nom'] as String).trim() : 'Membre de l’école',
        role: j['role'] as String? ?? '',
      );

  final String id;
  final String nom;

  /// « Direction », ou les matières de l'enseignant (« Mathématiques, SVT »).
  final String role;
}

/// Heures où l'école lit ses messages (REG-34). Hors de ces heures, le
/// message part mais le personnel n'est prévenu qu'à l'ouverture.
class HeuresMessagerie {
  const HeuresMessagerie({required this.debut, required this.fin, required this.jours, this.ouverte = true});

  factory HeuresMessagerie.depuisJson(Map<String, dynamic> j) => HeuresMessagerie(
        debut: j['debut'] as String? ?? '07:00',
        fin: j['fin'] as String? ?? '19:00',
        jours: [for (final d in (j['jours'] as List?) ?? const []) (d as num).toInt()],
        ouverte: j['ouverte'] != false,
      );

  /// « HH:MM ».
  final String debut;
  final String fin;

  /// Jours ISO : 1 = lundi … 7 = dimanche.
  final List<int> jours;
  final bool ouverte;

  static const nomsJours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

  static String heure(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? parts[1] : '00';
    return m == '00' ? '$h h' : '$h h $m';
  }

  /// « du lundi au samedi », « lundi, mercredi et vendredi ».
  String get libelleJours {
    final j = [...jours]..sort();
    if (j.isEmpty) return 'aucun jour';
    if (j.length == 7) return 'tous les jours';
    final suite = j.length > 2 && j.last - j.first == j.length - 1;
    if (suite) return 'du ${nomsJours[j.first - 1]} au ${nomsJours[j.last - 1]}';
    final noms = [for (final d in j) nomsJours[d - 1]];
    return noms.length == 1 ? 'le ${noms.first}' : '${noms.sublist(0, noms.length - 1).join(', ')} et ${noms.last}';
  }

  /// « du lundi au samedi, de 7 h à 19 h ».
  String get libelle => '$libelleJours, de ${heure(debut)} à ${heure(fin)}';
}

/// Destinataires proposés au parent, et heures de l'école.
class ContactsEcole {
  const ContactsEcole({required this.destinataires, this.heures});

  final List<DestinataireLiaison> destinataires;
  final HeuresMessagerie? heures;
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

  /// « J'ai lu » : le parent pour un mot de l'école, le personnel pour un
  /// message de parent. Sans réseau, gardée.
  Future<void> confirmerLecture(String motId);

  /// Parent : à qui écrire au sujet de cet enfant, et quand l'école lit.
  Future<ContactsEcole> contacts(String ficheEleveId);

  /// Parent : écrit à un enseignant de son enfant ou à la direction. Sans
  /// réseau, gardé et envoyé au retour.
  Future<bool> ecrireAEcole({required String ficheEleveId, required String destinataireId, required String corps});

  /// Direction : masque un message (journalisé). En ligne seulement.
  Future<void> masquer(String messageId, String motif);
}
