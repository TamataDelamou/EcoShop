import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_chat_ia_repository.dart';
import '../domain/chat_ia_repository.dart';

/// Port du chat IA — toujours réseau direct, voir la doc de
/// [ChatIaRepository] : pas de décorateur de cache/file hors-ligne (M16,
/// sous-livrable 3/7).
final chatIaRepositoryProvider = Provider<ChatIaRepository>((ref) {
  return SupabaseChatIaRepository(ref.watch(supabaseClientProvider));
});
