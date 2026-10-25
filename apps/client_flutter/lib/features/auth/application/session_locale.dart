import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';

/// Copie locale des données du compte qui décident de l'écran d'ouverture :
/// profil, établissements, fiche liée, CGU.
///
/// Sans elle, l'application ne s'ouvrait pas hors connexion, même avec une
/// session ouverte : ces lectures n'interrogeaient que le serveur.
///
/// Règle :
/// - **ouverture de l'application** : la dernière copie est affichée tout de
///   suite, le serveur est relu en arrière-plan ; l'écran se met à jour si la
///   réponse diffère ;
/// - **relecture demandée** (après un choix de rôle, une liaison…) : serveur
///   d'abord, la copie seulement si le réseau manque ;
/// - **réseau absent et aucune copie** : erreur ; la relance au retour du
///   réseau ([RelanceReseau]) relit tout.
///
/// La copie n'est qu'un affichage : le serveur reste la seule autorité sur
/// les droits (RLS). Elle est effacée à la déconnexion.
final storeSessionLocaleProvider = Provider<CacheDocumentStore>(
  (ref) => CacheDocumentStore(ref.watch(databaseProvider), 'session_locale'),
);

/// Lectures déjà faites sur le serveur depuis le lancement (`type.compte`) :
/// une relecture de celles-ci part au serveur d'abord.
final _luesDuServeurProvider = Provider<Set<String>>((ref) => <String>{});

/// Réponses arrivées en arrière-plan, reprises par la lecture suivante sans
/// nouvel appel.
final _reponsesFraichesProvider = Provider<Map<String, Object?>>((ref) => <String, Object?>{});

/// Vrai quand une relecture en arrière-plan a échoué faute de réseau : la
/// relance réessaie régulièrement ([RelanceReseau]).
final donneesSessionPerimeesProvider = StateProvider<bool>((ref) => false);

/// Attente maximale d'une réponse du serveur pour ces lectures (surchargée
/// en test). Au-delà, on considère le réseau absent : copie du téléphone si
/// elle existe, sinon écran « Pas de connexion » avec « Réessayer ».
final delaiLectureServeurProvider = Provider<Duration>((ref) => const Duration(seconds: 8));

/// Copie affichée et serveur toujours muet après ce délai : bandeau « Hors
/// connexion » (l'accueil est déjà affiché, en 2 s au plus).
final delaiAvantBandeauProvider = Provider<Duration>((ref) => const Duration(seconds: 2));

Future<T> lireAvecCopieLocale<T>(
  Ref ref, {
  required String type,
  required String compteId,
  required Future<T> Function() serveur,
  required Object? Function(T valeur) versJson,
  required T Function(Object? json) depuisJson,
}) async {
  final cle = '$type.$compteId';
  final store = ref.read(storeSessionLocaleProvider);
  final lues = ref.read(_luesDuServeurProvider);
  final fraiches = ref.read(_reponsesFraichesProvider);

  if (fraiches.containsKey(cle)) return depuisJson(fraiches.remove(cle));

  final delai = ref.read(delaiLectureServeurProvider);
  Future<T> lireServeur() => serveur().timeout(delai);

  final copie = await _lire(store, type, compteId);

  // Ouverture : copie tout de suite, serveur en arrière-plan.
  if (copie != null && !lues.contains(cle)) {
    lues.add(cle);
    var actif = true;
    ref.onDispose(() => actif = false);
    void signalerHorsConnexion(bool valeur) {
      if (actif) ref.read(donneesSessionPerimeesProvider.notifier).state = valeur;
    }

    // Aucune connexion : la copie suffit, bandeau tout de suite ; la relance
    // relira au retour du réseau.
    if (!ref.read(estEnLigneProvider)) {
      lues.remove(cle);
      Future.microtask(() => signalerHorsConnexion(true));
      return depuisJson(copie);
    }

    unawaited(() async {
      // Serveur muet au-delà de [delaiAvantBandeauProvider] (Wi-Fi sans
      // Internet) : bandeau, sans abandonner la lecture (réseau lent).
      final minuteur = Timer(ref.read(delaiAvantBandeauProvider), () => signalerHorsConnexion(true));
      try {
        final json = versJson(await lireServeur());
        minuteur.cancel();
        // Le serveur répond : plus de bandeau, la relance s'arrête.
        signalerHorsConnexion(false);
        await _ecrire(store, type, compteId, json);
        if (jsonEncode(json) != jsonEncode(copie) && actif) {
          fraiches[cle] = json;
          ref.invalidateSelf();
        }
      } catch (e) {
        minuteur.cancel();
        // Hors connexion : on garde la copie, la relance réessaiera.
        lues.remove(cle);
        if (estErreurReseau(e)) signalerHorsConnexion(true);
      }
    }());
    return depuisJson(copie);
  }

  try {
    // Aucune connexion (mode avion, données coupées) : inutile d'attendre.
    if (!ref.read(estEnLigneProvider)) throw const HorsConnexion();
    final valeur = await lireServeur();
    lues.add(cle);
    ref.read(donneesSessionPerimeesProvider.notifier).state = false;
    await _ecrire(store, type, compteId, versJson(valeur));
    return valeur;
  } catch (e) {
    if (!estErreurReseau(e)) rethrow;
    ref.read(donneesSessionPerimeesProvider.notifier).state = true;
    if (copie == null) rethrow;
    return depuisJson(copie);
  }
}

/// Remplace la copie après une action confirmée par le serveur (CGU
/// acceptées…) : la prochaine ouverture n'affiche pas l'ancien état.
Future<void> ecrireCopieLocale(Ref ref, {required String type, required String compteId, required Object? json}) =>
    _ecrire(ref.read(storeSessionLocaleProvider), type, compteId, json);

/// Efface la copie (déconnexion).
Future<void> purgerSessionLocale(CacheDocumentStore store) async {
  try {
    await store.purgerTout();
  } catch (_) {
    // Base locale indisponible : rien à effacer.
  }
}

// La copie est un plus : une base locale indisponible ne bloque jamais la
// lecture du serveur.
Future<Object?> _lire(CacheDocumentStore store, String type, String compteId) async {
  try {
    final document = await store.lireDocument(type, compteId);
    return document == null ? null : document['json'];
  } catch (_) {
    return null;
  }
}

Future<void> _ecrire(CacheDocumentStore store, String type, String compteId, Object? json) async {
  try {
    await store.ecrireDocument(type, compteId, {'json': json});
  } catch (_) {
    // Copie impossible : la prochaine ouverture passera par le serveur.
  }
}
