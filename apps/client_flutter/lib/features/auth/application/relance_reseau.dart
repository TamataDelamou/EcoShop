import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'auth_providers.dart';
import 'session_locale.dart';

/// Délai entre deux nouvelles tentatives tant que les données du compte
/// n'ont pas pu être relues (surchargé en test).
final delaiRelanceReseauProvider = Provider<Duration>((ref) => const Duration(seconds: 30));

/// Relance au retour du réseau (REG-18) : plus besoin de fermer et relancer
/// l'application.
///
/// - Le téléphone retrouve une connexion : profil, établissements, fiche et
///   CGU sont relus.
/// - Une relecture a échoué faute de réseau (Wi-Fi sans Internet, réseau
///   mobile faible : le téléphone se croit connecté) : nouvel essai toutes
///   les [delaiRelanceReseauProvider], jusqu'à ce qu'il réussisse.
///
/// Écouté en permanence par la racine de l'application.
final relanceReseauProvider = Provider<void>((ref) {
  Timer? minuteur;
  ref.onDispose(() => minuteur?.cancel());

  void relancer() {
    if (!ref.read(sessionOuverteProvider)) return;
    // Le bandeau reste affiché pendant l'essai : il disparaît quand une
    // lecture réussit (`session_locale.dart`), sans clignoter.
    ref.rafraichirSession();
  }

  ref.listen<bool>(estEnLigneProvider, (avant, enLigne) {
    if (avant == false && enLigne) relancer();
  });

  ref.listen<bool>(donneesSessionPerimeesProvider, (_, perimees) {
    if (perimees) {
      minuteur ??= Timer.periodic(ref.read(delaiRelanceReseauProvider), (_) => relancer());
    } else {
      minuteur?.cancel();
      minuteur = null;
    }
  }, fireImmediately: true);
});
