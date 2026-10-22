/// Bibliothèque physique (M17, cahier v4.1 ch. 25) : catalogue gratuit pour
/// tous, exemplaires étiquetés, prêt et retour au guichet (carte QR de
/// l'élève puis étiquette du livre), statuts automatiques « en retard » et
/// « perdu », réservation, relances, inventaire. Distincte des ressources
/// numériques et des flashcards (règle 25.1).
library;

class ErreurBibliotheque implements Exception {
  const ErreurBibliotheque(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'HORS_CONNEXION' => 'Pas de réseau : action impossible pour le moment.',
        'EXEMPLAIRE_DEJA_PRETE' => 'Cet exemplaire est déjà prêté.',
        'EXEMPLAIRE_RESERVE' => 'Cet exemplaire est gardé pour un autre élève (réservation).',
        'EXEMPLAIRE_RETIRE' => 'Cet exemplaire est retiré du fonds.',
        'EXEMPLAIRE_INCONNU' => 'Étiquette inconnue.',
        'EXEMPLAIRE_EMPRUNTE' => 'Exemplaire en prêt : attendez son retour.',
        'ELEVE_INCONNU' => 'Élève inconnu dans cet établissement.',
        'LIMITE_EMPRUNTS' => 'L’élève a déjà le nombre maximal d’emprunts.',
        'RENOUVELLEMENTS_EPUISES' => 'Ce prêt a déjà été renouvelé le nombre de fois autorisé.',
        'LIVRE_RESERVE' => 'Un autre élève attend ce livre : pas de renouvellement.',
        'EMPRUNT_CLOS' => 'Ce prêt est déjà clos.',
        'ACCES_REFUSE' => 'Vous n’avez pas les droits pour cette action.',
        _ => 'Opération impossible ($code).',
      };

  @override
  String toString() => 'ErreurBibliotheque($code)';
}

/// Contenu du QR des étiquettes : distinct de celui des cartes d'élève.
const prefixeQrLivre = 'ECOLIV:';

/// Lecture d'une douchette ou de la caméra : code d'exemplaire, ou `null`
/// si ce n'est pas une étiquette de livre.
String? codeExemplaireDepuisLecture(String lu) {
  var v = lu.trim().toUpperCase();
  if (v.startsWith(prefixeQrLivre)) v = v.substring(prefixeQrLivre.length);
  return RegExp(r'^LIV-\d{6}$').hasMatch(v) ? v : null;
}

