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
    this.gsgId,
    this.prenom,
    this.nom,
    this.etablissementActifId,
  });

  factory Profil.depuisJson(Map<String, dynamic> json) {
    return Profil(
      id: json['id'] as String,
      identifiantCanonique: json['identifiant_canonique'] as String? ?? '',
      statutCompte: StatutCompte.depuisCode(json['statut_compte'] as String?),
      roleRacine: RoleRacine.depuisCode(json['role_racine'] as String?),
      gsgId: json['gsg_id'] as String?,
      prenom: json['prenom'] as String?,
      nom: json['nom'] as String?,
      etablissementActifId: json['etablissement_actif_id'] as String?,
    );
  }

  final String id;
  final String identifiantCanonique;
  final StatutCompte statutCompte;

  /// Null tant que le rôle n'a pas été choisi (anti-élévation de privilège).
  final RoleRacine? roleRacine;

  /// Identité fédérée GSG ID — additive, souvent nulle.
  final String? gsgId;

  final String? prenom;
  final String? nom;
  final String? etablissementActifId;

  bool get roleDefini => roleRacine != null;

  /// Un élève doit revendiquer sa fiche scolaire pour accéder à sa scolarité.
  bool get exigeLiaisonFiche => roleRacine == RoleRacine.eleve;

  String get nomAffiche {
    final parties = [prenom, nom].where((p) => p != null && p.isNotEmpty);
    return parties.isEmpty ? identifiantCanonique : parties.join(' ');
  }
}
