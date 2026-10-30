/// Abonnement Premium d'un élève (REG-36). Payé par l'élève ou un parent
/// (mobile money via CinetPay), sans prélèvement automatique : comme les
/// « forfaits prépayés » de Google Play, on prolonge avant l'échéance, et le
/// temps déjà payé n'est jamais perdu (la nouvelle période part de la fin de
/// la période en cours).
enum FormulePremium {
  mensuel('mensuel', 'Un mois'),
  annuel('annuel', 'Une année');

  const FormulePremium(this.code, this.libelle);

  final String code;
  final String libelle;

  static FormulePremium? depuisCode(String? code) {
    for (final f in values) {
      if (f.code == code) return f;
    }
    return null;
  }
}

/// Jours avant l'échéance où l'application rappelle de prolonger.
const joursRappelPremium = 7;

class EtatPremium {
  const EtatPremium({this.expireLe, this.formule, required this.tarifMensuel, required this.tarifAnnuel, this.devise = 'GNF', this.quotaGratuit});

  /// Fin de la période payée ; null : jamais abonné.
  final DateTime? expireLe;
  final FormulePremium? formule;
  final num? tarifMensuel;
  final num? tarifAnnuel;
  final String devise;

  /// Questions au Tuteur IA par mois sans Premium (levé avec Premium).
  final int? quotaGratuit;

  bool actifLe(DateTime maintenant) => expireLe != null && expireLe!.isAfter(maintenant);

  /// Jours entiers restants (0 le dernier jour) ; null si inactif.
  int? joursRestants(DateTime maintenant) {
    if (!actifLe(maintenant)) return null;
    return expireLe!.difference(maintenant).inDays;
  }

  /// Faut-il rappeler de prolonger ?
  bool aRappeler(DateTime maintenant) {
    final j = joursRestants(maintenant);
    return j != null && j < joursRappelPremium;
  }

  num? tarif(FormulePremium f) => f == FormulePremium.mensuel ? tarifMensuel : tarifAnnuel;

  /// Économie de l'année par rapport à douze mois, en pourcentage entier.
  int? economieAnnuelle() {
    final m = tarifMensuel, a = tarifAnnuel;
    if (m == null || a == null || m <= 0) return null;
    final p = ((1 - a / (m * 12)) * 100).round();
    return p > 0 ? p : null;
  }

  /// Fin de la période si l'on paie maintenant (même calcul que le serveur).
  DateTime finSiPaye(FormulePremium f, DateTime maintenant) {
    final depart = actifLe(maintenant) ? expireLe! : maintenant;
    return f == FormulePremium.mensuel
        ? DateTime(depart.year, depart.month + 1, depart.day, depart.hour, depart.minute)
        : DateTime(depart.year + 1, depart.month, depart.day, depart.hour, depart.minute);
  }
}

class ErreurPremium implements Exception {
  const ErreurPremium(this.code);

  final String code;

  String get message => switch (code) {
        'HORS_LIGNE' => 'Pas de réseau : le paiement se fait en ligne. Réessayez quand le réseau revient.',
        'CINETPAY_NON_CONFIGURE' => 'Le paiement en ligne n’est pas encore ouvert. Réessayez plus tard.',
        'ACCES_REFUSE' || 'PERMISSION_REFUSEE' => 'Seuls l’élève et ses parents reliés peuvent payer cet abonnement.',
        'TARIF_NON_CONFIGURE' || 'PARAMETRES_ABONNEMENT_MANQUANTS' => 'Le prix de l’abonnement n’est pas encore fixé.',
        'URL_PAIEMENT_INDISPONIBLE' || 'erreur_cinetpay' => 'Le service de paiement ne répond pas. Réessayez dans un instant.',
        _ => 'Paiement impossible pour le moment. Réessayez.',
      };

  @override
  String toString() => code;
}
