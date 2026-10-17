/// Registre des donateurs et des dons (REG-03, lot C5).
///
/// Le serveur numérote les reçus, comptabilise et refuse toute
/// modification d'un don validé (migration `20260906001540`,
/// tests/rls/68) ; le client saisit, consulte et imprime.
library;

enum NatureDon {
  don('don', 'Don'),
  legs('legs', 'Legs'),
  denierCulte('denier_culte', 'Denier du culte'),
  quete('quete', 'Quête'),
  mecenat('mecenat', 'Mécénat'),
  parrainage('parrainage', 'Parrainage'),
  autre('autre', 'Autre');

  const NatureDon(this.code, this.libelle);

  final String code;
  final String libelle;

  static NatureDon depuisCode(String? code) =>
      NatureDon.values.firstWhere((n) => n.code == code, orElse: () => NatureDon.autre);
}

enum MoyenDon {
  especes('especes', 'Espèces'),
  mobileMoney('mobile_money', 'Orange Money'),
  virement('virement', 'Virement'),
  cheque('cheque', 'Chèque'),
  autre('autre', 'Autre');

  const MoyenDon(this.code, this.libelle);

  final String code;
  final String libelle;

  static MoyenDon depuisCode(String? code) =>
      MoyenDon.values.firstWhere((m) => m.code == code, orElse: () => MoyenDon.autre);
}

enum TypeDonateur {
  personne('personne', 'Personne'),
  organisation('organisation', 'Organisation'),
  eglise('eglise', 'Église ou paroisse');

  const TypeDonateur(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypeDonateur depuisCode(String? code) =>
      TypeDonateur.values.firstWhere((t) => t.code == code, orElse: () => TypeDonateur.personne);
}

enum TypeAffectation {
  libre('libre', 'Campagne libre', 'Les dons vont aux ressources de l\'école.'),
  projet('projet', 'Projet à fonds affectés',
      'Les dons sont réservés au projet : ils ne deviennent des ressources qu\'au fur et à mesure de leur emploi.'),
  parrainage('parrainage', 'Parrainage d\'élèves', 'Parrains et marraines qui soutiennent la scolarité d\'élèves.');

  const TypeAffectation(this.code, this.libelle, this.aide);

  final String code;
  final String libelle;
  final String aide;

  static TypeAffectation depuisCode(String? code) =>
      TypeAffectation.values.firstWhere((t) => t.code == code, orElse: () => TypeAffectation.libre);
}

double _montant(Object? v) => (v as num?)?.toDouble() ?? 0;
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

class Donateur {
  const Donateur({
    this.id,
    required this.etablissementId,
    this.type = TypeDonateur.personne,
    required this.nom,
    this.prenom,
    this.telephone,
    this.email,
    this.adresse,
    this.accepteContact = true,
    this.notes,
  });

  factory Donateur.depuisJson(Map<String, dynamic> json) => Donateur(
        id: json['id'] as String?,
        etablissementId: json['etablissement_id'] as String,
        type: TypeDonateur.depuisCode(json['type'] as String?),
        nom: json['nom'] as String,
        prenom: json['prenom'] as String?,
        telephone: json['telephone'] as String?,
        email: json['email'] as String?,
        adresse: json['adresse'] as String?,
        accepteContact: json['accepte_contact'] as bool? ?? true,
        notes: json['notes'] as String?,
      );

  final String? id;
  final String etablissementId;
  final TypeDonateur type;
  final String nom;
  final String? prenom;
  final String? telephone;
  final String? email;
  final String? adresse;
  final bool accepteContact;
  final String? notes;

  String get nomComplet => [nom, if (prenom != null && prenom!.trim().isNotEmpty) prenom].join(' ');

  Map<String, dynamic> versJson() => {
        'etablissement_id': etablissementId,
        'type': type.code,
        'nom': nom.trim(),
        'prenom': _vide(prenom),
        'telephone': _vide(telephone),
        'email': _vide(email),
        'adresse': _vide(adresse),
        'accepte_contact': accepteContact,
        'notes': _vide(notes),
      };

