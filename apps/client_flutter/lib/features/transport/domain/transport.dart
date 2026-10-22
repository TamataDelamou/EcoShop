/// Transport scolaire (M18, cahier v4.1 ch. 24) : circuits et arrêts,
/// affectation des élèves, trajets du chauffeur (montée et descente par la
/// carte QR de l'élève), suivi par les familles, facturation par le même
/// circuit que la scolarité.
library;

import 'dart:math' as math;

class ErreurTransport implements Exception {
  const ErreurTransport(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'HORS_CONNEXION' => 'Pas de réseau : action impossible pour le moment.',
        'COMPTE_CHAUFFEUR_INTROUVABLE' =>
          'Aucun compte EcoShop avec ce numéro ou cette adresse : le chauffeur doit d’abord s’inscrire.',
        'CIRCUIT_COMPLET' => 'Le véhicule est complet (capacité atteinte).',
        'ARRET_AVEC_ELEVES' => 'Des élèves sont affectés à un arrêt retiré : réaffectez-les d’abord.',
        'ARRET_INCONNU' => 'Arrêt inconnu pour ce circuit.',
        'ANNEE_COURANTE_ABSENTE' => 'Ouvrez d’abord l’année scolaire de l’établissement.',
        'FICHE_AUTRE_ETABLISSEMENT' => 'Cet élève n’appartient pas à l’établissement.',
        'ACCES_REFUSE' => 'Vous n’avez pas les droits pour cette action.',
        _ => 'Opération impossible ($code).',
      };

  @override
  String toString() => 'ErreurTransport($code)';
}

