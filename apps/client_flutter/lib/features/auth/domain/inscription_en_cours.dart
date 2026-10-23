import '../../../core/auth/role_racine.dart';

/// Espace choisi à la création d'un compte (REG-18, partie B).
enum EspaceInscription {
  eleve('eleve'),

  /// Aussi le client de la boutique : un compte parent sans enfant lié
  /// achète sur la marketplace sans établissement.
  parent('parent'),

  /// Représentant d'un établissement (ou d'un réseau) : aucun rôle choisi
  /// ici ; la demande d'ouverture (REG-04) est validée par Global Service
  /// Groupe, qui attribue alors le rôle Direction.
  etablissement('etablissement');

  const EspaceInscription(this.code);
  final String code;

  static EspaceInscription? depuisCode(String? code) {
    for (final e in EspaceInscription.values) {
      if (e.code == code) return e;
    }
    return null;
  }

  /// Rôle racine fixé par `finaliser_inscription` (null : aucun).
  RoleRacine? get role => switch (this) {
        EspaceInscription.eleve => RoleRacine.eleve,
        EspaceInscription.parent => RoleRacine.parent,
        EspaceInscription.etablissement => null,
      };
}

/// Saisies faites avant la vérification de l'adresse, gardées sur le
/// téléphone : le compte n'existe qu'après la vérification, et une
/// inscription abandonnée ne laisse rien dans la base. Appliquées ensuite par
/// `finaliser_inscription`, jamais à un compte existant.
class InscriptionEnCours {
  const InscriptionEnCours({required this.espace, this.prenom, this.nom, required this.creeLe});

  factory InscriptionEnCours.depuisJson(Map<String, dynamic> json) => InscriptionEnCours(
        espace: EspaceInscription.depuisCode(json['espace'] as String?) ?? EspaceInscription.parent,
        prenom: json['prenom'] as String?,
        nom: json['nom'] as String?,
        creeLe: DateTime.tryParse(json['cree_le'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final EspaceInscription espace;

  /// Null quand la personne a choisi Google sans saisir son nom : il est
  /// pré-rempli depuis Google et confirmé après la vérification.
  final String? prenom;
  final String? nom;
  final DateTime creeLe;

  /// Au-delà, la saisie est oubliée (le serveur supprime de son côté les
  /// comptes jamais vérifiés au bout de 24 h).
  static const validite = Duration(hours: 24);

  bool estValide(DateTime maintenant) => maintenant.difference(creeLe) < validite;

  bool get nomComplet => (prenom ?? '').trim().isNotEmpty && (nom ?? '').trim().isNotEmpty;

  Map<String, dynamic> versJson() => {
        'espace': espace.code,
        'prenom': prenom,
        'nom': nom,
        'cree_le': creeLe.toIso8601String(),
      };
}

/// Règle du serveur (`finaliser_inscription`, `definir_mon_nom`) reprise sur
/// le téléphone pour un message immédiat : non vide, 80 caractères au plus,
/// ni chiffre ni @.
String? verifierNom(String? valeur) {
  final v = (valeur ?? '').trim();
  if (v.isEmpty) return 'Obligatoire.';
  if (v.length > 80) return '80 caractères au plus.';
  if (RegExp(r'[@0-9]').hasMatch(v)) return 'Sans chiffre ni @.';
  return null;
}

/// Prénom et nom fournis par Google (métadonnées de la session), pour
/// pré-remplir la confirmation.
({String? prenom, String? nom}) nomsDepuisGoogle(Map<String, dynamic>? meta) {
  if (meta == null) return (prenom: null, nom: null);
  String? texte(String cle) {
    final v = meta[cle];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  final prenom = texte('given_name');
  final nom = texte('family_name');
  if (prenom != null || nom != null) return (prenom: prenom, nom: nom);
  final complet = texte('full_name') ?? texte('name');
  if (complet == null) return (prenom: null, nom: null);
  final mots = complet.split(RegExp(r'\s+'));
  if (mots.length == 1) return (prenom: mots.first, nom: null);
  return (prenom: mots.first, nom: mots.skip(1).join(' '));
}
