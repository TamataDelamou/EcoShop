/// Règles d'un réseau (REG-17) : politique de frais, grille, conditions de
/// transfert ; et transferts d'élèves entre ses écoles.
library;

/// Politiques de frais, choisies par la Direction Générale.
const politiquesFrais = <String, String>{
  'autonome': 'Chaque école fixe ses frais',
  'indicative': 'Grille de référence, adoptée librement',
  'commune': 'Grille commune imposée',
};

const explicationsPolitiques = <String, String>{
  'autonome': 'Chaque école fixe ses frais selon sa localité. Le réseau ne publie pas de grille.',
  'indicative': 'Le réseau publie une grille de référence. Chaque école la consulte et l’adopte si elle veut, '
      'puis reste libre d’ajuster.',
  'commune': 'Le réseau fixe les frais de toutes ses écoles. La grille s’applique aussitôt à chaque école '
      'membre, qui ne peut plus modifier ses tarifs elle-même.',
};

class NiveauReseau {
  const NiveauReseau({required this.id, required this.nom, this.ordre = 0});

  factory NiveauReseau.depuisJson(Map<String, dynamic> j) =>
      NiveauReseau(id: j['id'] as String, nom: j['nom'] as String? ?? '', ordre: (j['ordre'] as num?)?.toInt() ?? 0);

  final String id;
  final String nom;
  final int ordre;
}

class LigneGrilleReseau {
  const LigneGrilleReseau({
    required this.niveauId,
    required this.niveau,
    required this.montantAnnuel,
    this.fraisInscription = 0,
    this.tarifEcole,
  });

  factory LigneGrilleReseau.depuisJson(Map<String, dynamic> j) => LigneGrilleReseau(
        niveauId: j['niveau_id'] as String?,
        niveau: j['niveau'] as String? ?? 'Tous niveaux (par défaut)',
        montantAnnuel: (j['montant_annuel'] as num?)?.toDouble() ?? 0,
        fraisInscription: (j['frais_inscription'] as num?)?.toDouble() ?? 0,
        tarifEcole: (j['tarif_ecole'] as num?)?.toDouble(),
      );

  /// Null : tarif par défaut, pour tous les niveaux sans ligne propre.
  final String? niveauId;
  final String niveau;
  final double montantAnnuel;
  final double fraisInscription;

  /// Tarif actuel de l'école consultée, pour comparer (null si aucun).
  final double? tarifEcole;

  Map<String, dynamic> versParams() => {
        'niveau_id': niveauId,
        'montant_annuel': montantAnnuel,
        'frais_inscription': fraisInscription,
      };
}

class ReglesReseau {
  const ReglesReseau({
    required this.reseauId,
    this.deviseCode = 'GNF',
    this.politiqueFrais = 'autonome',
    this.transfertsOuverts = true,
    this.quitusRequis = true,
    this.validationReseau = false,
    this.inscriptionOfferte = true,
    this.dossierPartage = true,
    this.grille = const [],
    this.niveaux = const [],
  });

  factory ReglesReseau.depuisJson(Map<String, dynamic> j) => ReglesReseau(
        reseauId: j['reseau_id'] as String,
        deviseCode: j['devise_code'] as String? ?? 'GNF',
        politiqueFrais: j['politique_frais'] as String? ?? 'autonome',
        transfertsOuverts: j['transferts_ouverts'] as bool? ?? true,
        quitusRequis: j['quitus_requis'] as bool? ?? true,
        validationReseau: j['validation_reseau'] as bool? ?? false,
        inscriptionOfferte: j['inscription_offerte'] as bool? ?? true,
        dossierPartage: j['dossier_partage'] as bool? ?? true,
        grille: [
          for (final l in (j['grille'] as List?) ?? const [])
            LigneGrilleReseau.depuisJson((l as Map).cast<String, dynamic>()),
        ],
        niveaux: [
          for (final n in (j['niveaux'] as List?) ?? const []) NiveauReseau.depuisJson((n as Map).cast<String, dynamic>()),
        ],
      );

  final String reseauId;
  final String deviseCode;
  final String politiqueFrais;
  final bool transfertsOuverts;
  final bool quitusRequis;
  final bool validationReseau;
  final bool inscriptionOfferte;
  final bool dossierPartage;
  final List<LigneGrilleReseau> grille;
  final List<NiveauReseau> niveaux;

  bool get grilleCommune => politiqueFrais == 'commune';

