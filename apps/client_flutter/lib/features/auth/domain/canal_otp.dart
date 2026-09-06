/// Canaux de délivrance du code à usage unique (cahier v4.1, ch. 5.4).
///
/// Deux **entrées** authentifiables — téléphone et e-mail — et quatre
/// **canaux** de délivrance. L'entrée est ce qui devient l'identifiant
/// canonique ; le canal n'est qu'un moyen d'acheminement.
library;

/// Entrée authentifiable : ce qui identifie le compte.
enum TypeIdentifiant {
  telephone('telephone'),
  email('email');

  const TypeIdentifiant(this.code);

  /// Code tel que stocké dans `identifiants_comptes.type_identifiant`.
  final String code;
}

/// Canal d'acheminement du code.
enum CanalOtp {
  sms('sms', TypeIdentifiant.telephone),
  whatsapp('whatsapp', TypeIdentifiant.telephone),
  magicLink('magic_link', TypeIdentifiant.email),
  emailOtp('email_otp', TypeIdentifiant.email);

  const CanalOtp(this.code, this.entree);

  /// Code tel que stocké côté Postgres (`public.canal_otp`).
  final String code;

  /// Entrée que ce canal permet d'authentifier.
  final TypeIdentifiant entree;

  /// Un lien magique ouvre une session sans saisie de code : le parcours ne
  /// passe pas par l'écran de vérification.
  bool get demandeSaisieCode => this != CanalOtp.magicLink;

  /// Libellé affiché à l'utilisateur.
  String get libelle => switch (this) {
        CanalOtp.sms => 'SMS',
        CanalOtp.whatsapp => 'WhatsApp',
        CanalOtp.magicLink => 'Lien magique',
        CanalOtp.emailOtp => 'Code par e-mail',
      };

  /// Canaux disponibles pour une entrée donnée.
  static List<CanalOtp> pourEntree(TypeIdentifiant entree) =>
      CanalOtp.values.where((c) => c.entree == entree).toList(growable: false);

  static CanalOtp? depuisCode(String? code) {
    for (final canal in CanalOtp.values) {
      if (canal.code == code) return canal;
    }
    return null;
  }
}
