import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/app_database.dart';

/// Base locale Drift, ouverte à la première utilisation.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Flux de connectivité réseau (déclenche la resynchronisation proactive).
/// État lu tout de suite au lancement, puis chaque changement. Une panne du
/// module natif ne lève jamais : l'état reste simplement inconnu.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  final controleur = StreamController<List<ConnectivityResult>>();
  final connectivite = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? abonnement;
  ref.onDispose(() {
    runZonedGuarded(() => abonnement?.cancel(), (_, _) {});
    controleur.close();
  });
  () async {
    try {
      final initial = await connectivite.checkConnectivity();
      if (!controleur.isClosed) controleur.add(initial);
    } catch (_) {
      // État inconnu : on attend le premier changement.
    }
    if (controleur.isClosed) return;
    // Module indisponible (tests sans moteur Flutter, panne native) : ses
    // erreurs, même asynchrones, restent dans cette zone ; état inconnu.
    runZonedGuarded(() {
      abonnement = connectivite.onConnectivityChanged.listen(
        (etat) {
          if (!controleur.isClosed) controleur.add(etat);
        },
        onError: (Object _) {},
      );
    }, (_, _) {});
  }();
  return controleur.stream;
});

/// Indique si une connectivité autre que « none » est disponible.
///
/// Tant que l'état n'est pas encore connu (premières millisecondes), on
/// suppose le réseau présent : c'est le serveur qui dira s'il répond.
/// Supposer l'inverse afficherait « hors connexion » à chaque lancement.
/// Vrai ne garantit pas Internet (Wi-Fi sans Internet) : les lectures ont
/// leur propre délai maximum.
final estEnLigneProvider = Provider<bool>((ref) {
  final resultats = ref.watch(connectivityProvider).valueOrNull;
  if (resultats == null) return true;
  return resultats.any((r) => r != ConnectivityResult.none);
});

// NB : le moteur de synchronisation (core/sync/sync_engine.dart) est assemblé
// par feature avec son SyncRepository Drift dédié ; le socle fournit le port.
