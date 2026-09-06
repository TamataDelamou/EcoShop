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
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// Indique si une connectivité autre que « none » est disponible.
final estEnLigneProvider = Provider<bool>((ref) {
  final async = ref.watch(connectivityProvider);
  final resultats = async.value ?? const [ConnectivityResult.none];
  return resultats.any((r) => r != ConnectivityResult.none);
});

// NB : le moteur de synchronisation (core/sync/sync_engine.dart) est assemblé
// par feature avec son SyncRepository Drift dédié ; le socle fournit le port.