  static String? _vide(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
}

class AffectationDon {
  const AffectationDon({
    this.id,
    required this.etablissementId,
    required this.libelle,
    this.type = TypeAffectation.libre,
    this.description,
    this.objectif,
    this.dateFin,
    this.active = true,
  });

  factory AffectationDon.depuisJson(Map<String, dynamic> json) => AffectationDon(
        id: json['id'] as String?,
        etablissementId: json['etablissement_id'] as String,
        libelle: json['libelle'] as String,
        type: TypeAffectation.depuisCode(json['type'] as String?),
        description: json['description'] as String?,
        objectif: (json['objectif'] as num?)?.toDouble(),
        dateFin: _date(json['date_fin']),
        active: json['active'] as bool? ?? true,
      );

  final String? id;
  final String etablissementId;
  final String libelle;
  final TypeAffectation type;
  final String? description;
  final double? objectif;
  final DateTime? dateFin;
  final bool active;

  Map<String, dynamic> versJson() => {
        'etablissement_id': etablissementId,
        'libelle': libelle.trim(),
        'type': type.code,
        'description': description == null || description!.trim().isEmpty ? null : description!.trim(),
        'objectif': objectif,
        'date_fin': dateFin == null ? null : _iso(dateFin!),
        'active': active,
      };
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Une ligne de la liste des dons.
class Don {
  const Don({
    required this.id,
    required this.numeroRecu,
    required this.dateDon,
    required this.montant,
    required this.nature,
    required this.moyen,
    this.donateurId,
    this.donateurNom,
    this.affectation,
    this.anonyme = false,
    this.annule = false,
    this.motifAnnulation,
  });

  factory Don.depuisJson(Map<String, dynamic> json) {
    final d = json['donateurs'] as Map<String, dynamic>?;
    final a = json['affectations_dons'] as Map<String, dynamic>?;
    return Don(
      id: json['id'] as String,
      numeroRecu: json['numero_recu'] as String,
      dateDon: DateTime.parse(json['date_don'] as String),
      montant: _montant(json['montant']),
      nature: NatureDon.depuisCode(json['nature'] as String?),
      moyen: MoyenDon.depuisCode(json['moyen_paiement'] as String?),
      donateurId: json['donateur_id'] as String?,
      donateurNom: d == null ? null : [d['nom'], d['prenom']].whereType<String>().join(' '),
      affectation: a?['libelle'] as String?,
      anonyme: json['anonyme'] as bool? ?? false,
      annule: json['statut'] == 'annule',
      motifAnnulation: json['motif_annulation'] as String?,
    );
  }

  final String id;
  final String numeroRecu;
  final DateTime dateDon;
  final double montant;
  final NatureDon nature;
  final MoyenDon moyen;
  final String? donateurId;
  final String? donateurNom;
  final String? affectation;
  final bool anonyme;
  final bool annule;
  final String? motifAnnulation;

  String get donateurAffiche =>
      donateurNom ?? (nature == NatureDon.quete ? 'Quête' : 'Donateur anonyme');
}

class SaisieDon {
  const SaisieDon({
    required this.etablissementId,
    required this.montant,
    this.nature = NatureDon.don,
    this.moyen = MoyenDon.especes,
    required this.date,
    this.donateurId,
    this.affectationId,
    this.ficheEleveId,
    this.reference,
    this.commentaire,
    this.anonyme = false,
  });

  final String etablissementId;
  final double montant;
  final NatureDon nature;
  final MoyenDon moyen;
  final DateTime date;
  final String? donateurId;
  final String? affectationId;
  final String? ficheEleveId;
  final String? reference;
  final String? commentaire;
  final bool anonyme;

