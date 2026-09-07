import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/db/cache_document_store.dart';
import '../../../../core/providers.dart';
import '../data/communication_locale_repository.dart';
import '../domain/entree_communication_locale.dart';

/// Port du **prototype local** — voir [CommunicationLocaleRepository] pour
/// le contexte (aucune persistance serveur, données propres à l'appareil).
final communicationLocaleRepositoryProvider = Provider<CommunicationLocaleRepository>((ref) {
  return CommunicationLocaleRepository(CacheDocumentStore(ref.watch(databaseProvider), 'communication_locale'));
});

/// Entrées locales d'un type donné (message, annonce, mot de liaison).
final entreesLocalesProvider = FutureProvider.family<List<EntreeCommunicationLocale>, TypeEntreeLocale>((ref, type) {
  return ref.watch(communicationLocaleRepositoryProvider).lister(type);
});

/// Construit une [EntreeCommunicationLocale] prête à être ajoutée localement.
EntreeCommunicationLocale construireEntreeLocale({
  required TypeEntreeLocale type,
  required String auteurId,
  required String auteurNom,
  required String destinataireLabel,
  String? titre,
  required String contenu,
  bool important = false,
  bool signalee = false,
}) {
  return EntreeCommunicationLocale(
    id: const Uuid().v4(),
    type: type,
    auteurId: auteurId,
    auteurNom: auteurNom,
    destinataireLabel: destinataireLabel,
    titre: titre,
    contenu: contenu,
    dateCreation: DateTime.now(),
    important: important,
    signalee: signalee,
  );
}
