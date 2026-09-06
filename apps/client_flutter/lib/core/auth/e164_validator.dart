/// Normalisation E.164 des numéros de téléphone (cahier v4.1, ch. 5.4.1).
///
/// Le numéro transmis à `signInWithOtp()`/`verifyOtp()` doit être pré-normalisé
/// côté client, jamais par concaténation ad hoc au moment de l'appel.
abstract final class Validators {
  static final RegExp _nonChiffres = RegExp(r'\D');
  static final RegExp _e164 = RegExp(r'^\+[1-9]\d{6,14}$');

  /// Normalise à partir d'un indicatif pays et d'un numéro local.
  ///
  /// Ex. : `normalizeE164('+224', '620 00 00 00')` → `+224620000000`.
  /// Retourne `null` si le résultat n'est pas un E.164 valide.
  static String? normalizeE164({
    required String indicatifPays,
    required String numeroLocal,
  }) {
    final indicatif = indicatifPays.replaceAll(_nonChiffres, '');
    final local = numeroLocal.replaceAll(_nonChiffres, '');
    if (indicatif.isEmpty || local.isEmpty) return null;
    return _e164.hasMatch('+$indicatif$local') ? '+$indicatif$local' : null;
  }

  /// Indique si une chaîne est déjà un numéro E.164 valide.
  static bool estE164(String valeur) => _e164.hasMatch(valeur.trim());
}
