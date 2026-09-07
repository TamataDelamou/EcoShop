/// Enums SQL de M9 (`canal_notification`, `statut_notification`,
/// `statut_envoi`, `frequence_notification`).
library;

enum CanalNotification {
  sms('sms'),
  whatsapp('whatsapp'),
  email('email'),
  push('push');

  const CanalNotification(this.code);
  final String code;

  static CanalNotification depuisCode(String? code) {
    for (final v in CanalNotification.values) {
      if (v.code == code) return v;
    }
    return CanalNotification.sms;
  }

  String get libelle => switch (this) {
        sms => 'SMS',
        whatsapp => 'WhatsApp',
        email => 'E-mail',
        push => 'Notification push',
      };
}

enum StatutNotification {
  enAttente('en_attente'),
  envoyee('envoyee'),
  lue('lue'),
  echouee('echouee'),
  annulee('annulee');

  const StatutNotification(this.code);
  final String code;

  static StatutNotification depuisCode(String? code) {
    for (final v in StatutNotification.values) {
      if (v.code == code) return v;
    }
    return StatutNotification.enAttente;
  }

  String get libelle => switch (this) {
        enAttente => 'En attente',
        envoyee => 'Envoyée',
        lue => 'Lue',
        echouee => 'Échouée',
        annulee => 'Annulée',
      };
}

enum StatutEnvoi {
  envoye('envoye'),
  echoue('echoue'),
  enRetry('en_retry');

  const StatutEnvoi(this.code);
  final String code;

  static StatutEnvoi depuisCode(String? code) {
    for (final v in StatutEnvoi.values) {
      if (v.code == code) return v;
    }
    return StatutEnvoi.envoye;
  }

  String get libelle => switch (this) {
        envoye => 'Envoyé',
        echoue => 'Échoué',
        enRetry => 'Nouvelle tentative',
      };
}

enum FrequenceNotification {
  immediat('immediat'),
  quotidien('quotidien'),
  hebdomadaire('hebdomadaire');

  const FrequenceNotification(this.code);
  final String code;

  static FrequenceNotification depuisCode(String? code) {
    for (final v in FrequenceNotification.values) {
      if (v.code == code) return v;
    }
    return FrequenceNotification.immediat;
  }

  String get libelle => switch (this) {
        immediat => 'Immédiat',
        quotidien => 'Résumé quotidien',
        hebdomadaire => 'Résumé hebdomadaire',
      };
}
