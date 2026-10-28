import '../../../core/auth/role_racine.dart';

/// Statut d'un compte (`public.statut_compte`).
enum StatutCompte {
  actif('actif'),
  suspendu('suspendu'),
  supprime('supprime');

  const StatutCompte(this.code);

  final String code;

  static StatutCompte depuisCode(String? code) {
    for (final statut in StatutCompte.values) {
      if (statut.code == code) return statut;
    }
    // Un statut inconnu est traité comme une suspension : en cas de divergence
    // entre le client et la base, on refuse l'accès plutôt que de l'accorder.
    return StatutCompte.suspendu;
  }
}

/// Projection cliente de `public.profiles`.
///
/// Cette classe est un **cache d'affichage**. Aucune décision d'autorisation ne
/// repose sur elle : le serveur revérifie chaque requête via RLS (ch. 34).
class Profil {
  const Profil({
    required this.id,
    required this.identifiantCanonique,
    required this.statutCompte,
    this.roleRacine,
    this.prenom,
    this.nom,
    this.etablissementActifId,
    this.identifiantEcoshop,
    this.inscriptionFinalisee = true,
    this.photoChemin,
  });

  factory Profil.depuisJson(Map<String, dynamic> json) {
    return Profil(
      id: json['id'] as String,
      identifiantCanonique: json['identifiant_canonique'] as String? ?? '',
      statutCompte: StatutCompte.depuisCode(json['statut_compte'] as String?),
      roleRacine: RoleRacine.depuisCode(json['role_racine'] as String?),
      prenom: json['prenom'] as String?,
      nom: json['nom'] as String?,
      etablissementActifId: json['etablissement_actif_id'] as String?,
      identifiantEcoshop: json['identifiant_ecoshop'] as String?,
      photoChemin: json['photo_chemin'] as String?,
      // Colonne absente (copie locale d'avant REG-18) : compte en service.
      inscriptionFinalisee:
          !json.containsKey('inscription_finalisee_le') || json['inscription_finalisee_le'] != null,
    );
  }

  final String id;
  final String identifiantCanonique;
  final StatutCompte statutCompte;

  /// Null tant que le rôle n'a pas été choisi (anti-élévation de privilège).
  final RoleRacine? roleRacine;

  final String? prenom;
  final String? nom;
  final String? etablissementActifId;

  /// Identifiant EcoShop (REG-18), attribué par le serveur : `EC-XXXX-XXC`.
  final String? identifiantEcoshop;

  /// Faux pour un compte jamais finalisé (REG-18) : nouveau compte, ou
  /// personnel invité qui n'a pas encore donné son nom.
  final bool inscriptionFinalisee;

  /// Photo de profil (REG-23) : chemin dans le bucket privé `photos-profils`.
  final String? photoChemin;

  /// Prénom ou nom manquant.
  bool get nomIncomplet => (prenom ?? '').trim().isEmpty || (nom ?? '').trim().isEmpty;

  /// Même forme que la ligne `profiles` lue par [Profil.depuisJson] (copie
  /// locale, REG-18).
  Map<String, dynamic> versJson() => {
        'id': id,
        'identifiant_canonique': identifiantCanonique,
        'statut_compte': statutCompte.code,
        'role_racine': roleRacine?.code,
        'prenom': prenom,
        'nom': nom,
        'etablissement_actif_id': etablissementActifId,
        'identifiant_ecoshop': identifiantEcoshop,
        'inscription_finalisee_le': inscriptionFinalisee ? 'oui' : null,
        'photo_chemin': photoChemin,
      };

  bool get roleDefini => roleRacine != null;

  /// Un élève doit revendiquer sa fiche scolaire pour accéder à sa scolarité.
  bool get exigeLiaisonFiche => roleRacine == RoleRacine.eleve;

  String get nomAffiche {
    final parties = [prenom, nom].where((p) => p != null && p.isNotEmpty);
    return parties.isEmpty ? identifiantCanonique : parties.join(' ');
  }
}
