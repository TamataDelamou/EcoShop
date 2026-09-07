/// Type d'entrée du prototype local de communication (messagerie, annonces,
/// cahier de liaison) — voir [EntreeCommunicationLocale].
enum TypeEntreeLocale {
  message('message'),
  annonce('annonce'),
  motLiaison('mot_liaison');

  const TypeEntreeLocale(this.code);
  final String code;
}

/// Entrée du **prototype local** de messagerie/annonces/cahier de liaison
/// (M9) — persistée uniquement dans le cache Drift de l'appareil
/// (`CommunicationLocaleRepository`), **jamais envoyée au serveur** : aucune
/// table `conversations`/`messages`/`annonces`/`cahier_liaison` n'existe
/// dans le schéma Postgres actuel (voir le rapport de clôture M9). Cette
/// IHM démontre le parcours attendu, en attendant une migration backend
/// dédiée — elle ne doit jamais être présentée à l'utilisateur comme une
/// messagerie réellement partagée entre appareils.
class EntreeCommunicationLocale {
  const EntreeCommunicationLocale({
    required this.id,
    required this.type,
    required this.auteurId,
    required this.auteurNom,
    required this.destinataireLabel,
    this.titre,
    required this.contenu,
    this.pieceJointeNoms = const [],
    required this.dateCreation,
    this.lu = false,
    this.important = false,
    this.accuseReception = false,
    this.signalee = false,
  });

  factory EntreeCommunicationLocale.depuisJson(Map<String, dynamic> json) => EntreeCommunicationLocale(
        id: json['id'] as String,
        type: TypeEntreeLocale.values.firstWhere((t) => t.code == json['type'], orElse: () => TypeEntreeLocale.message),
        auteurId: json['auteur_id'] as String,
        auteurNom: json['auteur_nom'] as String,
        destinataireLabel: json['destinataire_label'] as String,
        titre: json['titre'] as String?,
        contenu: json['contenu'] as String,
        pieceJointeNoms: (json['piece_jointe_noms'] as List<dynamic>?)?.cast<String>() ?? const [],
        dateCreation: DateTime.parse(json['date_creation'] as String),
        lu: json['lu'] as bool? ?? false,
        important: json['important'] as bool? ?? false,
        accuseReception: json['accuse_reception'] as bool? ?? false,
        signalee: json['signalee'] as bool? ?? false,
      );

  Map<String, dynamic> versJson() => {
        'id': id,
        'type': type.code,
        'auteur_id': auteurId,
        'auteur_nom': auteurNom,
        'destinataire_label': destinataireLabel,
        'titre': titre,
        'contenu': contenu,
        'piece_jointe_noms': pieceJointeNoms,
        'date_creation': dateCreation.toIso8601String(),
        'lu': lu,
        'important': important,
        'accuse_reception': accuseReception,
        'signalee': signalee,
      };

  EntreeCommunicationLocale copierAvec({bool? lu, bool? accuseReception}) => EntreeCommunicationLocale(
        id: id,
        type: type,
        auteurId: auteurId,
        auteurNom: auteurNom,
        destinataireLabel: destinataireLabel,
        titre: titre,
        contenu: contenu,
        pieceJointeNoms: pieceJointeNoms,
        dateCreation: dateCreation,
        lu: lu ?? this.lu,
        important: important,
        accuseReception: accuseReception ?? this.accuseReception,
        signalee: signalee,
      );

  final String id;
  final TypeEntreeLocale type;
  final String auteurId;
  final String auteurNom;

  /// Étiquette libre du destinataire (nom de fil, classe, niveau, ou nom de
  /// l'enfant pour le cahier de liaison) — pas une relation vers une table
  /// réelle, purement descriptive dans ce prototype.
  final String destinataireLabel;
  final String? titre;
  final String contenu;
  final List<String> pieceJointeNoms;
  final DateTime dateCreation;
  final bool lu;

  /// Annonce importante nécessitant un accusé de réception.
  final bool important;
  final bool accuseReception;

  /// Signalée par le lexique local de modération (voir `moderation_locale.dart`).
  final bool signalee;
}
