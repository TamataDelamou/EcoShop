/// Justificatif d'absence (REG-36) : déposé par la famille, décidé par la
/// vie scolaire de l'école (modèle de Pronote).
library;

enum MotifJustificatif {
  maladie('maladie', 'Maladie'),
  rendezVousMedical('rendez_vous_medical', 'Rendez-vous médical'),
  raisonFamiliale('raison_familiale', 'Raison familiale'),
  transport('transport', 'Problème de transport'),
  autre('autre', 'Autre motif');

  const MotifJustificatif(this.code, this.libelle);

  final String code;
  final String libelle;

  static MotifJustificatif depuisCode(String? code) =>
      values.firstWhere((m) => m.code == code, orElse: () => MotifJustificatif.autre);
}

enum StatutJustificatif {
  depose('depose', 'En attente de la vie scolaire'),
  accepte('accepte', 'Accepté — absence justifiée'),
  refuse('refuse', 'Refusé');

  const StatutJustificatif(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutJustificatif depuisCode(String? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => StatutJustificatif.depose);
}

String _jour(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Justificatif {
  const Justificatif({
    required this.id,
    required this.etablissementId,
    required this.ficheEleveId,
    required this.dateDebut,
    required this.dateFin,
    required this.motif,
    this.commentaire,
    this.pieceChemin,
    this.statut = StatutJustificatif.depose,
    this.motifRefus,
    this.deposeLe,
    this.nomEleve,
    this.enAttenteEnvoi = false,
    this.avecPieceEnAttente = false,
  });

  final String id;
  final String etablissementId;
  final String ficheEleveId;
  final DateTime dateDebut;
  final DateTime dateFin;
  final MotifJustificatif motif;
  final String? commentaire;
  final String? pieceChemin;
  final StatutJustificatif statut;
  final String? motifRefus;
  final DateTime? deposeLe;

  /// « Fanta CAMARA » (liste de la vie scolaire).
  final String? nomEleve;

  /// Déposé sans réseau, pas encore reçu par l'école.
  final bool enAttenteEnvoi;

  /// Photo gardée sur le téléphone avec le dépôt en attente.
  final bool avecPieceEnAttente;

  bool get aUnePiece => pieceChemin != null || avecPieceEnAttente;

  factory Justificatif.depuisJson(Map<String, dynamic> json) {
    final fiche = json['fiches_eleves'] as Map<String, dynamic>?;
    return Justificatif(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      dateDebut: DateTime.parse(json['date_debut'] as String),
      dateFin: DateTime.parse(json['date_fin'] as String),
      motif: MotifJustificatif.depuisCode(json['motif'] as String?),
      commentaire: json['commentaire'] as String?,
      pieceChemin: json['piece_chemin'] as String?,
      statut: StatutJustificatif.depuisCode(json['statut'] as String?),
      motifRefus: json['motif_refus'] as String?,
      deposeLe: json['depose_le'] == null ? null : DateTime.parse(json['depose_le'] as String),
      nomEleve: fiche == null ? null : '${fiche['prenom'] ?? ''} ${fiche['nom'] ?? ''}'.trim(),
    );
  }

  /// Ligne envoyée au serveur (statut et décision : jamais côté famille).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'fiche_eleve_id': ficheEleveId,
        'date_debut': _jour(dateDebut),
        'date_fin': _jour(dateFin),
        'motif': motif.code,
        if (commentaire != null && commentaire!.trim().isNotEmpty) 'commentaire': commentaire!.trim(),
      };

  Justificatif enAttente({required bool avecPiece}) => Justificatif(
        id: id,
        etablissementId: etablissementId,
        ficheEleveId: ficheEleveId,
        dateDebut: dateDebut,
        dateFin: dateFin,
        motif: motif,
        commentaire: commentaire,
        deposeLe: deposeLe,
        nomEleve: nomEleve,
        enAttenteEnvoi: true,
        avecPieceEnAttente: avecPiece,
      );
}

/// Erreur lisible par la famille ou la vie scolaire.
class ErreurJustificatif implements Exception {
  const ErreurJustificatif(this.code);

  final String code;

  String get message => switch (code) {
        'PERMISSION_REFUSEE' => 'Vous n’avez pas le droit de faire cette opération pour cet élève.',
        'JUSTIFICATIF_DEJA_TRAITE' => 'Ce justificatif a déjà été traité par la vie scolaire.',
        'MOTIF_REFUS_REQUIS' => 'Indiquez au parent pourquoi le justificatif est refusé.',
        'FICHIER_TROP_LOURD' => 'La photo dépasse 2 Mo : reprenez-la de plus loin.',
        'PERIODE_INVALIDE' => 'La date de fin doit suivre la date de début (60 jours au plus).',
        _ => 'Le serveur n’a pas pu enregistrer : réessayez dans un instant.',
      };

  @override
  String toString() => 'ErreurJustificatif($code)';
}
