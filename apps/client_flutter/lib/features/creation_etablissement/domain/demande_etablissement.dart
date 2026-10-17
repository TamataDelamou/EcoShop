/// Statut d'une demande de création d'établissement (REG-04, cahier §5.3).
enum StatutDemandeEtablissement {
  enAttente('en_attente'),
  acceptee('acceptee'),
  refusee('refusee');

  const StatutDemandeEtablissement(this.code);

  final String code;

  static StatutDemandeEtablissement depuisCode(String? code) => StatutDemandeEtablissement.values.firstWhere(
        (s) => s.code == code,
        orElse: () => StatutDemandeEtablissement.enAttente,
      );
}

/// Demande vue par son auteur (le fondateur).
class DemandeEtablissement {
  const DemandeEtablissement({
    required this.id,
    required this.nomEtablissement,
    required this.paysCode,
    required this.ville,
    required this.statut,
    required this.creeLe,
    this.motifRefus,
    this.etablissementId,
  });

  factory DemandeEtablissement.depuisJson(Map<String, dynamic> json) => DemandeEtablissement(
        id: json['id'] as String,
        nomEtablissement: json['nom_etablissement'] as String,
        paysCode: json['pays_code'] as String,
        ville: json['ville'] as String,
        statut: StatutDemandeEtablissement.depuisCode(json['statut'] as String?),
        creeLe: DateTime.parse(json['created_at'] as String),
        motifRefus: json['motif_refus'] as String?,
        etablissementId: json['etablissement_id'] as String?,
      );

  final String id;
  final String nomEtablissement;
  final String paysCode;
  final String ville;
  final StatutDemandeEtablissement statut;
  final DateTime creeLe;
  final String? motifRefus;
  final String? etablissementId;
}

/// Demande telle que la voit l'administrateur GSG (avec le demandeur).
class DemandeATraiter {
  const DemandeATraiter({
    required this.id,
    required this.nomEtablissement,
    required this.paysCode,
    required this.ville,
    required this.telephone,
    required this.creeLe,
    this.paysNom,
    this.adresse,
    this.email,
    this.effectifEstime,
    this.numeroAutorisation,
    this.message,
    this.demandeurNom,
    this.demandeurIdentifiant,
  });

  factory DemandeATraiter.depuisJson(Map<String, dynamic> json) => DemandeATraiter(
        id: json['id'] as String,
        nomEtablissement: json['nom_etablissement'] as String,
        paysCode: json['pays_code'] as String,
        paysNom: json['pays_nom'] as String?,
        ville: json['ville'] as String,
        adresse: json['adresse'] as String?,
        telephone: json['telephone'] as String,
        email: json['email'] as String?,
        effectifEstime: (json['effectif_estime'] as num?)?.toInt(),
        numeroAutorisation: json['numero_autorisation'] as String?,
        message: json['message'] as String?,
        creeLe: DateTime.parse(json['created_at'] as String),
        demandeurNom: json['demandeur_nom'] as String?,
        demandeurIdentifiant: json['demandeur_identifiant'] as String?,
      );

  final String id;
  final String nomEtablissement;
  final String paysCode;
  final String? paysNom;
  final String ville;
  final String? adresse;
  final String telephone;
  final String? email;
  final int? effectifEstime;
  final String? numeroAutorisation;
  final String? message;
  final DateTime creeLe;
  final String? demandeurNom;
  final String? demandeurIdentifiant;
}

/// Saisie du formulaire de demande.
class SaisieDemandeEtablissement {
  const SaisieDemandeEtablissement({
    required this.nom,
    required this.paysCode,
    required this.ville,
    required this.telephone,
    this.adresse,
    this.email,
    this.effectifEstime,
    this.numeroAutorisation,
    this.message,
  });

  final String nom;
  final String paysCode;
  final String ville;
  final String telephone;
  final String? adresse;
  final String? email;
  final int? effectifEstime;
  final String? numeroAutorisation;
  final String? message;
}

/// Port du parcours de création d'établissement — réseau direct uniquement.
abstract interface class CreationEtablissementRepository {
  Future<String> soumettre(SaisieDemandeEtablissement saisie);

  /// Dernière demande du compte connecté (null s'il n'en a jamais fait).
  Future<DemandeEtablissement?> maDerniereDemande();

  /// File du backoffice — administrateur GSG uniquement.
  Future<List<DemandeATraiter>> demandesATraiter();

  Future<void> traiter({required String demandeId, required bool accepter, String? motif});
}

class ErreurCreationEtablissement implements Exception {
  const ErreurCreationEtablissement(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'ROLE_INCOMPATIBLE' =>
          'Ce compte a déjà un rôle (élève, parent, enseignant…) : créez la demande avec un nouveau compte.',
        'DEMANDE_DEJA_EN_COURS' => 'Une demande est déjà en cours d’examen pour ce compte.',
        'PAYS_INCONNU' => 'Ce pays n’est pas encore ouvert sur EcoShop.',
        'DEMANDE_INVALIDE' => 'Certaines informations sont invalides. Vérifiez le téléphone et le courriel.',
        'MOTIF_REQUIS' => 'Indiquez le motif du refus : il sera communiqué au demandeur.',
        'DEMANDE_DEJA_TRAITEE' => 'Cette demande a déjà été traitée.',
        'ACCES_REFUSE' => 'Action réservée à l’administration Global Service Groupe.',
        _ => 'Opération impossible pour le moment. Vérifiez votre connexion et réessayez.',
      };

  @override
  String toString() => 'ErreurCreationEtablissement($code)';
}