  ReglesReseau copierAvec({
    String? politiqueFrais,
    bool? transfertsOuverts,
    bool? quitusRequis,
    bool? validationReseau,
    bool? inscriptionOfferte,
    bool? dossierPartage,
  }) =>
      ReglesReseau(
        reseauId: reseauId,
        deviseCode: deviseCode,
        politiqueFrais: politiqueFrais ?? this.politiqueFrais,
        transfertsOuverts: transfertsOuverts ?? this.transfertsOuverts,
        quitusRequis: quitusRequis ?? this.quitusRequis,
        validationReseau: validationReseau ?? this.validationReseau,
        inscriptionOfferte: inscriptionOfferte ?? this.inscriptionOfferte,
        dossierPartage: dossierPartage ?? this.dossierPartage,
        grille: grille,
        niveaux: niveaux,
      );

  /// Les conditions de transfert en phrases, pour les écoles.
  List<String> get conditionsTransfert => !transfertsOuverts
      ? const ['Les transferts entre écoles du réseau sont fermés.']
      : [
          quitusRequis
              ? 'Les frais de l’année doivent être soldés avant le départ.'
              : 'Un élève peut partir même avec un solde dû (il reste dû à l’école de départ).',
          validationReseau
              ? 'La Direction Générale valide chaque transfert.'
              : 'Pas de validation du réseau : l’école d’accueil décide.',
          inscriptionOfferte
              ? 'Les frais d’inscription sont offerts dans l’école d’accueil.'
              : 'L’école d’accueil demande ses frais d’inscription.',
          dossierPartage
              ? 'Le dossier (classe, assiduité, famille) suit l’élève.'
              : 'Le dossier n’est pas transmis : seule l’identité suit l’élève.',
        ];
}

const statutsTransfert = <String, String>{
  'a_valider_reseau': 'À valider par le réseau',
  'en_attente_accueil': 'En attente de l’école d’accueil',
  'transfere': 'Transféré',
  'refuse': 'Refusé',
  'annule': 'Annulé',
};

class TransfertReseau {
  const TransfertReseau({
    required this.id,
    required this.statut,
    required this.eleve,
    required this.origine,
    required this.destination,
    this.reseauId,
    this.motif = '',
    this.sens,
    this.niveau,
    this.origineId,
    this.destinationId,
    this.soldeAuDepart,
    this.inscriptionOfferte = false,
    this.dossier,
    this.demandeLe,
    this.motifRefus,
    this.refusePar,
    this.enAttenteEnvoi = false,
  });

  factory TransfertReseau.depuisJson(Map<String, dynamic> j) => TransfertReseau(
        id: j['id'] as String,
        reseauId: j['reseau_id'] as String?,
        statut: j['statut'] as String? ?? 'en_attente_accueil',
        motif: j['motif'] as String? ?? '',
        sens: j['sens'] as String?,
        eleve: j['eleve'] as String? ?? '',
        niveau: j['niveau'] as String?,
        origineId: j['origine_id'] as String?,
        origine: j['origine'] as String? ?? '',
        destinationId: j['destination_id'] as String?,
        destination: j['destination'] as String? ?? '',
        soldeAuDepart: (j['solde_au_depart'] as num?)?.toDouble(),
        inscriptionOfferte: j['inscription_offerte'] as bool? ?? false,
        dossier: (j['dossier'] as Map?)?.cast<String, dynamic>(),
        demandeLe: DateTime.tryParse(j['demande_le'] as String? ?? '')?.toLocal(),
        motifRefus: j['motif_refus'] as String?,
        refusePar: j['refuse_par'] as String?,
      );

  final String id;
  final String? reseauId;
  final String statut;
  final String motif;

  /// `depart` ou `arrivee` vu d'une école ; null vu du réseau.
  final String? sens;
  final String eleve;
  final String? niveau;
  final String? origineId;
  final String origine;
  final String? destinationId;
  final String destination;
  final double? soldeAuDepart;
  final bool inscriptionOfferte;
  final Map<String, dynamic>? dossier;
  final DateTime? demandeLe;
  final String? motifRefus;
  final String? refusePar;

  /// Saisi sans réseau, pas encore reçu par le serveur.
  final bool enAttenteEnvoi;

  bool get enCours => statut == 'a_valider_reseau' || statut == 'en_attente_accueil';

  String get libelleStatut {
    if (enAttenteEnvoi) return 'En attente d’envoi';
    final base = statutsTransfert[statut] ?? statut;
    if (statut == 'refuse' && refusePar != null) {
      return refusePar == 'reseau' ? 'Refusé par le réseau' : 'Refusé par l’école d’accueil';
    }
    return base;
  }

