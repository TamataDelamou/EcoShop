/// Résultat de la RPC `verifications_reinscription` (M15quater) —
/// **informatif**, pas un blocage serveur absolu : l'écran de réinscription
/// affiche ces signaux avant confirmation, comme documenté côté source
/// (ecoshop_flutter affichait des alertes, sans refus systématique).
class VerificationsReinscription {
  const VerificationsReinscription({
    required this.impaye,
    required this.sanctionActive,
    required this.boursierPrecedent,
  });

  factory VerificationsReinscription.depuisJson(Map<String, dynamic> json) {
    return VerificationsReinscription(
      impaye: json['impaye'] as bool? ?? false,
      sanctionActive: json['sanction_active'] as bool? ?? false,
      boursierPrecedent: json['boursier_precedent'] as bool? ?? false,
    );
  }

  final bool impaye;
  final bool sanctionActive;
  final bool boursierPrecedent;

  bool get aDesAlertes => impaye || sanctionActive;
}
