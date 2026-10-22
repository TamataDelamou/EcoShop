/// Numéro de téléphone du compte (REG-16).
///
/// On se connecte par e-mail ou Google ; le numéro complète le profil. Tant
/// que personne ne l'a vérifié, il reste « déclaré » : l'école s'en sert pour
/// joindre la famille, mais il ne donne aucun droit (accepter une invitation
/// adressée à ce numéro, par exemple). L'école le confirme en présence de la
/// personne.
class TelephoneProfil {
  const TelephoneProfil({
    required this.numero,
    this.verifie = false,
    this.enAttenteEnvoi = false,
  });

  factory TelephoneProfil.depuisJson(Map<String, dynamic> json) => TelephoneProfil(
        numero: (json['telephone'] ?? json['numero']) as String,
        verifie: json['verifie'] as bool? ?? false,
        enAttenteEnvoi: json['en_attente_envoi'] as bool? ?? false,
      );

  /// Format E.164 (`+224620000000`).
  final String numero;
  final bool verifie;

  /// Saisi sans réseau : part au retour de la connexion.
  final bool enAttenteEnvoi;

  Map<String, dynamic> versJson() => {
        'numero': numero,
        'verifie': verifie,
        'en_attente_envoi': enAttenteEnvoi,
      };

  /// `+224 620 00 00 00` : indicatif, puis groupes de deux chiffres pour
  /// les numéros guinéens à 9 chiffres, sinon le numéro tel quel.
  String get lisible {
    if (numero.startsWith('+224') && numero.length == 13) {
      final local = numero.substring(4);
      return '+224 ${local.substring(0, 3)} ${local.substring(3, 5)} ${local.substring(5, 7)} ${local.substring(7)}';
    }
    return numero;
  }

  String get statut => enAttenteEnvoi
      ? 'En attente d’envoi'
      : verifie
          ? 'Confirmé'
          : 'À faire confirmer par l’école';
}

/// Personne de l'école dont le numéro n'est que déclaré : l'agent le
/// confirme quand la personne est devant lui (appel ou message de test).
class TelephoneAConfirmer {
  const TelephoneAConfirmer({
    required this.profilId,
    required this.telephone,
    this.prenom,
    this.nom,
    this.enfants,
  });

  factory TelephoneAConfirmer.depuisJson(Map<String, dynamic> json) => TelephoneAConfirmer(
        profilId: json['profile_id'] as String,
        telephone: json['telephone'] as String,
        prenom: json['prenom'] as String?,
        nom: json['nom'] as String?,
        enfants: json['enfants'] as String?,
      );

  final String profilId;
  final String telephone;
  final String? prenom;
  final String? nom;
  final String? enfants;

  String get nomAffiche {
    final parties = [prenom, nom].where((p) => p != null && p.isNotEmpty);
    return parties.isEmpty ? 'Compte sans nom' : parties.join(' ');
  }

  String get telephoneLisible => TelephoneProfil(numero: telephone).lisible;
}