int _entier(Object? v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

enum StatutEmprunt {
  enCours('en_cours', 'En cours'),
  enRetard('en_retard', 'En retard'),
  perdu('perdu', 'Perdu'),
  rendu('rendu', 'Rendu');

  const StatutEmprunt(this.code, this.libelle);

  final String code;
  final String libelle;

  static StatutEmprunt depuisCode(String? c) => values.firstWhere((s) => s.code == c, orElse: () => enCours);
}

class ParametresBibliotheque {
  const ParametresBibliotheque({
    this.dureePretJours = 14,
    this.maxEmprunts = 2,
    this.renouvellementsMax = 1,
    this.delaiPerteJours = 30,
    this.relances = true,
    this.inventaireDepuis,
  });

  final int dureePretJours;
  final int maxEmprunts;
  final int renouvellementsMax;
  final int delaiPerteJours;
  final bool relances;
  final DateTime? inventaireDepuis;

  factory ParametresBibliotheque.depuisJson(Map<String, dynamic>? j) => j == null
      ? const ParametresBibliotheque()
      : ParametresBibliotheque(
          dureePretJours: _entier(j['duree_pret_jours'] ?? 14),
          maxEmprunts: _entier(j['max_emprunts'] ?? 2),
          renouvellementsMax: _entier(j['renouvellements_max'] ?? 1),
          delaiPerteJours: _entier(j['delai_perte_jours'] ?? 30),
          relances: j['relances'] as bool? ?? true,
          inventaireDepuis: _date(j['inventaire_depuis']),
        );
}

class Livre {
  const Livre({
    required this.id,
    required this.titre,
    this.auteurs,
    this.isbn,
    this.editeur,
    this.annee,
    this.categorie,
    this.niveau,
    this.cote,
    this.resume,
    this.exemplaires = 0,
    this.disponibles = 0,
    this.reservations = 0,
  });

  final String id;
  final String titre;
  final String? auteurs;
  final String? isbn;
  final String? editeur;
  final int? annee;
  final String? categorie;
  final String? niveau;
  final String? cote;
  final String? resume;
  final int exemplaires;
  final int disponibles;
  final int reservations;

  factory Livre.depuisJson(Map<String, dynamic> j) => Livre(
        id: j['id'] as String,
        titre: j['titre'] as String? ?? '',
        auteurs: j['auteurs'] as String?,
        isbn: j['isbn'] as String?,
        editeur: j['editeur'] as String?,
        annee: j['annee'] == null ? null : _entier(j['annee']),
        categorie: j['categorie'] as String?,
        niveau: j['niveau'] as String?,
        cote: j['cote'] as String?,
        resume: j['resume'] as String?,
        exemplaires: _entier(j['exemplaires']),
        disponibles: _entier(j['disponibles']),
        reservations: _entier(j['reservations']),
      );
}

/// Fiche saisie (ou préremplie depuis l'ISBN).
class SaisieLivre {
  const SaisieLivre({
    required this.titre,
    this.auteurs,
    this.isbn,
    this.editeur,
    this.annee,
    this.categorie,
    this.niveau,
    this.cote,
    this.resume,
  });

  final String titre;
  final String? auteurs;
  final String? isbn;
  final String? editeur;
  final int? annee;
  final String? categorie;
  final String? niveau;
  final String? cote;
  final String? resume;
}

class ExemplaireGuichet {
  const ExemplaireGuichet({required this.id, required this.code, required this.livreId, required this.titre, this.cote, this.retire = false});

  final String id;
  final String code;
  final String livreId;
  final String titre;
  final String? cote;
  final bool retire;

  factory ExemplaireGuichet.depuisJson(Map<String, dynamic> j) => ExemplaireGuichet(
        id: j['id'] as String,
        code: j['code'] as String,
        livreId: j['livre_id'] as String,
        titre: j['titre'] as String? ?? '',
        cote: j['cote'] as String?,
        retire: j['retire'] as bool? ?? false,
      );
}

class LecteurGuichet {
  const LecteurGuichet({required this.ficheEleveId, required this.nom, required this.prenom, this.classe, this.jeton});

  final String ficheEleveId;
  final String nom;
  final String prenom;
  final String? classe;
  final String? jeton;

  String get nomComplet => '$prenom $nom';

  factory LecteurGuichet.depuisJson(Map<String, dynamic> j) => LecteurGuichet(
        ficheEleveId: j['fiche_eleve_id'] as String,
        nom: j['nom'] as String? ?? '',
        prenom: j['prenom'] as String? ?? '',
        classe: j['classe'] as String?,
        jeton: j['jeton'] as String?,
      );
}

class EmpruntGuichet {
  const EmpruntGuichet({
    required this.id,
    required this.exemplaireId,
    required this.ficheEleveId,
    required this.echeance,
    this.statut = StatutEmprunt.enCours,
    this.enAttenteEnvoi = false,
  });

  final String id;
  final String exemplaireId;
  final String ficheEleveId;
  final DateTime echeance;
  final StatutEmprunt statut;
  final bool enAttenteEnvoi;

  Map<String, dynamic> versJson() => {
        'id': id,
        'exemplaire_id': exemplaireId,
        'fiche_eleve_id': ficheEleveId,
        'echeance': echeance.toIso8601String().substring(0, 10),
        'statut': statut.code,
        'en_attente': enAttenteEnvoi,
      };

  factory EmpruntGuichet.depuisJson(Map<String, dynamic> j) => EmpruntGuichet(
        id: j['id'] as String,
        exemplaireId: j['exemplaire_id'] as String,
        ficheEleveId: j['fiche_eleve_id'] as String,
        echeance: DateTime.parse(j['echeance'] as String),
        statut: StatutEmprunt.depuisCode(j['statut'] as String?),
        enAttenteEnvoi: j['en_attente'] as bool? ?? false,
      );
}

/// Tout ce que le guichet garde sur l'appareil pour prêter sans réseau.
class DonneesGuichet {
  const DonneesGuichet({
    required this.parametres,
    required this.exemplaires,
    required this.lecteurs,
    required this.emprunts,
  });

  final ParametresBibliotheque parametres;
  final List<ExemplaireGuichet> exemplaires;
  final List<LecteurGuichet> lecteurs;
  final List<EmpruntGuichet> emprunts;

  ExemplaireGuichet? exemplaire(String code) => exemplaires.where((e) => e.code == code).firstOrNull;
  LecteurGuichet? lecteurParJeton(String jeton) => lecteurs.where((l) => l.jeton == jeton).firstOrNull;
  LecteurGuichet? lecteur(String ficheId) => lecteurs.where((l) => l.ficheEleveId == ficheId).firstOrNull;
  List<EmpruntGuichet> empruntsDe(String ficheId) => emprunts.where((e) => e.ficheEleveId == ficheId).toList();
  EmpruntGuichet? empruntDe(String exemplaireId) => emprunts.where((e) => e.exemplaireId == exemplaireId).firstOrNull;

  DonneesGuichet avecEmprunts(List<EmpruntGuichet> nouveaux) =>
      DonneesGuichet(parametres: parametres, exemplaires: exemplaires, lecteurs: lecteurs, emprunts: nouveaux);

  Map<String, dynamic> versJson() => {
        'parametres': {
          'duree_pret_jours': parametres.dureePretJours,
          'max_emprunts': parametres.maxEmprunts,
          'renouvellements_max': parametres.renouvellementsMax,
          'delai_perte_jours': parametres.delaiPerteJours,
          'relances': parametres.relances,
        },
        'exemplaires': [
          for (final e in exemplaires)
            {'id': e.id, 'code': e.code, 'livre_id': e.livreId, 'titre': e.titre, 'cote': e.cote, 'retire': e.retire},
        ],
        'cartes': [
          for (final l in lecteurs)
            {'fiche_eleve_id': l.ficheEleveId, 'nom': l.nom, 'prenom': l.prenom, 'classe': l.classe, 'jeton': l.jeton},
        ],
        'emprunts': [for (final e in emprunts) e.versJson()],
      };

  factory DonneesGuichet.depuisJson(Map<String, dynamic> j) => DonneesGuichet(
        parametres: ParametresBibliotheque.depuisJson((j['parametres'] as Map?)?.cast<String, dynamic>()),
        exemplaires: [for (final e in (j['exemplaires'] as List?) ?? const []) ExemplaireGuichet.depuisJson((e as Map).cast<String, dynamic>())],
        lecteurs: [for (final c in (j['cartes'] as List?) ?? const []) LecteurGuichet.depuisJson((c as Map).cast<String, dynamic>())],
        emprunts: [for (final e in (j['emprunts'] as List?) ?? const []) EmpruntGuichet.depuisJson((e as Map).cast<String, dynamic>())],
      );
}

enum StatutGuichet { prete, rendu, enAttenteEnvoi, refuse, pasEmprunte }

class ResultatGuichet {
  const ResultatGuichet({required this.statut, required this.titre, this.message, this.echeance, this.lecteur, this.reserve = false, this.enRetard = false});

  final StatutGuichet statut;
  final String titre;
  final String? message;
  final DateTime? echeance;
  final LecteurGuichet? lecteur;
  final bool reserve;
  final bool enRetard;
}

class EmpruntEleve {
  const EmpruntEleve({required this.id, required this.titre, required this.echeance, required this.statut, this.renduLe});

  final String id;
  final String titre;
  final DateTime echeance;
  final StatutEmprunt statut;
  final DateTime? renduLe;

  factory EmpruntEleve.depuisJson(Map<String, dynamic> j) => EmpruntEleve(
        id: j['id'] as String,
        titre: j['titre'] as String? ?? '',
        echeance: DateTime.parse(j['echeance'] as String),
        statut: StatutEmprunt.depuisCode(j['statut'] as String?),
        renduLe: _date(j['rendu_le']),
      );
}

class ReservationEleve {
  const ReservationEleve({required this.livreId, required this.titre, required this.prete, this.gardeeJusquAu});

  final String livreId;
  final String titre;

  /// L'exemplaire attend l'élève au guichet.
  final bool prete;
  final DateTime? gardeeJusquAu;

  factory ReservationEleve.depuisJson(Map<String, dynamic> j) => ReservationEleve(
        livreId: j['livre_id'] as String,
        titre: j['titre'] as String? ?? '',
        prete: j['prete'] as bool? ?? false,
        gardeeJusquAu: _date(j['gardee_jusqu_au']),
      );
}

class LigneSuivi {
  const LigneSuivi({required this.titre, this.code, this.eleve, this.classe, this.echeance, this.statut, this.id});

  final String? id;
  final String titre;
  final String? code;
  final String? eleve;
  final String? classe;
  final DateTime? echeance;
  final StatutEmprunt? statut;

  factory LigneSuivi.depuisJson(Map<String, dynamic> j) => LigneSuivi(
        id: j['id'] as String?,
        titre: j['titre'] as String? ?? '',
        code: j['code'] as String?,
        eleve: j['eleve'] as String?,
        classe: j['classe'] as String?,
        echeance: j['echeance'] == null ? null : DateTime.tryParse(j['echeance'] as String),
        statut: j['statut'] == null ? null : StatutEmprunt.depuisCode(j['statut'] as String?),
      );
}

class TableauBibliotheque {
  const TableauBibliotheque({
    required this.parametres,
    required this.livres,
    required this.exemplaires,
    required this.enCours,
    required this.retards,
    required this.pertesRepetees,
    required this.plusEmpruntes,
    this.inventaireVus,
    this.introuvables = const [],
  });

  final ParametresBibliotheque parametres;
  final int livres;
  final int exemplaires;
  final int enCours;
  final List<LigneSuivi> retards;
  final List<({String eleve, int pertes})> pertesRepetees;
  final List<({String titre, int emprunts})> plusEmpruntes;
  final int? inventaireVus;
  final List<LigneSuivi> introuvables;

  factory TableauBibliotheque.depuisJson(Map<String, dynamic> j) {
    final inv = (j['inventaire'] as Map?)?.cast<String, dynamic>();
    return TableauBibliotheque(
      parametres: ParametresBibliotheque.depuisJson((j['parametres'] as Map?)?.cast<String, dynamic>()),
      livres: _entier(j['livres']),
      exemplaires: _entier(j['exemplaires']),
      enCours: _entier(j['en_cours']),
      retards: [for (final r in (j['retards'] as List?) ?? const []) LigneSuivi.depuisJson((r as Map).cast<String, dynamic>())],
      pertesRepetees: [
        for (final p in (j['pertes_repetees'] as List?) ?? const [])
          (eleve: (p as Map)['eleve'] as String? ?? '', pertes: _entier(p['pertes'])),
      ],
      plusEmpruntes: [
        for (final p in (j['plus_empruntes'] as List?) ?? const [])
          (titre: (p as Map)['titre'] as String? ?? '', emprunts: _entier(p['emprunts'])),
      ],
      inventaireVus: inv == null ? null : _entier(inv['vus']),
      introuvables: [
        for (final r in (inv?['introuvables'] as List?) ?? const []) LigneSuivi.depuisJson((r as Map).cast<String, dynamic>()),
      ],
    );
  }
}

abstract interface class BibliothequeRepository {
  // Tous les membres
  Future<List<Livre>> catalogue(String etablissementId, {String? texte});
  Future<({List<EmpruntEleve> emprunts, List<ReservationEleve> reservations})> empruntsEleve(String ficheEleveId);
  Future<void> reserver(String livreId, String ficheEleveId);

  // Bibliothèque (direction ou personnel habilité)
  Future<String> enregistrerLivre(String etablissementId, SaisieLivre saisie, {String? id, int nouveauxExemplaires = 0});
  Future<SaisieLivre?> rechercherIsbn(String isbn);
  Future<List<ExemplaireGuichet>> exemplairesDuLivre(String etablissementId, String livreId);
  Future<DonneesGuichet> guichet(String etablissementId, {bool rafraichir = true});
  Future<ResultatGuichet> preter({required String etablissementId, required LecteurGuichet lecteur, required String code});
  Future<ResultatGuichet> rendre({required String etablissementId, required String code});
  Future<DateTime> renouveler(String empruntId);
  Future<void> declarerPerdu(String empruntId);
  Future<TableauBibliotheque> tableau(String etablissementId);
  Future<void> enregistrerParametres(String etablissementId, ParametresBibliotheque p);
  Future<void> commencerInventaire(String etablissementId);
  Future<String?> inventorier(String etablissementId, String code);
}
