import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/coquille/application/session_logout.dart';

import '../../support/faux_auth_repository.dart';

/// Provider-piège : capture le [Ref] du conteneur pour appeler les
/// extensions `Ref`/`WidgetRef` (`deconnecterEtPurgerDonneesLocales`) depuis
/// un test qui ne monte aucun widget.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late FauxAuthRepository auth;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    auth = FauxAuthRepository();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      authRepositoryProvider.overrideWithValue(auth),
    ]);
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  test(
      'patch de sécurité M9 — les messages laissés par l\'ancien prototype local '
      'sont effacés à la déconnexion', () async {
    final ancien = CacheDocumentStore(db, 'communication_locale');
    await ancien.ecrireListe('message', [
      {'id': 'e1', 'contenu': 'Message privé du compte A'},
    ]);

    final ref = container.read(_refProvider);
    await ref.deconnecterEtPurgerDonneesLocales();

    expect(auth.appels, contains('deconnecter'));
    expect(await ancien.lireListe('message'), isNull,
        reason: 'le compte suivant ne doit rien voir du précédent');
  });

  test('la purge est scopée au domaine communication_locale (n\'efface pas les autres caches)', () async {
    final autreDomaine = CacheDocumentStore(db, 'un_autre_module');
    await autreDomaine.ecrireListe('sondage', [
      {'id': '1'}
    ]);

    final ref = container.read(_refProvider);
    await ref.deconnecterEtPurgerDonneesLocales();

    final toujoursLa = await autreDomaine.lireListe('sondage');
    expect(toujoursLa, hasLength(1),
        reason: 'seul le domaine communication_locale doit être purgé à la déconnexion');
  });
}
