/// Configuration d'environnement — aucune clé en dur dans le code (ch. 34.1).
///
/// Les valeurs sont fournies à la compilation :
/// `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...`
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Le client Supabase ne peut être initialisé que si les deux valeurs sont
  /// fournies (évite une initialisation silencieuse avec des valeurs vides).
  static bool get estConfigure =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
