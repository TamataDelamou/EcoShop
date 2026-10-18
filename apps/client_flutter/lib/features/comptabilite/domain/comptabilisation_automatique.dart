/// Comptabilisation automatique des encaissements (REG-03, lot C3) et de la
/// paie (lot C5).
///
/// Le serveur crée seul les pièces (migrations `20260906001536` et
/// `20260906001538`, tests/rls/65 et 67) ; le client affiche l'état, lance
/// le rattrapage et règle les comptes utilisés.
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
  'paie:charge': 'Salaires (charge)',
  'paie:dette': 'Salaires dus au personnel',
  'paie:retenues': 'Retenues sur salaire',
  'paie:tresorerie': 'Paiement des salaires',
  'don:don': 'Dons',
  'don:legs': 'Legs',
  'don:denier_culte': 'Deniers du culte',
  'don:quete': 'Quêtes',
  'don:mecenat': 'Mécénat',
  'don:parrainage': 'Parrainage',
  'don:autre': 'Autres dons',
  'don:fonds_affectes': 'Dons affectés à un projet',
  'don:reprise_fonds_affectes': 'Emploi des fonds affectés (reprise)',
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
  bool get estTresorerie => cle.startsWith('tresorerie:') || cle == 'paie:tresorerie';
  bool get estPaie => cle.startsWith('paie:');
  bool get estDon => cle.startsWith('don:');
  String get compteAffiche => compteCode == null ? 'Aucun compte' : '$compteCode — ${compteIntitule ?? ''}';
}

class IncidentComptabilisation {
  const IncidentComptabilisation({
    required this.id,
    required this.code,
    required this.operation,
    required this.le,
    this.sourceType = 'encaissement_scolarite',
  });

  factory IncidentComptabilisation.depuisJson(Map<String, dynamic> json) => IncidentComptabilisation(
        id: json['id'] as String,
        code: json['code'] as String,
        operation: json['operation'] as String,
        le: DateTime.parse(json['le'] as String),
        sourceType: json['source_type'] as String? ?? 'encaissement_scolarite',
      );

  final String id;
  final String code;
  final String operation;
  final DateTime le;
  final String sourceType;

  bool get estPaie => sourceType == 'paie_bulletin';
  bool get estDon => sourceType == 'don' || sourceType == 'emploi_fonds_affectes';

  /// Ce qui a déclenché l'incident, en clair.
  String get origine => switch (sourceType) {
        'paie_bulletin' => 'Bulletin de paie',
        'don' => operation == 'annulation' ? 'Annulation de don' : 'Don',
        'emploi_fonds_affectes' => 'Emploi de fonds affectés',
        _ => operation == 'annulation' ? 'Annulation de paiement' : 'Paiement',
      };

  String get explication {
    final objet = switch (sourceType) {
      'paie_bulletin' => 'du bulletin de paie',
      'don' => 'du don',
      'emploi_fonds_affectes' => 'de l\'emploi des fonds',
      _ => 'du paiement',
    };
    return switch (code) {
      'AUCUN_EXERCICE_OUVERT' => 'Aucun exercice ouvert à la date $objet : ouvrez l\'exercice puis rattrapez.',
      'PERIODE_CLOTUREE' => 'Date $objet dans une période déjà clôturée : à régulariser par la comptable.',
      'COMPTE_AUTO_INTROUVABLE' => 'Compte introuvable : choisissez-le dans les règles ci-dessous.',
      'PIECE_EXERCICE_CLOTURE' => 'Correction d\'une pièce d\'un exercice clôturé : passer par le report à nouveau.',
      _ => 'Comptabilisation impossible ($code).',
    };
  }
}

class EtatComptabilisationAutomatique {
  const EtatComptabilisationAutomatique({
    required this.active,
    required this.nonComptabilises,
    required this.annulationsEnAttente,
    this.paiesASynchroniser = 0,
    this.donsAComptabiliser = 0,
    this.incidents = const [],
    this.regles = const [],
  });

  factory EtatComptabilisationAutomatique.depuisJson(Map<String, dynamic> json) => EtatComptabilisationAutomatique(
        active: json['active'] as bool? ?? false,
        nonComptabilises: (json['non_comptabilises'] as num?)?.toInt() ?? 0,
        annulationsEnAttente: (json['annulations_en_attente'] as num?)?.toInt() ?? 0,
        paiesASynchroniser: (json['paies_a_synchroniser'] as num?)?.toInt() ?? 0,
        donsAComptabiliser: (json['dons_a_comptabiliser'] as num?)?.toInt() ?? 0,
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

  /// Bulletins validés/payés sans pièce, ou modifiés après coup (lot C5).
  final int paiesASynchroniser;

  /// Dons et emplois de fonds affectés à reporter (lot C5).
  final int donsAComptabiliser;
  final List<IncidentComptabilisation> incidents;
  final List<RegleComptabilisation> regles;

  bool get aJour => nonComptabilises == 0 && annulationsEnAttente == 0 && paiesASynchroniser == 0 && donsAComptabiliser == 0;
}

class ErreurComptabilisationAutomatique implements Exception {
  const ErreurComptabilisationAutomatique(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'COMPTE_NON_IMPUTABLE' => 'Ce compte regroupe d\'autres comptes : choisissez un compte de détail.',
        'COMPTABLE_ECRITURE_REQUIS' || 'COMPTABLE_REQUIS' => 'Vous n\'avez pas les droits de comptabilité.',
        'HORS_CONNEXION' =>
          'Pas de réseau. Les écrans déjà consultés restent lisibles sur cet appareil ; cette action (ou une page '
              'jamais ouverte ici) attend le retour du réseau.',
        _ => 'Opération impossible pour le moment. Réessayez dans un instant.',
      };

  @override
  String toString() => 'ErreurComptabilisationAutomatique($code)';
}

abstract interface class ComptabilisationAutomatiqueRepository {
  Future<EtatComptabilisationAutomatique> etat(String etablissementId);

  /// Rattrapage (paiements et paie) : renvoie le nombre d'opérations
  /// comptabilisées et en échec.
  Future<({int comptabilises, int enEchec})> rattraper(String etablissementId);

  /// [compteId] null : retour au compte par défaut du plan.
  Future<void> definirRegle(String etablissementId, String cle, String? compteId);
}