double? _reel(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
int _entier(Object? v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

class ArretTransport {
  const ArretTransport({
    required this.id,
    required this.ordre,
    required this.nom,
    this.repere,
    this.latitude,
    this.longitude,
    this.heureMatin,
    this.heureSoir,
    this.eleves = 0,
  });

  final String id;
  final int ordre;
  final String nom;
  final String? repere;
  final double? latitude;
  final double? longitude;

  /// « HH:MM ».
  final String? heureMatin;
  final String? heureSoir;
  final int eleves;

  bool get localise => latitude != null && longitude != null;

  ArretTransport copier({int? ordre, String? nom, String? repere, double? latitude, double? longitude,
          String? heureMatin, String? heureSoir}) =>
      ArretTransport(
        id: id,
        ordre: ordre ?? this.ordre,
        nom: nom ?? this.nom,
        repere: repere ?? this.repere,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        heureMatin: heureMatin ?? this.heureMatin,
        heureSoir: heureSoir ?? this.heureSoir,
        eleves: eleves,
      );

  Map<String, dynamic> versJson() => {
        'id': id,
        'nom': nom,
        'repere': repere,
        'latitude': latitude,
        'longitude': longitude,
        'heure_matin': heureMatin,
        'heure_soir': heureSoir,
      };

  factory ArretTransport.depuisJson(Map<String, dynamic> j) => ArretTransport(
        id: j['id'] as String,
        ordre: _entier(j['ordre']),
        nom: j['nom'] as String? ?? '',
        repere: j['repere'] as String?,
        latitude: _reel(j['latitude']),
        longitude: _reel(j['longitude']),
        heureMatin: j['heure_matin'] as String?,
        heureSoir: j['heure_soir'] as String?,
        eleves: _entier(j['eleves']),
      );
}

class EleveTransporte {
  const EleveTransporte({
    required this.ficheEleveId,
    required this.nom,
    required this.prenom,
    this.arretId,
    this.classe,
    this.jeton,
    this.matricule,
    this.circuitId,
    this.montantDu,
    this.montantPaye,
  });

  final String ficheEleveId;
  final String nom;
  final String prenom;
  final String? arretId;
  final String? classe;

  /// Carte QR (téléphone du chauffeur seulement, pour scanner sans réseau).
  final String? jeton;
  final String? matricule;
  final String? circuitId;
  final double? montantDu;
  final double? montantPaye;

  String get nomComplet => '$prenom $nom';
  double? get resteAPayer => montantDu == null ? null : math.max(0.0, montantDu! - (montantPaye ?? 0));

  factory EleveTransporte.depuisJson(Map<String, dynamic> j) => EleveTransporte(
        ficheEleveId: j['fiche_eleve_id'] as String,
        nom: j['nom'] as String? ?? '',
        prenom: j['prenom'] as String? ?? '',
        arretId: j['arret_id'] as String?,
        classe: j['classe'] as String?,
        jeton: j['jeton'] as String?,
        matricule: j['matricule'] as String?,
        circuitId: j['circuit_id'] as String?,
        montantDu: _reel(j['montant_du']),
        montantPaye: _reel(j['montant_paye']),
      );
}

class CircuitTransport {
  const CircuitTransport({
    required this.id,
    required this.nom,
    required this.arrets,
    required this.eleves,
    this.vehicule,
    this.capacite,
    this.tarifAnnuel = 0,
    this.actif = true,
    this.chauffeur,
    this.telephoneChauffeur,
    this.etablissementId,
    this.etablissement,
    this.trajetEnCours,
    this.dernierTrajet,
  });

  final String id;
  final String nom;
  final String? vehicule;
  final int? capacite;
  final double tarifAnnuel;
  final bool actif;
  final String? chauffeur;
  final String? telephoneChauffeur;
  final String? etablissementId;
  final String? etablissement;
  final List<ArretTransport> arrets;
  final List<EleveTransporte> eleves;
  final TrajetResume? trajetEnCours;
  final TrajetResume? dernierTrajet;

  ArretTransport? arret(String? id) => id == null ? null : arrets.where((a) => a.id == id).firstOrNull;

  factory CircuitTransport.depuisJson(Map<String, dynamic> j) => CircuitTransport(
        id: j['id'] as String,
        nom: j['nom'] as String? ?? '',
        vehicule: j['vehicule'] as String?,
        capacite: j['capacite'] == null ? null : _entier(j['capacite']),
        tarifAnnuel: _reel(j['tarif_annuel']) ?? 0,
        actif: j['actif'] as bool? ?? true,
        chauffeur: (j['chauffeur'] as String?)?.trim().isEmpty == true ? null : j['chauffeur'] as String?,
        telephoneChauffeur: j['telephone_chauffeur'] as String?,
        etablissementId: j['etablissement_id'] as String?,
        etablissement: j['etablissement'] as String?,
        arrets: [for (final a in (j['arrets'] as List?) ?? const []) ArretTransport.depuisJson((a as Map).cast<String, dynamic>())],
        eleves: [for (final e in (j['eleves'] as List?) ?? const []) EleveTransporte.depuisJson((e as Map).cast<String, dynamic>())],
        trajetEnCours: j['trajet_en_cours'] == null
            ? null
            : TrajetResume.depuisJson((j['trajet_en_cours'] as Map).cast<String, dynamic>()),
        dernierTrajet: j['dernier_trajet'] == null
            ? null
            : TrajetResume.depuisJson((j['dernier_trajet'] as Map).cast<String, dynamic>()),
      );
}

enum SensTrajet {
  aller('aller', 'Aller (vers l’école)'),
  retour('retour', 'Retour (vers les familles)');

  const SensTrajet(this.code, this.libelle);

  final String code;
  final String libelle;

  static SensTrajet depuisCode(String? c) => c == 'retour' ? retour : aller;
}

class TrajetResume {
  const TrajetResume({
    required this.sens,
    this.id,
    this.demarreLe,
    this.termineLe,
    this.dernierArretOrdre,
    this.positionLe,
    this.aBord,
    this.restesABord,
  });

  final String? id;
  final SensTrajet sens;
  final DateTime? demarreLe;
  final DateTime? termineLe;
  final int? dernierArretOrdre;
  final DateTime? positionLe;
  final int? aBord;
  final int? restesABord;

  factory TrajetResume.depuisJson(Map<String, dynamic> j) => TrajetResume(
        id: j['id'] as String?,
        sens: SensTrajet.depuisCode(j['sens'] as String?),
        demarreLe: DateTime.tryParse(j['demarre_le'] as String? ?? '')?.toLocal(),
        termineLe: DateTime.tryParse(j['termine_le'] as String? ?? '')?.toLocal(),
        dernierArretOrdre: j['dernier_arret_ordre'] == null ? null : _entier(j['dernier_arret_ordre']),
        positionLe: DateTime.tryParse(j['position_le'] as String? ?? '')?.toLocal(),
        aBord: j['a_bord'] == null ? null : _entier(j['a_bord']),
        restesABord: j['restes_a_bord'] == null ? null : _entier(j['restes_a_bord']),
      );
}

/// Trajet en cours sur le téléphone du chauffeur, gardé sur l'appareil pour
/// reprendre après une coupure (batterie, application fermée).
class TrajetLocal {
  const TrajetLocal({
    required this.id,
    required this.circuitId,
    required this.sens,
    required this.demarreLe,
    this.arretsPasses = const [],
    this.aBord = const [],
  });

  final String id;
  final String circuitId;
  final SensTrajet sens;
  final DateTime demarreLe;
  final List<String> arretsPasses;

  /// Élèves à bord (identifiants de fiche), d'après les scans du téléphone.
  final List<String> aBord;

  TrajetLocal avec({List<String>? arretsPasses, List<String>? aBord}) => TrajetLocal(
        id: id,
        circuitId: circuitId,
        sens: sens,
        demarreLe: demarreLe,
        arretsPasses: arretsPasses ?? this.arretsPasses,
        aBord: aBord ?? this.aBord,
      );

  Map<String, dynamic> versJson() => {
        'id': id,
        'circuit_id': circuitId,
        'sens': sens.code,
        'demarre_le': demarreLe.toUtc().toIso8601String(),
        'arrets_passes': arretsPasses,
        'a_bord': aBord,
      };

  factory TrajetLocal.depuisJson(Map<String, dynamic> j) => TrajetLocal(
        id: j['id'] as String,
        circuitId: j['circuit_id'] as String,
        sens: SensTrajet.depuisCode(j['sens'] as String?),
        demarreLe: DateTime.parse(j['demarre_le'] as String).toLocal(),
        arretsPasses: [for (final a in (j['arrets_passes'] as List?) ?? const []) a as String],
        aBord: [for (final a in (j['a_bord'] as List?) ?? const []) a as String],
      );

  /// Arrêts dans l'ordre du trajet : du premier au dernier à l'aller, à
  /// l'envers au retour.
  List<ArretTransport> arretsDansLOrdre(List<ArretTransport> arrets) {
    final tries = [...arrets]..sort((a, b) => a.ordre.compareTo(b.ordre));
    return sens == SensTrajet.aller ? tries : tries.reversed.toList();
  }

  ArretTransport? prochainArret(List<ArretTransport> arrets) =>
      arretsDansLOrdre(arrets).where((a) => !arretsPasses.contains(a.id)).firstOrNull;
}

enum EvenementBus {
  montee('montee', 'Montée'),
  descente('descente', 'Descente');

  const EvenementBus(this.code, this.libelle);

  final String code;
  final String libelle;
}

enum StatutScanBus { enregistre, enAttenteEnvoi, carteInconnue, horsCircuit, dejaFait }

class ResultatScanBus {
  const ResultatScanBus({required this.statut, required this.evenement, this.eleve, this.nom});

  final StatutScanBus statut;
  final EvenementBus evenement;
  final EleveTransporte? eleve;

  /// Nom renvoyé par le serveur (élève hors liste du téléphone).
  final String? nom;
}

class EvenementJourTransport {
  const EvenementJourTransport({required this.evenement, required this.heure, this.arret});

  final EvenementBus evenement;
  final DateTime heure;
  final String? arret;

  factory EvenementJourTransport.depuisJson(Map<String, dynamic> j) => EvenementJourTransport(
        evenement: j['evenement'] == 'descente' ? EvenementBus.descente : EvenementBus.montee,
        heure: DateTime.parse(j['scanne_le'] as String).toLocal(),
        arret: j['arret'] as String?,
      );
}

/// Ce que voit la famille (24.2, 24.3).
class SuiviTransport {
  const SuiviTransport({
    required this.affecte,
    this.circuit,
    this.arretId,
    this.arrets = const [],
    this.trajetSens,
    this.trajetLatitude,
    this.trajetLongitude,
    this.positionLe,
    this.dernierArretOrdre,
    this.dernierArretLe,
    this.aBord = false,
    this.aujourdHui = const [],
  });

  final bool affecte;
  final CircuitTransport? circuit;
  final String? arretId;
  final List<ArretTransport> arrets;

  /// Renseignés seulement pendant un trajet en cours.
  final SensTrajet? trajetSens;
  final double? trajetLatitude;
  final double? trajetLongitude;
  final DateTime? positionLe;
  final int? dernierArretOrdre;
  final DateTime? dernierArretLe;
  final bool aBord;
  final List<EvenementJourTransport> aujourdHui;

  bool get trajetEnCours => trajetSens != null;
  ArretTransport? get monArret => arrets.where((a) => a.id == arretId).firstOrNull;
  ArretTransport? get dernierArret =>
      dernierArretOrdre == null ? null : arrets.where((a) => a.ordre == dernierArretOrdre).firstOrNull;

  /// Arrêts restant avant celui de l'enfant (sens du trajet), si connu.
  int? get arretsAvantLeMien {
    final mien = monArret;
    final dernier = dernierArretOrdre;
    if (mien == null || trajetSens == null) return null;
    if (dernier == null) {
      return trajetSens == SensTrajet.aller
          ? arrets.where((a) => a.ordre < mien.ordre).length
          : arrets.where((a) => a.ordre > mien.ordre).length;
    }
    final reste = trajetSens == SensTrajet.aller ? mien.ordre - dernier - 1 : dernier - mien.ordre - 1;
    return reste < 0 ? null : reste;
  }

  factory SuiviTransport.depuisJson(Map<String, dynamic> j) {
    if (j['affecte'] != true) return const SuiviTransport(affecte: false);
    final c = (j['circuit'] as Map).cast<String, dynamic>();
    final arrets = [for (final a in (j['arrets'] as List?) ?? const []) ArretTransport.depuisJson((a as Map).cast<String, dynamic>())];
    final t = (j['trajet_en_cours'] as Map?)?.cast<String, dynamic>();
    return SuiviTransport(
      affecte: true,
      circuit: CircuitTransport.depuisJson({...c, 'arrets': <Object>[], 'eleves': <Object>[]}),
      arretId: j['arret_id'] as String?,
      arrets: arrets,
      trajetSens: t == null ? null : SensTrajet.depuisCode(t['sens'] as String?),
      trajetLatitude: _reel(t?['latitude']),
      trajetLongitude: _reel(t?['longitude']),
      positionLe: DateTime.tryParse(t?['position_le'] as String? ?? '')?.toLocal(),
      dernierArretOrdre: t?['dernier_arret_ordre'] == null ? null : _entier(t?['dernier_arret_ordre']),
      dernierArretLe: DateTime.tryParse(t?['dernier_arret_le'] as String? ?? '')?.toLocal(),
      aBord: t?['a_bord'] == true,
      aujourdHui: [
        for (final e in (j['aujourd_hui'] as List?) ?? const []) EvenementJourTransport.depuisJson((e as Map).cast<String, dynamic>()),
      ],
    );
  }
}

/// Distance en mètres entre deux points (formule de haversine).
double distanceMetres(double lat1, double lon1, double lat2, double lon2) {
  const rayon = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * rayon * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Un arrêt est considéré passé quand le bus s'en approche à moins de
/// [rayonArretMetres].
const rayonArretMetres = 120.0;

abstract interface class TransportRepository {
  // Direction
  Future<List<CircuitTransport>> circuits(String etablissementId);
  Future<void> enregistrerCircuit({
    required String etablissementId,
    String? id,
    required String nom,
    String? vehicule,
    int? capacite,
    required double tarifAnnuel,
    String? chauffeur,
    bool actif,
  });
  Future<void> enregistrerArrets(String circuitId, List<ArretTransport> arrets);
  Future<List<EleveTransporte>> rechercherEleves(String etablissementId, String texte);
  Future<void> affecter({required String ficheEleveId, required String circuitId, required String arretId});
  Future<void> retirerAffectation(String ficheEleveId);

  // Chauffeur (d'abord hors connexion)
  Future<List<CircuitTransport>> mesCircuitsChauffeur();
  Future<TrajetLocal?> trajetLocal(String circuitId);
  Future<TrajetLocal> demarrer(CircuitTransport circuit, SensTrajet sens);
  Future<TrajetLocal> passerArret(TrajetLocal trajet, ArretTransport arret);
  Future<void> signalerPosition(TrajetLocal trajet, double latitude, double longitude);
  Future<(ResultatScanBus, TrajetLocal)> scanner({
    required TrajetLocal trajet,
    required CircuitTransport circuit,
    required String lecture,
    required EvenementBus evenement,
  });

  /// Termine le trajet ; renvoie les élèves encore à bord (d'après le
  /// téléphone, complété par le serveur s'il est joignable).
  Future<List<EleveTransporte>> terminer(TrajetLocal trajet, CircuitTransport circuit);

  // Famille
  Future<SuiviTransport> suivi(String ficheEleveId);
}