  Map<String, dynamic> versParams() => {
        'p_etablissement': etablissementId,
        'p_montant': montant,
        'p_nature': nature.code,
        'p_moyen': moyen.code,
        'p_date': _iso(date),
        'p_donateur_id': donateurId,
        'p_affectation_id': affectationId,
        'p_fiche_eleve_id': ficheEleveId,
        'p_reference': reference,
        'p_commentaire': commentaire,
        'p_anonyme': anonyme,
      };
}

class ResultatDon {
  const ResultatDon({required this.id, required this.numeroRecu, required this.comptabilise, this.incident});

  factory ResultatDon.depuisJson(Map<String, dynamic> json) => ResultatDon(
        id: json['id'] as String,
        numeroRecu: json['numero_recu'] as String,
        comptabilise: json['comptabilise'] as bool? ?? false,
        incident: json['incident'] as String?,
      );

  final String id;
  final String numeroRecu;
  final bool comptabilise;

  /// Code d'incident comptable (le don reste enregistré).
  final String? incident;
}

/// Contenu d'un reçu de don (PDF).
class RecuDon {
  const RecuDon({
    required this.numeroRecu,
    required this.dateDon,
    required this.montant,
    required this.nature,
    required this.moyen,
    this.reference,
    this.affectation,
    this.eleve,
    this.donateurNom,
    this.donateurAdresse,
    this.anonyme = false,
    this.annule = false,
    this.motifAnnulation,
    this.saisiPar,
  });

  factory RecuDon.depuisJson(Map<String, dynamic> json) {
    final d = json['donateur'] as Map<String, dynamic>?;
    return RecuDon(
      numeroRecu: json['numero_recu'] as String,
      dateDon: DateTime.parse(json['date_don'] as String),
      montant: _montant(json['montant']),
      nature: NatureDon.depuisCode(json['nature'] as String?),
      moyen: MoyenDon.depuisCode(json['moyen_paiement'] as String?),
      reference: json['reference_paiement'] as String?,
      affectation: json['affectation'] as String?,
      eleve: json['eleve'] as String?,
      donateurNom: d == null ? null : [d['nom'], d['prenom']].whereType<String>().join(' '),
      donateurAdresse: d?['adresse'] as String?,
      anonyme: json['anonyme'] as bool? ?? false,
      annule: json['statut'] == 'annule',
      motifAnnulation: json['motif_annulation'] as String?,
      saisiPar: json['saisi_par'] as String?,
    );
  }

  final String numeroRecu;
  final DateTime dateDon;
  final double montant;
  final NatureDon nature;
  final MoyenDon moyen;
  final String? reference;
  final String? affectation;
  final String? eleve;
  final String? donateurNom;
  final String? donateurAdresse;
  final bool anonyme;
  final bool annule;
  final String? motifAnnulation;
  final String? saisiPar;
}

class ReleveDonateur {
  const ReleveDonateur({required this.donateurNom, this.adresse, required this.annee, required this.total, required this.dons});

  factory ReleveDonateur.depuisJson(Map<String, dynamic> json) {
    final d = json['donateur'] as Map<String, dynamic>;
    return ReleveDonateur(
      donateurNom: [d['nom'], d['prenom']].whereType<String>().join(' '),
      adresse: d['adresse'] as String?,
      annee: (json['annee'] as num).toInt(),
      total: _montant(json['total']),
      dons: [
        for (final l in (json['dons'] as List<dynamic>? ?? const []))
          (
            numeroRecu: (l as Map<String, dynamic>)['numero_recu'] as String,
            date: DateTime.parse(l['date_don'] as String),
            montant: _montant(l['montant']),
            nature: NatureDon.depuisCode(l['nature'] as String?),
            affectation: l['affectation'] as String?,
          ),
      ],
    );
  }

  final String donateurNom;
  final String? adresse;
  final int annee;
  final double total;
  final List<({String numeroRecu, DateTime date, double montant, NatureDon nature, String? affectation})> dons;
}

class SuiviAffectation {
  const SuiviAffectation({
    required this.id,
    required this.libelle,
    required this.type,
    required this.active,
    this.objectif,
    required this.collecte,
    required this.collecteAnnee,
    required this.emploie,
    required this.disponible,
    required this.donateurs,
  });

