import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../communication/prototype/application/communication_locale_providers.dart';
import '../../inscription_en_ligne/application/inscription_en_ligne_providers.dart';
import '../../pointage/application/pointage_providers.dart';
import '../../push/application/push_providers.dart';
import '../../reseau/application/reseau_providers.dart';
import '../../transport/application/transport_providers.dart';

/// Déconnexion complète : ferme la session serveur **et** purge tout ce que
/// le prototype local de messagerie/annonces/cahier de liaison (M9) a écrit
/// sur l'appareil.
///
/// Patch de sécurité — le prototype local (`CommunicationLocaleRepository`)
/// stocke ses entrées sous une clé de cache unique non isolée par profil
/// (`CacheDocumentStore.cleUnique = 'global'`) : sans cette purge, un second
/// compte se connectant sur le même appareil (tablette d'établissement,
/// scénario courant) voit les messages du compte précédent, y compris quand
/// l'un des deux comptes est un mineur. `rafraichirSession()` seul ne
/// suffisait pas : il n'invalide que `profilProvider`/`ficheLieeProvider`/
/// `mesEtablissementsProvider`, jamais `entreesLocalesProvider` — et même
/// invalidé, ce provider aurait relu les mêmes lignes non purgées.
///
/// Ne touche à aucun autre domaine de cache local (`CacheEntries` des modules
/// métier M5+, `ReferentielCacheEntries`, `SyncQueueEntries`) : ces domaines
/// sont déjà correctement soumis aux RLS serveur à la prochaine
/// synchronisation et ne portent pas ce risque de fuite entre comptes —
/// périmètre de ce patch volontairement limité au prototype local concerné.
Future<void> _deconnecterEtPurgerDonneesLocales({
  required T Function<T>(ProviderListenable<T> provider) lire,
  required void Function(ProviderOrFamily provider) invalider,
}) async {
  // Notifications push : ce téléphone ne reçoit plus celles du compte
  // (tablette partagée, téléphone prêté). Avant la déconnexion, tant que le
  // serveur reconnaît encore le compte.
  try {
    await lire(servicePushProvider)?.detacher();
  } catch (_) {
    // Push indisponible : rien à détacher.
  }
  await lire(authRepositoryProvider).deconnecter();
  await lire(communicationLocaleRepositoryProvider).purgerTout();
  // Comptabilité gardée pour le hors connexion (REG-03 C7) : données des
  // donateurs, états, pièces — jamais visibles du compte suivant.
  try {
    await lire(lectureComptabiliteProvider).purger();
  } catch (_) {
    // Base locale indisponible : rien à purger.
  }
  // Inscriptions en ligne (REG-08) : dossiers d'élèves et de familles.
  try {
    await lire(lectureInscriptionsProvider).purger();
  } catch (_) {
    // Base locale indisponible : rien à purger.
  }
  // Réseaux d'établissements (M19) : tableaux de bord, circulaires.
  try {
    await lire(lectureReseauProvider).purger();
  } catch (_) {
    // Base locale indisponible : rien à purger.
  }
  // Transport (M18) : cartes des élèves du circuit, trajet en cours.
  try {
    await lire(lectureTransportProvider).purger();
  } catch (_) {
    // Base locale indisponible : rien à purger.
  }
  // Pointage (REG-09) : jetons des cartes et présence des élèves.
  try {
    await lire(lecturePointageProvider).purger();
  } catch (_) {
    // Base locale indisponible : rien à purger.
  }
  invalider(entreesLocalesProvider);
  invalider(profilProvider);
  invalider(ficheLieeProvider);
  invalider(mesEtablissementsProvider);
}

extension DeconnexionRef on Ref {
  Future<void> deconnecterEtPurgerDonneesLocales() =>
      _deconnecterEtPurgerDonneesLocales(lire: read, invalider: invalidate);
}

extension DeconnexionWidgetRef on WidgetRef {
  Future<void> deconnecterEtPurgerDonneesLocales() =>
      _deconnecterEtPurgerDonneesLocales(lire: read, invalider: invalidate);
}
