/// Comptabilisation automatique des encaissements (REG-03, lot C3).
///
/// Le serveur crée seul les pièces (migration `20260906001536`,
/// tests/rls/65) ; le client affiche l'état, lance le rattrapage et règle
/// les comptes utilisés.
library;

const libellesCles = <String, String>{
  'tresorerie:especes': 'Espèces',
  'tresorerie:mobile_money': 'Orange Money',
  'tresorerie:virement': 'Virement',
  'tresorerie:cheque': 'Chèque',
  'tresorerie:autre': 'Autre moyen',
  'produit:scolarite': 'Frais de scolarité',
  'produit:inscription': 'Inscriptions',
  'produit:cantine': 'Cantine',
  'produit:transport': 'Transport',
  'produit:autre': 'Autres frais',
};

class RegleComptabilisation {
  const RegleComptabilisation({
    required this.cle,
    this.compteId,
    this.compteCode,
    this.compteIntitule,
    this.personnalisee = false,
  });

  factory RegleComptabilisation.depuisJson(Map<String, dynamic> json) => RegleComptabilisation(
        cle: json['cle'] as String,
        compteId: json['compte_id'] as String?,
        compteCode: json['compte_code'] as String?,
        compteIntitule: json['compte_intitule'] as String?,
        personnalisee: json['personnalisee'] as bool? ?? false,
      );

  final String cle;
  final String? compteId;
  final String? compteCode;
  final String? compteIntitule;
  final bool personnalisee;

  String get libelle => libellesCles[cle] ?? cle;
  bool get estTresorerie => cle.startsWith('tresorerie:');
  String get compteAffiche => compteCode == null ? 'Aucun compte' : '$compteCode — ${compteIntitule ?? ''}';
}

class IncidentComptabilisation {
  const IncidentComptabilisation({required this.id, required this.code, required this.operation, required this.le});

  factory IncidentComptabilisation.depuisJson(Map<String, dynamic> json) => IncidentComptabilisation(
        id: json['id'] as String,
        code: json['code'] as String,
        operation: json['operation'] as String,
        le: DateTime.parse(json['le'] as String),
      );

  final String id;
  final String code;
  final String operation;
  final DateTime le;

  String get explication => switch (code) {
        'AUCUN_EXERCICE_OUVERT' => 'Aucun exercice ouvert à la date du paiement : ouvrez l\'exercice puis rattrapez.',
        'PERIODE_CLOTUREE' => 'Paiement daté d\'une période déjà clôturée : à régulariser par la comptable.',
        'COMPTE_AUTO_INTROUVABLE' => 'Compte introuvable : choisissez-le dans les règles ci-dessous.',
        'PIECE_EXERCICE_CLOTURE' => 'Annulation d\'un paiement d\'un exercice clôturé : correction par report à nouveau.',
        _ => 'Comptabilisation impossible ($code).',
      };
}

class EtatComptabilisationAutomatique {
  const EtatComptabilisationAutomatique({
    required this.active,
    required this.nonComptabilises,
    required this.annulationsEnAttente,
    this.incidents = const [],
    this.regles = const [],
  });

  factory EtatComptabilisationAutomatique.depuisJson(Map<String, dynamic> json) => EtatComptabilisationAutomatique(
        active: json['active'] as bool? ?? false,
        nonComptabilises: (json['non_comptabilises'] as num?)?.toInt() ?? 0,
        annulationsEnAttente: (json['annulations_en_attente'] as num?)?.toInt() ?? 0,
        incidents: [
          for (final i in (json['incidents'] as List<dynamic>? ?? const []))
            IncidentComptabilisation.depuisJson(i as Map<String, dynamic>),
        ],
        regles: [
          for (final r in (json['regles'] as List<dynamic>? ?? const []))
            RegleComptabilisation.depuisJson(r as Map<String, dynamic>),
        ],
      );

  final bool active;
  final int nonComptabilises;
  final int annulationsEnAttente;
  final List<IncidentComptabilisation> incidents;
  final List<RegleComptabilisation> regles;

  bool get aJour => nonComptabilises == 0 && annulationsEnAttente == 0;
}

class ErreurComptabilisationAutomatique implements Exception {
  const ErreurComptabilisationAutomatique(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'COMPTE_NON_IMPUTABLE' => 'Ce compte regroupe d\'autres comptes : choisissez un compte de détail.',
        'COMPTABLE_ECRITURE_REQUIS' || 'COMPTABLE_REQUIS' => 'Vous n\'avez pas les droits de comptabilité.',
        _ => 'Opération impossible pour le moment. Réessayez dans un instant.',
      };

  @override
  String toString() => 'ErreurComptabilisationAutomatique($code)';
}

abstract interface class ComptabilisationAutomatiqueRepository {
  Future<EtatComptabilisationAutomatique> etat(String etablissementId);

  /// Rattrapage : renvoie le nombre de paiements comptabilisés et en échec.
  Future<({int comptabilises, int enEchec})> rattraper(String etablissementId);

  /// [compteId] null : retour au compte par défaut du plan.
  Future<void> definirRegle(String etablissementId, String cle, String? compteId);
}