  factory SuiviAffectation.depuisJson(Map<String, dynamic> json) => SuiviAffectation(
        id: json['id'] as String,
        libelle: json['libelle'] as String,
        type: TypeAffectation.depuisCode(json['type'] as String?),
        active: json['active'] as bool? ?? true,
        objectif: (json['objectif'] as num?)?.toDouble(),
        collecte: _montant(json['collecte']),
        collecteAnnee: _montant(json['collecte_annee']),
        emploie: _montant(json['emploie']),
        disponible: _montant(json['disponible']),
        donateurs: (json['donateurs'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String libelle;
  final TypeAffectation type;
  final bool active;
  final double? objectif;
  final double collecte;
  final double collecteAnnee;
  final double emploie;
  final double disponible;
  final int donateurs;

  /// Progression vers l'objectif, entre 0 et 1 (null sans objectif).
  double? get progression => objectif == null || objectif == 0 ? null : (collecte / objectif!).clamp(0, 1).toDouble();
}

class EngagementSuivi {
  const EngagementSuivi({
    required this.id,
    required this.donateur,
    this.affectation,
    this.eleve,
    required this.montant,
    required this.periodicite,
    required this.attendu,
    required this.recu,
    required this.retard,
  });

  factory EngagementSuivi.depuisJson(Map<String, dynamic> json) => EngagementSuivi(
        id: json['id'] as String,
        donateur: json['donateur'] as String,
        affectation: json['affectation'] as String?,
        eleve: json['eleve'] as String?,
        montant: _montant(json['montant']),
        periodicite: json['periodicite'] as String,
        attendu: _montant(json['attendu']),
        recu: _montant(json['recu']),
        retard: _montant(json['retard']),
      );

  final String id;
  final String donateur;
  final String? affectation;
  final String? eleve;
  final double montant;
  final String periodicite;
  final double attendu;
  final double recu;
  final double retard;

  String get periodiciteLibelle => switch (periodicite) {
        'mensuelle' => 'par mois',
        'trimestrielle' => 'par trimestre',
        _ => 'par an',
      };
}

class TableauBordDons {
  const TableauBordDons({
    required this.annee,
    required this.total,
    required this.totalAnneePrecedente,
    required this.nombreDons,
    required this.nombreDonateurs,
    required this.nouveauxDonateurs,
    required this.donateursFideles,
    this.parNature = const [],
    this.affectations = const [],
    this.meilleursDonateurs = const [],
    this.aRelancer = const [],
    this.engagements = const [],
  });

  factory TableauBordDons.depuisJson(Map<String, dynamic> json) => TableauBordDons(
        annee: (json['annee'] as num).toInt(),
        total: _montant(json['total']),
        totalAnneePrecedente: _montant(json['total_annee_precedente']),
        nombreDons: (json['nombre_dons'] as num?)?.toInt() ?? 0,
        nombreDonateurs: (json['nombre_donateurs'] as num?)?.toInt() ?? 0,
        nouveauxDonateurs: (json['nouveaux_donateurs'] as num?)?.toInt() ?? 0,
        donateursFideles: (json['donateurs_fideles'] as num?)?.toInt() ?? 0,
        parNature: [
          for (final n in (json['par_nature'] as List<dynamic>? ?? const []))
            (
              nature: NatureDon.depuisCode((n as Map<String, dynamic>)['nature'] as String?),
              montant: _montant(n['montant']),
              nombre: (n['nombre'] as num?)?.toInt() ?? 0,
            ),
        ],
        affectations: [
          for (final a in (json['affectations'] as List<dynamic>? ?? const []))
            SuiviAffectation.depuisJson(a as Map<String, dynamic>),
        ],
        meilleursDonateurs: [
          for (final m in (json['meilleurs_donateurs'] as List<dynamic>? ?? const []))
            (nom: (m as Map<String, dynamic>)['nom'] as String, montant: _montant(m['montant'])),
        ],
        aRelancer: [
          for (final r in (json['a_relancer'] as List<dynamic>? ?? const []))
            (
              nom: (r as Map<String, dynamic>)['nom'] as String,
              telephone: r['telephone'] as String?,
              montantAnneePrecedente: _montant(r['montant_annee_precedente']),
            ),
        ],
        engagements: [
          for (final e in (json['engagements'] as List<dynamic>? ?? const []))
            EngagementSuivi.depuisJson(e as Map<String, dynamic>),
        ],
      );

  final int annee;
  final double total;
  final double totalAnneePrecedente;
  final int nombreDons;
  final int nombreDonateurs;
  final int nouveauxDonateurs;
  final int donateursFideles;
  final List<({NatureDon nature, double montant, int nombre})> parNature;
  final List<SuiviAffectation> affectations;
  final List<({String nom, double montant})> meilleursDonateurs;
  final List<({String nom, String? telephone, double montantAnneePrecedente})> aRelancer;
  final List<EngagementSuivi> engagements;

  /// Évolution par rapport à l'année précédente (null si rien l'an dernier).
  double? get evolution => totalAnneePrecedente == 0 ? null : (total - totalAnneePrecedente) / totalAnneePrecedente;

  List<EngagementSuivi> get engagementsEnRetard => [for (final e in engagements) if (e.retard > 0) e];
}

class ErreurDons implements Exception {
  const ErreurDons(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'COMPTABLE_ECRITURE_REQUIS' || 'COMPTABLE_REQUIS' => 'Vous n\'avez pas les droits de comptabilité.',
        'MONTANT_INVALIDE' => 'Indiquez un montant supérieur à zéro.',
        'DATE_DON_FUTURE' || 'DATE_FUTURE' => 'La date ne peut pas être dans le futur.',
        'AFFECTATION_CLOSE' => 'Cette campagne est close : rouvrez-la ou choisissez-en une autre.',
        'FONDS_INSUFFISANTS' => 'Montant supérieur aux fonds encore disponibles pour ce projet.',
        'MOTIF_REQUIS' => 'Indiquez le motif (3 caractères au moins).',
        'LIBELLE_REQUIS' => 'Décrivez l\'emploi des fonds (3 caractères au moins).',
        'DON_DEJA_ANNULE' => 'Ce don est déjà annulé.',
        'DONATEUR_A_DES_DONS' => 'Ce donateur a déjà donné : il peut être archivé, pas supprimé.',
        'AFFECTATION_UTILISEE' => 'Cette campagne a reçu des dons : son type ne peut plus changer.',
        _ => 'Opération impossible pour le moment. Réessayez dans un instant.',
      };

  @override
  String toString() => 'ErreurDons($code)';
}

abstract interface class DonsRepository {
  Future<TableauBordDons> tableauBord(String etablissementId, int annee);
  Future<List<Don>> dons(String etablissementId, int annee);
  Future<List<Donateur>> donateurs(String etablissementId);
  Future<List<AffectationDon>> affectations(String etablissementId);

  /// Création si [Donateur.id] est null, sinon mise à jour.
  Future<String> enregistrerDonateur(Donateur donateur);
  Future<void> archiverDonateur(String donateurId);
  Future<String> enregistrerAffectation(AffectationDon affectation);
  Future<void> enregistrerEngagement({
    required String etablissementId,
    required String donateurId,
    String? affectationId,
    required double montant,
    required String periodicite,
    required DateTime dateDebut,
  });

  Future<ResultatDon> enregistrerDon(SaisieDon saisie);
  Future<void> annulerDon(String donId, String motif);
  Future<RecuDon> recu(String donId);
  Future<ReleveDonateur> releve(String donateurId, int annee);

  /// Renvoie le solde encore disponible pour le projet.
  Future<double> constaterEmploi({
    required String affectationId,
    required double montant,
    required String libelle,
    required DateTime date,
  });
}
