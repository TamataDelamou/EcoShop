import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../data/firebase_messagerie_push.dart';
import '../domain/messagerie_push.dart';
import 'service_push.dart';

/// `null` sur PC, ou tant que Firebase n'est pas configuré sur le téléphone.
final messageriePushProvider = Provider<MessageriePush?>((ref) {
  return InitialisationPush.disponible ? FirebaseMessageriePush() : null;
});

final servicePushProvider = Provider<ServicePush?>((ref) {
  final messagerie = ref.watch(messageriePushProvider);
  if (messagerie == null) return null;
  final client = ref.watch(supabaseClientProvider);
  return ServicePush(
    messagerie: messagerie,
    memoire: CacheDocumentStore(ref.watch(databaseProvider), 'push'),
    plateforme: InitialisationPush.plateforme,
    enregistrer: (identifiant, plateforme) => client.rpc<dynamic>(
      'enregistrer_jeton_push',
      params: {'p_jeton': identifiant, 'p_plateforme': plateforme},
    ),
    retirer: (identifiant) => client.rpc<dynamic>('retirer_jeton_push', params: {'p_jeton': identifiant}),
  );
});
