/// Configuration d'environnement — aucune clé en dur dans le code (ch. 34.1).
///
/// Les valeurs sont fournies à la compilation :
/// `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...`
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Identifiant client OAuth « Application Web » de Google (console Google
  /// Cloud du projet Firebase). Vide : le bouton Google n'est pas proposé.
  static const String googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Identifiant client OAuth iOS (seulement pour une future version iPhone).
  static const String googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Connexion par code SMS : suspendue (REG-16, coût d'un SMS par
  /// connexion). `--dart-define=CONNEXION_TELEPHONE=true` la réaffiche.
  static const bool connexionTelephone = bool.fromEnvironment('CONNEXION_TELEPHONE');

  /// Le client Supabase ne peut être initialisé que si les deux valeurs sont
  /// fournies (évite une initialisation silencieuse avec des valeurs vides).
  static bool get estConfigure =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
