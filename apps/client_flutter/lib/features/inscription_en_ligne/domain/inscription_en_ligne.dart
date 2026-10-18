import 'dart:typed_data';

/// Inscriptions et réinscriptions en ligne (REG-08).
///
/// Décisions du porteur de projet : campagne datée par la Direction ; en
/// primaire le parent seul, dès le collège (CITE ≥ 2) l'élève comme le
/// parent ; on enregistre qui paie ; aucun blocage automatique (impayé,
/// sanction) — la Direction décide ; hors connexion d'abord.

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
double _nombre(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Étapes d'un dossier (`public.statut_demande_inscription`).
enum StatutDemandeInscription {
  soumise('soumise', 'Reçue — en examen'),
  incomplete('incomplete', 'Pièces à fournir'),
  convoquee('convoquee', 'Convocation'),
  aExaminer('a_examiner', 'À examiner par la direction'),
  acceptee('acceptee', 'Acceptée — à régler'),
  listeAttente('liste_attente', "Liste d'attente"),
  inscrite('inscrite', 'Inscription confirmée'),
  refusee('refusee', 'Non retenue'),
  expiree('expiree', 'Délai dépassé'),
  desistement('desistement', 'Ne revient pas'),
  retiree('retiree', 'Retirée');

  const StatutDemandeInscription(this.code, this.libelle);

  final String code;
  final String libelle;

  /// Le dossier n'évoluera plus.
  bool get estClos => this == inscrite || this == refusee || this == expiree || this == desistement || this == retiree;

  /// Le demandeur peut encore déposer des pièces.
  bool get accepteDesPieces => !estClos;

  static StatutDemandeInscription depuisCode(String? code) =>
      values.firstWhere((v) => v.code == code, orElse: () => soumise);
}

/// Pièce exigée par la campagne, éventuellement pour certains cycles.
class PieceRequise {
  const PieceRequise({
    required this.code,
    required this.libelle,
    this.obligatoire = true,
    this.iscedMin = 0,
    this.iscedMax = 8,
  });

  factory PieceRequise.depuisJson(Map<String, dynamic> j) => PieceRequise(
        code: j['code'] as String,
        libelle: j['libelle'] as String? ?? j['code'] as String,
        obligatoire: j['obligatoire'] as bool? ?? true,
        iscedMin: (j['isced_min'] as num?)?.toInt() ?? 0,
        iscedMax: (j['isced_max'] as num?)?.toInt() ?? 8,
      );

  final String code;
  final String libelle;
  final bool obligatoire;
  final int iscedMin;
  final int iscedMax;

  bool concerne(int isced) => isced >= iscedMin && isced <= iscedMax;

  Map<String, dynamic> versJson() => {
        'code': code,
        'libelle': libelle,
        'obligatoire': obligatoire,
        'isced_min': iscedMin,
        'isced_max': iscedMax,
      };

  /// Code technique dérivé d'un libellé saisi par la Direction.
  static String codeDepuisLibelle(String libelle) {
    const accents = {'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i',
      'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c'};
    final sans = libelle.toLowerCase().split('').map((c) => accents[c] ?? c).join();
    final code = sans.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    final borne = code.length > 40 ? code.substring(0, 40) : code;
    return borne.length < 2 ? 'piece_$borne' : borne;
  }
}

/// Niveau ouvert par l'établissement pour l'année de la campagne.
class NiveauOffert {
  const NiveauOffert({
    required this.niveauId,
    required this.nom,
    required this.isced,
    this.placesRestantes,
    this.fraisInscription = 0,
  });

  factory NiveauOffert.depuisJson(Map<String, dynamic> j) => NiveauOffert(
        niveauId: j['niveau_id'] as String,
        nom: j['nom'] as String? ?? '',
        isced: (j['isced'] as num?)?.toInt() ?? 0,
        placesRestantes: (j['places_restantes'] as num?)?.toInt(),
        fraisInscription: _nombre(j['frais_inscription']),
      );

  final String niveauId;
  final String nom;
  final int isced;

  /// `null` : places non limitées.
  final int? placesRestantes;
  final double fraisInscription;

  /// Dès le collège, l'élève peut faire sa demande et payer lui-même.
  bool get eleveAutonomePossible => isced >= 2;
  bool get complet => placesRestantes != null && placesRestantes! <= 0;
}

/// Campagne publiée, telle que la voit une famille.
class CampagneOuverte {
  const CampagneOuverte({
    required this.campagneId,
    required this.etablissementId,
    required this.etablissementNom,
    this.ville,
    required this.annee,
    required this.dateLimite,
    required this.nouvellesOuvertes,
    this.ouvertureNouvelles,
    this.piecesRequises = const [],
    this.consignes,
    this.niveaux = const [],
  });

  factory CampagneOuverte.depuisJson(Map<String, dynamic> j) => CampagneOuverte(
        campagneId: j['campagne_id'] as String,
        etablissementId: j['etablissement_id'] as String,
        etablissementNom: j['etablissement_nom'] as String? ?? '',
        ville: j['ville'] as String?,
        annee: j['annee'] as String? ?? '',
        dateLimite: _date(j['date_limite']) ?? DateTime.now(),
        nouvellesOuvertes: j['nouvelles_ouvertes'] as bool? ?? false,
        ouvertureNouvelles: _date(j['ouverture_nouvelles']),
        piecesRequises: [
          for (final p in (j['pieces_requises'] as List?) ?? const []) PieceRequise.depuisJson(p as Map<String, dynamic>),
        ],
        consignes: j['consignes'] as String?,
        niveaux: [
          for (final n in (j['niveaux'] as List?) ?? const []) NiveauOffert.depuisJson(n as Map<String, dynamic>),
        ],
      );

  final String campagneId;
  final String etablissementId;
  final String etablissementNom;
  final String? ville;
  final String annee;
  final DateTime dateLimite;
  final bool nouvellesOuvertes;
  final DateTime? ouvertureNouvelles;
  final List<PieceRequise> piecesRequises;
  final String? consignes;
  final List<NiveauOffert> niveaux;
}

/// Résumé d'un dossier existant (dans une réinscription possible).
class ResumeDemande {
  const ResumeDemande({
    required this.id,
    required this.statut,
    this.numeroDossier,
    this.montantARegler = 0,
    this.offreExpireLe,
  });

  factory ResumeDemande.depuisJson(Map<String, dynamic> j) => ResumeDemande(
        id: j['id'] as String,
        statut: StatutDemandeInscription.depuisCode(j['statut'] as String?),
        numeroDossier: j['numero_dossier'] as String?,
        montantARegler: _nombre(j['montant_a_regler']),
        offreExpireLe: _date(j['offre_expire_le']),
      );

  final String id;
  final StatutDemandeInscription statut;
  final String? numeroDossier;
  final double montantARegler;
  final DateTime? offreExpireLe;
}

/// Élève que l'utilisateur peut réinscrire (son enfant, ou lui-même dès le
/// collège).
class ReinscriptionPossible {
  const ReinscriptionPossible({
    required this.ficheEleveId,
    required this.nom,
    required this.prenom,
    required this.etablissementId,
    required this.etablissementNom,
    required this.campagneId,
    required this.annee,
    required this.dateLimite,
    required this.ouverte,
    this.classeActuelle,
    this.niveauProposeId,
    this.niveauProposeNom,
    this.niveauProposeIsced = 0,
    this.niveauOffert = false,
    this.fraisInscription = 0,
    this.soldePrecedent = 0,
    this.qualite = 'parent',
    this.responsableFinancier = 'parent',
    this.piecesRequises = const [],
    this.demande,
  });

  factory ReinscriptionPossible.depuisJson(Map<String, dynamic> j) => ReinscriptionPossible(
        ficheEleveId: j['fiche_eleve_id'] as String,
        nom: j['nom'] as String? ?? '',
        prenom: j['prenom'] as String? ?? '',
        etablissementId: j['etablissement_id'] as String,
        etablissementNom: j['etablissement_nom'] as String? ?? '',
        campagneId: j['campagne_id'] as String,
        annee: j['annee'] as String? ?? '',
        dateLimite: _date(j['date_limite']) ?? DateTime.now(),
        ouverte: j['ouverte'] as bool? ?? false,
        classeActuelle: j['classe_actuelle'] as String?,
        niveauProposeId: j['niveau_propose_id'] as String?,
        niveauProposeNom: j['niveau_propose_nom'] as String?,
        niveauProposeIsced: (j['niveau_propose_isced'] as num?)?.toInt() ?? 0,
        niveauOffert: j['niveau_offert'] as bool? ?? false,
        fraisInscription: _nombre(j['frais_inscription']),
        soldePrecedent: _nombre(j['solde_precedent']),
        qualite: j['qualite'] as String? ?? 'parent',
        responsableFinancier: j['responsable_financier'] as String? ?? 'parent',
        piecesRequises: [
          for (final p in (j['pieces_requises'] as List?) ?? const []) PieceRequise.depuisJson(p as Map<String, dynamic>),
        ],
        demande: j['demande'] is Map<String, dynamic> ? ResumeDemande.depuisJson(j['demande'] as Map<String, dynamic>) : null,
      );

  final String ficheEleveId;
  final String nom;
  final String prenom;
  final String etablissementId;
  final String etablissementNom;
  final String campagneId;
  final String annee;
  final DateTime dateLimite;
  final bool ouverte;
  final String? classeActuelle;
  final String? niveauProposeId;
  final String? niveauProposeNom;

  /// Cycle (CITE) du niveau proposé : dès 2 (collège), l'élève peut payer lui-même.
  final int niveauProposeIsced;
  final bool niveauOffert;
  final double fraisInscription;
  final double soldePrecedent;

  /// `eleve` : l'utilisateur est l'élève lui-même (collège et plus).
  final String qualite;
  final String responsableFinancier;
  final List<PieceRequise> piecesRequises;
  final ResumeDemande? demande;

  String get nomComplet => '$prenom $nom';
  bool get parLEleve => qualite == 'eleve';
}

/// Dossier d'inscription (lecture : demandeur, parents, élève, Direction).
class DemandeInscription {
  const DemandeInscription({
    required this.id,
    required this.etablissementId,
    required this.campagneId,
    required this.type,
    required this.numeroDossier,
    required this.statut,
    required this.nom,
    required this.prenom,
    required this.dateNaissance,
    required this.niveauId,
    this.niveauNom,
    this.etablissementNom,
    this.sexe,
    this.lieuNaissance,
    this.ecolePrecedente,
    this.ficheEleveId,
    this.intention,
    this.demandeurQualite = 'parent',
    this.responsableFinancier = 'parent',
    this.telephone,
    this.commentaire,
    this.alertes = const {},
    this.motif,
    this.rangAttente,
    this.offreExpireLe,
    this.montantARegler = 0,
    this.classeId,
    this.inscriptionId,
    this.numeroProvisoire,
    this.creeLe,
    this.pieces = const {},
    this.enAttenteEnvoi = false,
    this.niveauIsced = 0,
    this.piecesRequises = const [],
    this.devise = 'GNF',
  });

  factory DemandeInscription.depuisJson(Map<String, dynamic> j) => DemandeInscription(
        id: j['id'] as String,
        etablissementId: j['etablissement_id'] as String,
        campagneId: j['campagne_id'] as String,
        type: j['type'] as String? ?? 'nouvelle',
        numeroDossier: j['numero_dossier'] as String? ?? '',
        statut: StatutDemandeInscription.depuisCode(j['statut'] as String?),
        nom: j['nom'] as String? ?? '',
        prenom: j['prenom'] as String? ?? '',
        dateNaissance: _date(j['date_naissance']) ?? DateTime(2000),
        niveauId: j['niveau_id'] as String,
        niveauNom: (j['niveaux_educatifs'] as Map<String, dynamic>?)?['nom'] as String? ?? j['niveau_nom'] as String?,
        etablissementNom:
            (j['etablissements'] as Map<String, dynamic>?)?['nom'] as String? ?? j['etablissement_nom'] as String?,
        sexe: j['sexe'] as String?,
        lieuNaissance: j['lieu_naissance'] as String?,
        ecolePrecedente: j['ecole_precedente'] as String?,
        ficheEleveId: j['fiche_eleve_id'] as String?,
        intention: j['intention'] as String?,
        demandeurQualite: j['demandeur_qualite'] as String? ?? 'parent',
        responsableFinancier: j['responsable_financier'] as String? ?? 'parent',
        telephone: j['telephone_contact'] as String?,
        commentaire: j['commentaire'] as String?,
        alertes: (j['alertes'] as Map<String, dynamic>?) ?? const {},
        motif: j['motif'] as String?,
        rangAttente: (j['rang_attente'] as num?)?.toInt(),
        offreExpireLe: _date(j['offre_expire_le']),
        montantARegler: _nombre(j['montant_a_regler']),
        classeId: j['classe_id'] as String?,
        inscriptionId: j['inscription_id'] as String?,
        numeroProvisoire: j['numero_provisoire'] as String?,
        creeLe: _date(j['created_at']),
        pieces: {
          for (final p in (j['pieces_demandes_inscription'] as List?) ?? const [])
            (p as Map<String, dynamic>)['code'] as String: p['chemin'] as String,
        },
        enAttenteEnvoi: j['en_attente_envoi'] as bool? ?? false,
        niveauIsced: ((j['niveaux_educatifs'] as Map<String, dynamic>?)?['isced'] as num?)?.toInt() ??
            (j['niveau_isced'] as num?)?.toInt() ??
            0,
        piecesRequises: [
          for (final p in ((j['campagnes_inscription'] as Map<String, dynamic>?)?['pieces_requises'] as List?) ??
              (j['pieces_requises'] as List?) ??
              const [])
            PieceRequise.depuisJson(p as Map<String, dynamic>),
        ],
        devise: (j['etablissements'] as Map<String, dynamic>?)?['devise_code'] as String? ?? j['devise'] as String? ?? 'GNF',
      );

  final String id;
  final String etablissementId;
  final String campagneId;

  /// `reinscription` ou `nouvelle`.
  final String type;

  /// Numéro définitif (serveur) ou, en attente d'envoi, le numéro provisoire.
  final String numeroDossier;
  final StatutDemandeInscription statut;
  final String nom;
  final String prenom;
  final DateTime dateNaissance;
  final String niveauId;
  final String? niveauNom;
  final String? etablissementNom;
  final String? sexe;
  final String? lieuNaissance;
  final String? ecolePrecedente;
  final String? ficheEleveId;
  final String? intention;
  final String demandeurQualite;
  final String responsableFinancier;
  final String? telephone;
  final String? commentaire;

  /// Signaux pour la Direction : `impaye` (montant), `sanction_active`,
  /// `doublon_possible`.
  final Map<String, dynamic> alertes;
  final String? motif;
  final int? rangAttente;
  final DateTime? offreExpireLe;
  final double montantARegler;
  final String? classeId;
  final String? inscriptionId;
  final String? numeroProvisoire;
  final DateTime? creeLe;

  /// Pièces déposées : code → chemin dans le stockage.
  final Map<String, String> pieces;

  /// Saisi sur cet appareil, pas encore reçu par l'école.
  final bool enAttenteEnvoi;
  final int niveauIsced;
  final List<PieceRequise> piecesRequises;
  final String devise;

  /// Pièces exigées pour le cycle de l'élève.
  List<PieceRequise> get piecesAttendues => [for (final p in piecesRequises) if (p.concerne(niveauIsced)) p];

  /// Pièces obligatoires encore absentes.
  List<PieceRequise> get piecesManquantes =>
      [for (final p in piecesAttendues) if (p.obligatoire && !pieces.containsKey(p.code)) p];

  String get nomComplet => '$prenom $nom';
  bool get estReinscription => type == 'reinscription';
  bool get aRegler => statut == StatutDemandeInscription.acceptee && montantARegler > 0;
  double? get impaye => alertes['impaye'] is num ? (alertes['impaye'] as num).toDouble() : null;
  bool get sanctionActive => alertes['sanction_active'] == true;
  bool get doublonPossible => alertes['doublon_possible'] == true;

  DemandeInscription avecStatut(StatutDemandeInscription nouveau) => DemandeInscription(
        id: id, etablissementId: etablissementId, campagneId: campagneId, type: type,
        numeroDossier: numeroDossier, statut: nouveau, nom: nom, prenom: prenom,
        dateNaissance: dateNaissance, niveauId: niveauId, niveauNom: niveauNom,
        etablissementNom: etablissementNom, sexe: sexe, lieuNaissance: lieuNaissance,
        ecolePrecedente: ecolePrecedente, ficheEleveId: ficheEleveId, intention: intention,
        demandeurQualite: demandeurQualite, responsableFinancier: responsableFinancier,
        telephone: telephone, commentaire: commentaire, alertes: alertes, motif: motif,
        rangAttente: rangAttente, offreExpireLe: offreExpireLe, montantARegler: montantARegler,
        classeId: classeId, inscriptionId: inscriptionId, numeroProvisoire: numeroProvisoire,
        creeLe: creeLe, pieces: pieces, enAttenteEnvoi: enAttenteEnvoi,
        niveauIsced: niveauIsced, piecesRequises: piecesRequises, devise: devise,
      );
}

/// Ce que la famille saisit (réinscription ou nouvel élève).
class SaisieDemandeInscription {
  const SaisieDemandeInscription({
    required this.campagneId,
    required this.type,
    this.id,
    this.ficheEleveId,
    this.intention = 'revient',
    this.nom,
    this.prenom,
    this.dateNaissance,
    this.sexe,
    this.lieuNaissance,
    this.ecolePrecedente,
    this.niveauId,
    this.demandeurQualite = 'parent',
    this.responsableFinancier = 'parent',
    this.telephone,
    this.commentaire,
    this.numeroProvisoire,
    this.saisiLe,
    this.libelleEcole,
    this.libelleNiveau,
    this.niveauIsced = 0,
    this.piecesRequises = const [],
  });

  final String campagneId;
  final String type;

  /// Clé générée sur l'appareil (idempotence de l'envoi).
  final String? id;
  final String? ficheEleveId;
  final String intention;
  final String? nom;
  final String? prenom;
  final DateTime? dateNaissance;
  final String? sexe;
  final String? lieuNaissance;
  final String? ecolePrecedente;
  final String? niveauId;
  final String demandeurQualite;
  final String responsableFinancier;
  final String? telephone;
  final String? commentaire;
  final String? numeroProvisoire;
  final DateTime? saisiLe;

  /// Pour l'affichage local tant que le dossier attend l'envoi.
  final String? libelleEcole;
  final String? libelleNiveau;
  final int niveauIsced;
  final List<PieceRequise> piecesRequises;

  SaisieDemandeInscription avecCle(String cle, {String? numeroProvisoire, DateTime? saisiLe}) =>
      SaisieDemandeInscription(
        campagneId: campagneId, type: type, id: cle, ficheEleveId: ficheEleveId, intention: intention,
        nom: nom, prenom: prenom, dateNaissance: dateNaissance, sexe: sexe, lieuNaissance: lieuNaissance,
        ecolePrecedente: ecolePrecedente, niveauId: niveauId, demandeurQualite: demandeurQualite,
        responsableFinancier: responsableFinancier, telephone: telephone, commentaire: commentaire,
        numeroProvisoire: numeroProvisoire ?? this.numeroProvisoire, saisiLe: saisiLe ?? this.saisiLe,
        libelleEcole: libelleEcole, libelleNiveau: libelleNiveau,
        niveauIsced: niveauIsced, piecesRequises: piecesRequises,
      );

  /// Paramètres de `soumettre_demande_inscription`.
  Map<String, dynamic> versParams() => {
        'p_id': id,
        'p_campagne': campagneId,
        'p_donnees': {
          'type': type,
          if (ficheEleveId != null) 'fiche_eleve_id': ficheEleveId,
          if (type == 'reinscription') 'intention': intention,
          if (nom != null) 'nom': nom,
          if (prenom != null) 'prenom': prenom,
          if (dateNaissance != null) 'date_naissance': _iso(dateNaissance!),
          if (sexe != null) 'sexe': sexe,
          if (lieuNaissance != null) 'lieu_naissance': lieuNaissance,
          if (ecolePrecedente != null) 'ecole_precedente': ecolePrecedente,
          if (niveauId != null) 'niveau_id': niveauId,
          'demandeur_qualite': demandeurQualite,
          'responsable_financier': responsableFinancier,
          if (telephone != null) 'telephone': telephone,
          if (commentaire != null) 'commentaire': commentaire,
        },
        'p_numero_provisoire': numeroProvisoire,
        'p_saisi_le': (saisiLe ?? DateTime.now()).toUtc().toIso8601String(),
      };
}

/// Réponse du serveur (ou de l'appareil, hors connexion).
class ResultatDemandeInscription {
  const ResultatDemandeInscription({
    required this.id,
    required this.numeroDossier,
    required this.statut,
    this.montantARegler = 0,
    this.offreExpireLe,
    this.dejaRecue = false,
    this.enAttenteEnvoi = false,
  });

  factory ResultatDemandeInscription.depuisJson(Map<String, dynamic> j) => ResultatDemandeInscription(
        id: j['id'] as String,
        numeroDossier: j['numero_dossier'] as String? ?? '',
        statut: StatutDemandeInscription.depuisCode(j['statut'] as String?),
        montantARegler: _nombre(j['montant_a_regler']),
        offreExpireLe: _date(j['offre_expire_le']),
        dejaRecue: j['deja_recue'] as bool? ?? false,
      );

  final String id;
  final String numeroDossier;
  final StatutDemandeInscription statut;
  final double montantARegler;
  final DateTime? offreExpireLe;
  final bool dejaRecue;

  /// Gardée sur l'appareil, envoyée au retour du réseau.
  final bool enAttenteEnvoi;
}

/// Pièce photographiée par la famille.
class PieceAEnvoyer {
  const PieceAEnvoyer({required this.code, required this.octets, this.extension = 'jpg'});

  final String code;
  final Uint8List octets;
  final String extension;

  String get typeMime => switch (extension) {
        'png' => 'image/png',
        'pdf' => 'application/pdf',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}

/// Paramétrage d'une campagne par la Direction.
class CampagneInscription {
  const CampagneInscription({
    this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.ouvertureReinscriptions,
    required this.ouvertureNouvelles,
    required this.dateLimite,
    this.delaiReservationJours = 7,
    this.piecesRequises = const [],
    this.places = const {},
    this.consignes,
    this.publiee = false,
  });

  factory CampagneInscription.depuisJson(Map<String, dynamic> j) => CampagneInscription(
        id: j['id'] as String?,
        etablissementId: j['etablissement_id'] as String,
        anneeScolaireId: j['annee_scolaire_id'] as String,
        ouvertureReinscriptions: _date(j['ouverture_reinscriptions']) ?? DateTime.now(),
        ouvertureNouvelles: _date(j['ouverture_nouvelles']) ?? DateTime.now(),
        dateLimite: _date(j['date_limite']) ?? DateTime.now(),
        delaiReservationJours: (j['delai_reservation_jours'] as num?)?.toInt() ?? 7,
        piecesRequises: [
          for (final p in (j['pieces_requises'] as List?) ?? const []) PieceRequise.depuisJson(p as Map<String, dynamic>),
        ],
        places: {
          for (final p in (j['places_inscription'] as List?) ?? const [])
            (p as Map<String, dynamic>)['niveau_id'] as String: (p['places'] as num).toInt(),
        },
        consignes: j['consignes'] as String?,
        publiee: j['publiee'] as bool? ?? false,
      );

  final String? id;
  final String etablissementId;
  final String anneeScolaireId;
  final DateTime ouvertureReinscriptions;
  final DateTime ouvertureNouvelles;
  final DateTime dateLimite;
  final int delaiReservationJours;
  final List<PieceRequise> piecesRequises;

  /// Places par niveau ; un niveau absent suit la capacité de ses classes.
  final Map<String, int> places;
  final String? consignes;
  final bool publiee;

  Map<String, dynamic> versParams() => {
        'p_etablissement': etablissementId,
        'p_annee_scolaire': anneeScolaireId,
        'p_ouverture_reinscriptions': _iso(ouvertureReinscriptions),
        'p_ouverture_nouvelles': _iso(ouvertureNouvelles),
        'p_date_limite': _iso(dateLimite),
        'p_delai_reservation_jours': delaiReservationJours,
        'p_pieces_requises': [for (final p in piecesRequises) p.versJson()],
        'p_places': places,
        'p_consignes': consignes,
        'p_publiee': publiee,
      };
}

/// Tableau de bord de la campagne (Direction).
class TableauCampagne {
  const TableauCampagne({
    this.elevesEligibles = 0,
    this.reinscrits = 0,
    this.desistements = 0,
    this.parStatut = const {},
    this.fraisEncaisses = 0,
    this.niveaux = const [],
  });

  factory TableauCampagne.depuisJson(Map<String, dynamic> j) => TableauCampagne(
        elevesEligibles: (j['eleves_eligibles'] as num?)?.toInt() ?? 0,
        reinscrits: (j['reinscrits'] as num?)?.toInt() ?? 0,
        desistements: (j['desistements'] as num?)?.toInt() ?? 0,
        parStatut: {
          for (final e in ((j['par_statut'] as Map<String, dynamic>?) ?? const {}).entries)
            StatutDemandeInscription.depuisCode(e.key): (e.value as num).toInt(),
        },
        fraisEncaisses: _nombre(j['frais_encaisses']),
        niveaux: [
          for (final n in (j['niveaux'] as List?) ?? const [])
            (
              niveauId: (n as Map<String, dynamic>)['niveau_id'] as String,
              nom: n['nom'] as String? ?? '',
              placesRestantes: (n['places_restantes'] as num?)?.toInt(),
              enAttente: (n['en_attente'] as num?)?.toInt() ?? 0,
            ),
        ],
      );

  final int elevesEligibles;
  final int reinscrits;
  final int desistements;
  final Map<StatutDemandeInscription, int> parStatut;
  final double fraisEncaisses;
  final List<({String niveauId, String nom, int? placesRestantes, int enAttente})> niveaux;

  /// Part des élèves de l'an dernier déjà réinscrits (0 à 1).
  double get tauxReinscription => elevesEligibles == 0 ? 0 : reinscrits / elevesEligibles;
  int nombre(StatutDemandeInscription s) => parStatut[s] ?? 0;
}

/// Décision de la Direction sur un dossier.
enum DecisionDossier {
  accepter('accepter', 'Accepter'),
  refuser('refuser', 'Refuser'),
  incomplete('incomplete', 'Réclamer des pièces'),
  convoquer('convoquer', 'Convoquer'),
  listeAttente('liste_attente', "Mettre en liste d'attente");

  const DecisionDossier(this.code, this.libelle);

  final String code;
  final String libelle;

  bool get motifObligatoire => this == refuser || this == incomplete || this == convoquer;
}

/// Port des inscriptions en ligne.
abstract interface class InscriptionEnLigneRepository {
  // Familles
  Future<List<ReinscriptionPossible>> reinscriptionsPossibles();
  Future<List<CampagneOuverte>> campagnesOuvertes({String? recherche});
  Future<ResultatDemandeInscription> soumettre(SaisieDemandeInscription saisie);
  Future<void> deposerPiece(String demandeId, PieceAEnvoyer piece);
  Future<List<DemandeInscription>> mesDemandes();
  Future<void> retirer(String demandeId);

  // Direction
  Future<CampagneInscription?> campagne(String etablissementId, String anneeScolaireId);
  /// `null` : enregistrée sur l'appareil, envoyée au retour du réseau.
  Future<String?> enregistrerCampagne(CampagneInscription campagne);
  Future<List<DemandeInscription>> dossiers(String campagneId);
  Future<TableauCampagne> tableau(String campagneId);
  /// `null` : décision gardée sur l'appareil, appliquée au retour du réseau.
  Future<StatutDemandeInscription?> traiter(
    String demandeId,
    DecisionDossier decision, {
    String? motif,
    String? niveauId,
    bool forcer = false,
  });
  /// Paiement reçu au guichet. `null` : gardé sur l'appareil (espèces
  /// encaissées sans réseau), l'inscription est créée au retour du réseau.
  Future<String?> finaliserAuGuichet(String demandeId, {String? classeId, double? montant, String moyen = 'especes'});
  Future<Uri> lienPiece(String chemin);

  /// Noms des niveaux du référentiel (paramétrage des places).
  Future<Map<String, String>> nomsNiveaux(List<String> niveauIds);
}

/// Erreur métier, traduite pour l'écran.
class ErreurInscriptionEnLigne implements Exception {
  const ErreurInscriptionEnLigne(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'HORS_CONNEXION' => 'Pas de réseau pour le moment.',
        'RESEAU_REQUIS' => 'Cette action demande le réseau. Réessayez une fois connecté.',
        'CAMPAGNE_FERMEE' => "Les inscriptions de cette école ne sont pas ouvertes.",
        'CAMPAGNE_TERMINEE' => 'La date limite des inscriptions est dépassée.',
        'REINSCRIPTIONS_PAS_ENCORE_OUVERTES' => 'Les réinscriptions ne sont pas encore ouvertes.',
        'NOUVELLES_DEMANDES_PAS_ENCORE_OUVERTES' => "Les demandes des nouveaux élèves ne sont pas encore ouvertes.",
        'NIVEAU_NON_OUVERT' => "Ce niveau n'est pas ouvert par l'école pour l'année prochaine.",
        'PARENT_REQUIS_AVANT_COLLEGE' => "Avant le collège, c'est un parent qui fait la demande et qui paie.",
        'ACCES_REFUSE' || 'PERMISSION_REFUSEE' => "Vous n'êtes pas autorisé à faire cette opération.",
        'DEJA_INSCRIT' => "L'élève est déjà inscrit pour l'année prochaine.",
        'IDENTITE_INCOMPLETE' => "Renseignez le nom, le prénom et la date de naissance de l'élève.",
        'ELEVE_INTROUVABLE' || 'AUCUNE_INSCRIPTION_PRECEDENTE' => "Élève introuvable dans cette école.",
        'CLE_DEJA_UTILISEE' => 'Ce dossier existe déjà sous un autre compte.',
        'DEMANDE_CLOSE' => 'Ce dossier est clos.',
        'MOTIF_OBLIGATOIRE' => 'Indiquez le motif : la famille le verra.',
        'AUCUNE_CLASSE_POUR_CE_NIVEAU' => "Créez d'abord une classe de ce niveau pour l'année prochaine.",
        'CLASSE_INVALIDE' => 'Classe invalide pour ce dossier.',
        'ANNEE_INVALIDE' => "Choisissez une année scolaire de l'établissement, non clôturée.",
        'PIECES_INVALIDES' => 'Chaque pièce exigée doit avoir un nom.',
        'FICHIER_TROP_LOURD' => 'Le fichier dépasse 5 Mo. Reprenez la photo un peu plus loin.',
        _ => 'Opération impossible pour le moment. Réessayez.',
      };

  @override
  String toString() => 'ErreurInscriptionEnLigne($code)';
}
