/// Annonces de l'école (REG-19, lot 1) : la direction publie pour toute
/// l'école, un niveau ou une classe ; les parents confirmés et les élèves
/// concernés lisent ; la direction voit combien de familles ont lu.
library;

enum PorteeAnnonce {
  ecole('ecole', 'Toute l’école'),
  niveau('niveau', 'Un niveau'),
  classe('classe', 'Une classe');

  const PorteeAnnonce(this.code, this.libelle);
  final String code;
  final String libelle;

  static PorteeAnnonce depuisCode(String? code) =>
      PorteeAnnonce.values.firstWhere((p) => p.code == code, orElse: () => PorteeAnnonce.ecole);
}

class Annonce {
  const Annonce({
    required this.id,
    required this.etablissementId,
    required this.titre,
    required this.corps,
    required this.portee,
    required this.publieeLe,
    this.etablissement,
    this.importante = false,
    this.classe,
    this.niveau,
    this.lue = false,
    this.enAttenteEnvoi = false,
    this.familles,
    this.famillesLues,
    this.masqueeLe,
    this.motifMasquage,
    this.parSms = false,
  });

  factory Annonce.depuisJson(Map<String, dynamic> j) => Annonce(
        id: j['id'] as String,
        etablissementId: j['etablissement_id'] as String? ?? '',
        etablissement: j['etablissement'] as String?,
        titre: j['titre'] as String? ?? '',
        corps: j['corps'] as String? ?? '',
        importante: j['importante'] == true,
        portee: PorteeAnnonce.depuisCode(j['portee'] as String?),
        classe: j['classe'] as String?,
        niveau: j['niveau'] as String?,
        publieeLe: DateTime.tryParse(j['publiee_le'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        lue: j['lue'] == true,
        familles: (j['familles'] as num?)?.toInt(),
        famillesLues: (j['familles_lues'] as num?)?.toInt(),
        masqueeLe: DateTime.tryParse(j['masquee_le'] as String? ?? '')?.toLocal(),
        motifMasquage: j['motif_masquage'] as String?,
        parSms: j['par_sms'] == true,
      );

  final String id;
  final String etablissementId;
  final String? etablissement;
  final String titre;
  final String corps;
  final bool importante;
  final PorteeAnnonce portee;
  final String? classe;
  final String? niveau;
  final DateTime publieeLe;

  /// Lecture confirmée par le compte connecté.
  final bool lue;

  /// Publiée ou lue sans réseau : partira au retour du réseau.
  final bool enAttenteEnvoi;

  // Vue de la direction.
  final int? familles;
  final int? famillesLues;
  final DateTime? masqueeLe;
  final String? motifMasquage;
  final bool parSms;

  bool get masquee => masqueeLe != null;

  /// « Toute l'école », « CM1 »…
  String get cible => switch (portee) {
        PorteeAnnonce.ecole => 'Toute l’école',
        PorteeAnnonce.niveau => niveau ?? 'Un niveau',
        PorteeAnnonce.classe => classe ?? 'Une classe',
      };

  Annonce copierAvec({bool? lue}) => Annonce(
        id: id,
        etablissementId: etablissementId,
        etablissement: etablissement,
        titre: titre,
        corps: corps,
        importante: importante,
        portee: portee,
        classe: classe,
        niveau: niveau,
        publieeLe: publieeLe,
        lue: lue ?? this.lue,
        enAttenteEnvoi: enAttenteEnvoi,
        familles: familles,
        famillesLues: famillesLues,
        masqueeLe: masqueeLe,
        motifMasquage: motifMasquage,
        parSms: parSms,
      );
}

class CibleAnnonce {
  const CibleAnnonce(this.id, this.nom);
  final String id;
  final String nom;
}

/// Classes et niveaux de l'année courante.
class PorteesDisponibles {
  const PorteesDisponibles({this.classes = const [], this.niveaux = const []});

  factory PorteesDisponibles.depuisJson(Map<String, dynamic> j) {
    List<CibleAnnonce> liste(Object? v) => [
          for (final e in (v as List?) ?? const [])
            CibleAnnonce((e as Map)['id'] as String, e['nom'] as String? ?? ''),
        ]..sort((a, b) => a.nom.compareTo(b.nom));
    return PorteesDisponibles(classes: liste(j['classes']), niveaux: liste(j['niveaux']));
  }

  final List<CibleAnnonce> classes;
  final List<CibleAnnonce> niveaux;
}

/// Résultat d'une publication.
class ResultatPublication {
  const ResultatPublication({required this.recue, this.familles, this.sms, this.smsNonEnvoyes});

  /// Faux : sans réseau, la publication attend sur le téléphone.
  final bool recue;
  final int? familles;
  final int? sms;
  final int? smsNonEnvoyes;
}

class ErreurAnnonces implements Exception {
  const ErreurAnnonces(this.code);
  final String code;

  String get message => switch (code) {
        'PERMISSION_REFUSEE' => 'Réservé à la direction de l’école.',
        'AUCUN_DESTINATAIRE' => 'Aucune famille dans cette portée pour l’année en cours.',
        'PORTEE_INVALIDE' => 'Choisissez un niveau ou une classe de l’école.',
        'TEXTE_TROP_COURT' => 'Titre et texte : 3 caractères au moins.',
        'MOTIF_REQUIS' => 'Indiquez la raison (3 caractères au moins).',
        'HORS_CONNEXION' => 'Pas de connexion. Réessayez une fois en ligne.',
        _ => 'Une erreur est survenue. Réessayez.',
      };

  @override
  String toString() => 'ErreurAnnonces($code)';
}

abstract interface class AnnoncesRepository {
  /// Annonces reçues (toutes écoles) ; sans réseau, les dernières reçues.
  Future<List<Annonce>> mesAnnonces();

  /// Confirme la lecture ; sans réseau, gardée et envoyée au retour.
  Future<void> marquerLue(String annonceId);

  /// Annonces de l'école, pour la direction (lectures, masquées).
  Future<List<Annonce>> annoncesEtablissement(String etablissementId);

  Future<PorteesDisponibles> portees(String etablissementId);

  /// Publie ; sans réseau, garde la publication (clé de l'appareil, jamais de
  /// doublon au renvoi).
  Future<ResultatPublication> publier({
    required String etablissementId,
    required PorteeAnnonce portee,
    String? cibleId,
    required String titre,
    required String corps,
    bool importante = false,
    bool parSms = false,
  });

  /// Masque l'annonce pour les familles (journalisé). En ligne seulement.
  Future<void> masquer(String annonceId, String motif);
}
