/// Pointage des élèves au portail, alertes aux familles, crédits SMS et
/// relances d'impayés (REG-09).
///
/// Décisions du porteur de projet : pas de GPS ; carte à QR code scannée au
/// portail, hors connexion d'abord ; avis en push (gratuits) ; SMS payés
/// sur les crédits que l'établissement achète à GSG ; l'appel en classe
/// reste la preuve officielle.

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
double _nombre(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// Préfixe des QR codes des cartes EcoShop.
const prefixeQrCarte = 'ECO1.';

/// Jeton lu dans un QR code ou tapé par une douchette (préfixe retiré).
String jetonDepuisLecture(String lu) {
  final propre = lu.trim();
  return propre.startsWith(prefixeQrCarte) ? propre.substring(prefixeQrCarte.length) : propre;
}

enum SensPointage {
  arrivee('arrivee', 'Arrivée'),
  sortie('sortie', 'Sortie');

  const SensPointage(this.code, this.libelle);

  final String code;
  final String libelle;
}

/// Carte valide connue du téléphone du portail.
class CartePortail {
  const CartePortail({
    required this.jeton,
    required this.ficheEleveId,
    required this.nom,
    required this.prenom,
    this.classe,
    this.matricule,
    this.dateNaissance,
    this.version = 1,
  });

  factory CartePortail.depuisJson(Map<String, dynamic> j) => CartePortail(
        jeton: j['jeton'] as String,
        ficheEleveId: j['fiche_eleve_id'] as String,
        nom: j['nom'] as String? ?? '',
        prenom: j['prenom'] as String? ?? '',
        classe: j['classe'] as String?,
        matricule: j['matricule'] as String?,
        dateNaissance: _date(j['date_naissance']),
        version: (j['version'] as num?)?.toInt() ?? 1,
      );

  final String jeton;
  final String ficheEleveId;
  final String nom;
  final String prenom;
  final String? classe;
  final String? matricule;
  final DateTime? dateNaissance;
  final int version;

  String get nomComplet => '$prenom $nom';

  /// Contenu imprimé dans le QR code.
  String get contenuQr => '$prefixeQrCarte$jeton';
}

/// Réglages du pointage d'un établissement.
class ParametresPointage {
  const ParametresPointage({
    this.actif = false,
    this.heureLimiteArrivee = '08:15',
    this.heureFinCours = '15:00',
    this.joursClasse = const [1, 2, 3, 4, 5],
    this.notifierArriveeSortie = true,
    this.smsAbsence = true,
    this.smsSortieAnticipee = true,
  });

  factory ParametresPointage.depuisJson(Map<String, dynamic>? j) => j == null
      ? const ParametresPointage()
      : ParametresPointage(
          actif: j['actif'] as bool? ?? false,
          heureLimiteArrivee: _hm(j['heure_limite_arrivee']) ?? '08:15',
          heureFinCours: _hm(j['heure_fin_cours']) ?? '15:00',
          joursClasse: [for (final x in (j['jours_classe'] as List?) ?? const [1, 2, 3, 4, 5]) (x as num).toInt()],
          notifierArriveeSortie: j['notifier_arrivee_sortie'] as bool? ?? true,
          smsAbsence: j['sms_absence'] as bool? ?? true,
          smsSortieAnticipee: j['sms_sortie_anticipee'] as bool? ?? true,
        );

  static String? _hm(Object? v) => v is String && v.length >= 5 ? v.substring(0, 5) : null;

  final bool actif;

  /// « HH:MM ».
  final String heureLimiteArrivee;
  final String heureFinCours;

  /// 1 = lundi … 7 = dimanche.
  final List<int> joursClasse;
  final bool notifierArriveeSortie;
  final bool smsAbsence;
  final bool smsSortieAnticipee;

  /// Minutes depuis minuit de l'heure limite (choix automatique du sens).
  int get minutesFinCours {
    final p = heureFinCours.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  Map<String, dynamic> versParams(String etablissementId) => {
        'p_etablissement': etablissementId,
        'p_actif': actif,
        'p_heure_limite_arrivee': heureLimiteArrivee,
        'p_heure_fin_cours': heureFinCours,
        'p_jours_classe': joursClasse,
        'p_notifier_arrivee_sortie': notifierArriveeSortie,
        'p_sms_absence': smsAbsence,
        'p_sms_sortie_anticipee': smsSortieAnticipee,
      };

  ParametresPointage copier({
    bool? actif,
    String? heureLimiteArrivee,
    String? heureFinCours,
    List<int>? joursClasse,
    bool? notifierArriveeSortie,
    bool? smsAbsence,
    bool? smsSortieAnticipee,
  }) =>
      ParametresPointage(
        actif: actif ?? this.actif,
        heureLimiteArrivee: heureLimiteArrivee ?? this.heureLimiteArrivee,
        heureFinCours: heureFinCours ?? this.heureFinCours,
        joursClasse: joursClasse ?? this.joursClasse,
        notifierArriveeSortie: notifierArriveeSortie ?? this.notifierArriveeSortie,
        smsAbsence: smsAbsence ?? this.smsAbsence,
        smsSortieAnticipee: smsSortieAnticipee ?? this.smsSortieAnticipee,
      );
}

/// Ce que le téléphone du portail sait pour travailler sans réseau.
class DonneesPortail {
  const DonneesPortail({required this.cartes, this.parametres = const ParametresPointage()});

  factory DonneesPortail.depuisJson(Map<String, dynamic> j) => DonneesPortail(
        cartes: [for (final c in (j['cartes'] as List?) ?? const []) CartePortail.depuisJson(c as Map<String, dynamic>)],
        parametres: ParametresPointage.depuisJson(j['parametres'] as Map<String, dynamic>?),
      );

  final List<CartePortail> cartes;
  final ParametresPointage parametres;

  CartePortail? carte(String jeton) {
    for (final c in cartes) {
      if (c.jeton == jeton) return c;
    }
    return null;
  }
}

enum StatutScan { enregistre, enAttenteEnvoi, doublon, carteInconnue }

/// Réponse affichée en grand au portail.
class ResultatScan {
  const ResultatScan({
    required this.statut,
    required this.sens,
    required this.heure,
    this.carte,
    this.nom,
    this.prenom,
    this.classe,
    this.enRetard = false,
  });

  final StatutScan statut;
  final SensPointage sens;
  final DateTime heure;
  final CartePortail? carte;
  final String? nom;
  final String? prenom;
  final String? classe;
  final bool enRetard;

  String get nomAffiche => [prenom ?? carte?.prenom, nom ?? carte?.nom].whereType<String>().join(' ');
  bool get accepte => statut == StatutScan.enregistre || statut == StatutScan.enAttenteEnvoi;
}

/// Ligne du tableau de présence du jour.
class EleveDuJour {
  const EleveDuJour({
    required this.ficheEleveId,
    required this.nom,
    required this.prenom,
    this.classe,
    this.matricule,
    this.arrivee,
    this.enRetard = false,
    this.sortie,
    this.absentAppel = false,
    this.justifie = false,
    this.sortieAutorisee = false,
    this.alertes = const [],
    this.ecart = false,
  });

  factory EleveDuJour.depuisJson(Map<String, dynamic> j) => EleveDuJour(
        ficheEleveId: j['fiche_eleve_id'] as String,
        nom: j['nom'] as String? ?? '',
        prenom: j['prenom'] as String? ?? '',
        classe: j['classe'] as String?,
        matricule: j['matricule'] as String?,
        arrivee: _date(j['arrivee']),
        enRetard: j['en_retard'] as bool? ?? false,
        sortie: _date(j['sortie']),
        absentAppel: j['absent_appel'] as bool? ?? false,
        justifie: j['justifie'] as bool? ?? false,
        sortieAutorisee: j['sortie_autorisee'] as bool? ?? false,
        alertes: [for (final a in (j['alertes'] as List?) ?? const []) a as String],
        ecart: j['ecart'] as bool? ?? false,
      );

  final String ficheEleveId;
  final String nom;
  final String prenom;
  final String? classe;
  final String? matricule;
  final DateTime? arrivee;
  final bool enRetard;
  final DateTime? sortie;
  final bool absentAppel;
  final bool justifie;
  final bool sortieAutorisee;
  final List<String> alertes;

  /// Entré au portail mais absent à l'appel en classe.
  final bool ecart;

  String get nomComplet => '$prenom $nom';
  bool get absent => arrivee == null;
  bool get alerteAbsence => alertes.contains('absence');
  bool get alerteSortie => alertes.contains('sortie_anticipee');
}

class PresenceDuJour {
  const PresenceDuJour({
    required this.jour,
    this.actif = false,
    this.heureLimiteArrivee,
    this.effectif = 0,
    this.arrives = 0,
    this.enRetard = 0,
    this.sortis = 0,
    this.traiteLe,
    this.alertesEnvoyees = 0,
    this.portails = const [],
    this.eleves = const [],
    this.creditsSms = 0,
  });

  factory PresenceDuJour.depuisJson(Map<String, dynamic> j) {
    final traite = j['traite'] as Map<String, dynamic>?;
    return PresenceDuJour(
      jour: _date(j['jour']) ?? DateTime.now(),
      actif: j['actif'] as bool? ?? false,
      heureLimiteArrivee: (j['heure_limite_arrivee'] as String?)?.substring(0, 5),
      effectif: (j['effectif'] as num?)?.toInt() ?? 0,
      arrives: (j['arrives'] as num?)?.toInt() ?? 0,
      enRetard: (j['en_retard'] as num?)?.toInt() ?? 0,
      sortis: (j['sortis'] as num?)?.toInt() ?? 0,
      traiteLe: _date(traite?['traite_le']),
      alertesEnvoyees: (traite?['alertes'] as num?)?.toInt() ?? 0,
      portails: [
        for (final p in (j['portails'] as List?) ?? const [])
          (
            appareilId: (p as Map<String, dynamic>)['appareil_id'] as String,
            derniereSynchro: _date(p['derniere_synchro']) ?? DateTime(2000),
          ),
      ],
      eleves: [for (final e in (j['eleves'] as List?) ?? const []) EleveDuJour.depuisJson(e as Map<String, dynamic>)],
      creditsSms: (j['credits_sms'] as num?)?.toInt() ?? 0,
    );
  }

  final DateTime jour;
  final bool actif;
  final String? heureLimiteArrivee;
  final int effectif;
  final int arrives;
  final int enRetard;
  final int sortis;

  /// Détection des absences du jour faite (et nombre d'alertes).
  final DateTime? traiteLe;
  final int alertesEnvoyees;
  final List<({String appareilId, DateTime derniereSynchro})> portails;
  final List<EleveDuJour> eleves;
  final int creditsSms;

  int get absents => effectif - arrives;
  int get ecarts => eleves.where((e) => e.ecart).length;

  /// Dernière transmission d'un portail.
  DateTime? get derniereSynchro {
    DateTime? d;
    for (final p in portails) {
      if (d == null || p.derniereSynchro.isAfter(d)) d = p.derniereSynchro;
    }
    return d;
  }
}

/// Crédits SMS d'un établissement.
class MouvementSms {
  const MouvementSms({required this.quantite, required this.motif, this.reference, required this.le});

  factory MouvementSms.depuisJson(Map<String, dynamic> j) => MouvementSms(
        quantite: (j['quantite'] as num).toInt(),
        motif: j['motif'] as String,
        reference: j['reference'] as String?,
        le: _date(j['created_at']) ?? DateTime.now(),
      );

  final int quantite;
  final String motif;
  final String? reference;
  final DateTime le;

  String get libelle => switch (motif) {
        'achat' => 'Achat',
        'envoi' => 'Envoi',
        'remboursement' => 'SMS non distribué (recrédité)',
        _ => 'Ajustement GSG',
      };
}

class PackSms {
  const PackSms({required this.code, required this.libelle, required this.quantite, required this.prix, this.devise = 'GNF', this.actif = true});

  factory PackSms.depuisJson(Map<String, dynamic> j) => PackSms(
        code: j['code'] as String,
        libelle: j['libelle'] as String? ?? j['code'] as String,
        quantite: (j['quantite'] as num).toInt(),
        prix: _nombre(j['prix']),
        devise: j['devise'] as String? ?? 'GNF',
        actif: j['actif'] as bool? ?? false,
      );

  final String code;
  final String libelle;
  final int quantite;
  final double prix;
  final String devise;
  final bool actif;
}

class CreditsSms {
  const CreditsSms({this.solde = 0, this.mouvements = const [], this.packs = const []});

  final int solde;
  final List<MouvementSms> mouvements;
  final List<PackSms> packs;
}

/// Famille en retard de paiement (paliers échus).
class FamilleEnRetard {
  const FamilleEnRetard({
    required this.inscriptionId,
    required this.nom,
    required this.prenom,
    this.classe,
    required this.exigible,
    required this.paye,
    required this.enRetard,
    this.derniereRelance,
  });

  factory FamilleEnRetard.depuisJson(Map<String, dynamic> j) => FamilleEnRetard(
        inscriptionId: j['inscription_id'] as String,
        nom: j['nom'] as String? ?? '',
        prenom: j['prenom'] as String? ?? '',
        classe: j['classe'] as String?,
        exigible: _nombre(j['exigible']),
        paye: _nombre(j['paye']),
        enRetard: _nombre(j['en_retard']),
        derniereRelance: _date(j['derniere_relance']),
      );

  final String inscriptionId;
  final String nom;
  final String prenom;
  final String? classe;
  final double exigible;
  final double paye;
  final double enRetard;
  final DateTime? derniereRelance;

  String get nomComplet => '$prenom $nom';

  /// Une famille n'est pas relancée deux fois dans la semaine.
  bool get relanceeRecemment =>
      derniereRelance != null && DateTime.now().difference(derniereRelance!) < const Duration(days: 7);
}

class ApercuRelances {
  const ApercuRelances({this.creditsSms = 0, this.familles = const []});

  factory ApercuRelances.depuisJson(Map<String, dynamic> j) => ApercuRelances(
        creditsSms: (j['credits_sms'] as num?)?.toInt() ?? 0,
        familles: [for (final f in (j['familles'] as List?) ?? const []) FamilleEnRetard.depuisJson(f as Map<String, dynamic>)],
      );

  final int creditsSms;
  final List<FamilleEnRetard> familles;

  double get totalEnRetard => familles.fold(0, (s, f) => s + f.enRetard);
}

class BilanRelance {
  const BilanRelance({this.familles = 0, this.push = 0, this.sms = 0, this.smsNonEnvoyes = 0, this.dejaRelancees = 0});

  factory BilanRelance.depuisJson(Map<String, dynamic> j) => BilanRelance(
        familles: (j['familles'] as num?)?.toInt() ?? 0,
        push: (j['push'] as num?)?.toInt() ?? 0,
        sms: (j['sms'] as num?)?.toInt() ?? 0,
        smsNonEnvoyes: (j['sms_non_envoyes'] as num?)?.toInt() ?? 0,
        dejaRelancees: (j['deja_relancees'] as num?)?.toInt() ?? 0,
      );

  final int familles;
  final int push;
  final int sms;
  final int smsNonEnvoyes;
  final int dejaRelancees;
}

/// Port du pointage.
abstract interface class PointageRepository {
  // Portail
  Future<DonneesPortail> donneesPortail(String etablissementId);
  Future<ResultatScan> scanner({
    required String etablissementId,
    required String lecture,
    required SensPointage sens,
    required String appareilId,
  });
  Future<void> signalerPortail(String etablissementId, String appareilId);
  Future<int> scansEnAttente();

  // Direction
  Future<ParametresPointage> parametres(String etablissementId);
  Future<void> enregistrerParametres(String etablissementId, ParametresPointage parametres);
  Future<List<CartePortail>> cartesClasse(String classeId, {bool regenerer = false});
  Future<void> remplacerCarte(String ficheEleveId);
  Future<PresenceDuJour> presenceDuJour(String etablissementId);
  Future<void> autoriserSortie(String ficheEleveId, DateTime jour, String motif);
  Future<CreditsSms> creditsSms(String etablissementId);
  Future<Uri> acheterPack(String etablissementId, String pack);
  Future<ApercuRelances> apercuRelances(String etablissementId);
  Future<BilanRelance> relancer(String etablissementId, {required bool sms, List<String>? inscriptions});

  // Familles
  Future<bool> avisArriveeSortie();
  Future<void> definirAvisArriveeSortie(bool actif);

  // GSG
  Future<List<PackSms>> tousLesPacks();
  Future<void> definirPack(PackSms pack);
  Future<List<({String id, String nom, String? ville, int solde})>> soldesEtablissements();
  Future<int> crediter(String etablissementId, int quantite, String reference);
}

class ErreurPointage implements Exception {
  const ErreurPointage(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'HORS_CONNEXION' => 'Pas de réseau pour le moment.',
        'RESEAU_REQUIS' => 'Cette action demande le réseau. Réessayez une fois connecté.',
        'PERMISSION_REFUSEE' || 'ACCES_REFUSE' => "Vous n'avez pas le droit de gérer les présences de cet établissement.",
        'HEURES_INCOHERENTES' => "L'heure limite d'arrivée doit précéder la fin des cours.",
        'JOURS_INVALIDES' => 'Choisissez au moins un jour de classe.',
        'MOTIF_OBLIGATOIRE' => 'Indiquez le motif.',
        'PACK_INDISPONIBLE' => "Ce pack n'est pas en vente pour le moment.",
        'CINETPAY_NON_CONFIGURE' => "Le paiement en ligne de GSG n'est pas encore ouvert. Contactez GSG pour acheter des crédits.",
        'PRIX_REQUIS' => 'Fixez un prix avant de mettre le pack en vente.',
        'REFERENCE_OBLIGATOIRE' => 'Indiquez la référence du paiement reçu.',
        'SOLDE_INSUFFISANT' => "Le solde de l'école est insuffisant pour ce retrait.",
        'AUCUN_PORTAIL_DONNEES' => "Ouvrez une première fois le portail avec du réseau pour charger les cartes.",
        _ => 'Opération impossible pour le moment. Réessayez.',
      };

  @override
  String toString() => 'ErreurPointage($code)';
}