  TransfertReseau avecStatut(String nouveau, {bool enAttenteEnvoi = false, String? motifRefus, String? refusePar}) =>
      TransfertReseau(
        id: id,
        reseauId: reseauId,
        statut: nouveau,
        motif: motif,
        sens: sens,
        eleve: eleve,
        niveau: niveau,
        origineId: origineId,
        origine: origine,
        destinationId: destinationId,
        destination: destination,
        soldeAuDepart: soldeAuDepart,
        inscriptionOfferte: inscriptionOfferte,
        dossier: dossier,
        demandeLe: demandeLe,
        motifRefus: motifRefus ?? this.motifRefus,
        refusePar: refusePar ?? this.refusePar,
        enAttenteEnvoi: enAttenteEnvoi,
      );
}

class DestinationTransfert {
  const DestinationTransfert({
    required this.etablissementId,
    required this.nom,
    required this.reseau,
    this.ville,
    this.transfertsOuverts = true,
    this.quitusRequis = true,
    this.validationReseau = false,
  });

  factory DestinationTransfert.depuisJson(Map<String, dynamic> j) => DestinationTransfert(
        etablissementId: j['etablissement_id'] as String,
        nom: j['nom'] as String? ?? '',
        ville: j['ville'] as String?,
        reseau: j['reseau'] as String? ?? '',
        transfertsOuverts: j['transferts_ouverts'] as bool? ?? true,
        quitusRequis: j['quitus_requis'] as bool? ?? true,
        validationReseau: j['validation_reseau'] as bool? ?? false,
      );

  final String etablissementId;
  final String nom;
  final String? ville;
  final String reseau;
  final bool transfertsOuverts;
  final bool quitusRequis;
  final bool validationReseau;
}

class EleveTransferable {
  const EleveTransferable({
    required this.ficheId,
    required this.nom,
    required this.prenom,
    this.classe,
    this.matricule,
    this.solde = 0,
    this.enTransfert = false,
  });

  factory EleveTransferable.depuisJson(Map<String, dynamic> j) => EleveTransferable(
        ficheId: j['fiche_id'] as String,
        nom: j['nom'] as String? ?? '',
        prenom: j['prenom'] as String? ?? '',
        classe: j['classe'] as String?,
        matricule: j['matricule'] as String?,
        solde: (j['solde'] as num?)?.toDouble() ?? 0,
        enTransfert: j['en_transfert'] as bool? ?? false,
      );

  final String ficheId;
  final String nom;
  final String prenom;
  final String? classe;
  final String? matricule;
  final double solde;
  final bool enTransfert;

  String get nomComplet => '$prenom $nom';
}

class ClasseAccueil {
  const ClasseAccueil({required this.classeId, required this.nom, this.memeNiveau = false, this.capacite, this.effectif = 0});

  factory ClasseAccueil.depuisJson(Map<String, dynamic> j) => ClasseAccueil(
        classeId: j['classe_id'] as String,
        nom: j['nom'] as String? ?? '',
        memeNiveau: j['meme_niveau'] as bool? ?? false,
        capacite: (j['capacite'] as num?)?.toInt(),
        effectif: (j['effectif'] as num?)?.toInt() ?? 0,
      );

  final String classeId;
  final String nom;
  final bool memeNiveau;
  final int? capacite;
  final int effectif;

  bool get complete => capacite != null && effectif >= capacite!;
}

/// Port des règles et transferts (implémenté par Supabase, simulé en test).
abstract interface class TransfertsReseauRepository {
  Future<ReglesReseau> regles(String reseauId, {String? etablissementId});

  /// Règles de la Direction Générale (en ligne : effet immédiat sur les
  /// écoles, on doit voir tout de suite si c'est passé).
  Future<ReglesReseau> parametrer(ReglesReseau regles);
  Future<void> enregistrerGrille(String reseauId, List<LigneGrilleReseau> lignes);

  /// Applique la grille : à tout le réseau ([etablissementId] null) ou à
  /// une école qui l'adopte. Renvoie le nombre d'écoles mises à jour.
  Future<int> appliquerGrille(String reseauId, {String? etablissementId});

  Future<List<TransfertReseau>> transferts({String? reseauId, String? etablissementId});
  Future<List<DestinationTransfert>> destinations(String etablissementId);
  Future<List<EleveTransferable>> elevesTransferables(String etablissementId, {String texte = ''});
  Future<List<ClasseAccueil>> classesAccueil(String transfertId);

  /// Les gestes suivants marchent sans réseau : gardés avec leur clé et
  /// envoyés au retour. `true` si le serveur les a reçus tout de suite.
  Future<bool> demander({
    required String etablissementId,
    required EleveTransferable eleve,
    required DestinationTransfert destination,
    required String motif,
  });
  Future<bool> valider({required String transfertId, required bool accorder, String? motif});
  Future<bool> repondre({required String transfertId, required bool accepter, String? classeId, String? motif});
  Future<void> annuler(String transfertId);
}
