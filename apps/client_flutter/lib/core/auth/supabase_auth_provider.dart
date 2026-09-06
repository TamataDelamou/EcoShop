import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Client Supabase unique, initialisé dans `main.dart` (ch. 5.4).
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Flux d'état d'authentification — la session est restaurée automatiquement
/// au démarrage tant que le jeton de rafraîchissement reste valide (ch. 5.7).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

/// Session courante (null si l'utilisateur n'est pas authentifié).
final sessionProvider = Provider<Session?>((ref) {
  return Supabase.instance.client.auth.currentSession;
});
