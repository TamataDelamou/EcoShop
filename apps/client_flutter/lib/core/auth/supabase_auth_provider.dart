import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Client Supabase unique, initialisé dans `main.dart` (ch. 5.4).
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Flux d'état d'authentification — la session est restaurée automatiquement
/// au démarrage tant que le jeton de rafraîchissement reste valide (ch. 5.7).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// Session courante (null si l'utilisateur n'est pas authentifié).
///
/// Relue à chaque événement Auth : sans cette dépendance, la valeur lue au
/// premier affichage restait figée — après une connexion Google, l'écran ne
/// quittait pas la connexion tant que l'application n'était pas relancée,
/// et après une déconnexion il attendait un profil qui ne viendrait plus.
final sessionProvider = Provider<Session?>((ref) {
  final auth = ref.watch(supabaseClientProvider).auth;
  ref.watch(authStateProvider);
  return auth.currentSession;
});
