import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/coquille/application/session_logout.dart';
import 'package:ecoshop_client/features/communication/prototype/application/communication_locale_providers.dart';
import 'package:ecoshop_client/features/communication/prototype/domain/entree_communication_locale.dart';

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
      'patch de sécurité M9 — déconnexion compte A puis connexion compte B '
      'sur le même appareil : B ne voit rien de A', () async {
    // --- Compte A utilise la messagerie locale ---
    final entreeA = construireEntreeLocale(
      type: TypeEntreeLocale.message,
      auteurId: 'compte-a',
      auteurNom: 'Élève A',
      destinataireLabel: 'Classe 6e A',
      contenu: 'Message privé du compte A',
    );
    await container.read(communicationLocaleRepositoryProvider).ajouter(entreeA);
    // Reflète le geste réel de l'écran après un ajout (voir
    // ecran_messagerie_prototype.dart) : invalider la famille pour la relire.
    container.invalidate(entreesLocalesProvider(TypeEntreeLocale.message));

    // Le message est bien lisible tant que le compte A est connecté.
    final vuParA =
        await container.read(entreesLocalesProvider(TypeEntreeLocale.message).future);
    expect(vuParA, hasLength(1));
    expect(vuParA.single.contenu, 'Message privé du compte A');

    // --- Déconnexion du compte A ---
    final ref = container.read(_refProvider);
    await ref.deconnecterEtPurgerDonneesLocales();

    expect(auth.appels, contains('deconnecter'));

    // La purge doit avoir vidé le stockage local avant qu'un autre compte ne
    // se connecte sur le même appareil — pas seulement invalidé le cache
    // Riverpod en mémoire.
    final apresDeconnexion =
        await container.read(entreesLocalesProvider(TypeEntreeLocale.message).future);
    expect(apresDeconnexion, isEmpty,
        reason: 'le prototype local doit être vidé à la déconnexion');

    // --- Compte B se connecte sur le même appareil (même base Drift) ---
    final entreeB = construireEntreeLocale(
      type: TypeEntreeLocale.message,
      auteurId: 'compte-b',
      auteurNom: 'Élève B',
      destinataireLabel: 'Classe 5e B',
      contenu: 'Message du compte B',
    );
    await container.read(communicationLocaleRepositoryProvider).ajouter(entreeB);
    container.invalidate(entreesLocalesProvider(TypeEntreeLocale.message));

    final vuParB =
        await container.read(entreesLocalesProvider(TypeEntreeLocale.message).future);
    expect(vuParB, hasLength(1),
        reason: 'B ne doit voir que son propre message, jamais celui de A');
    expect(vuParB.single.contenu, 'Message du compte B');
    expect(vuParB.map((e) => e.contenu), isNot(contains('Message privé du compte A')));
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
