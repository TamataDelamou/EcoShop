import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/config/env.dart';
import '../../../core/securite/code_secret.dart';
import '../../../core/securite/surveillance_session.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/session_locale.dart';
import '../../coquille/application/session_logout.dart';
import '../../coquille/application/verrou_controller.dart';
import '../data/appareil_repository.dart';
import '../domain/etat_appareil.dart';

/// Code du compte en service côté application. Faux sans configuration
/// Supabase (mode diagnostic) et dans les tests qui ne portent pas dessus.
final appareilActifProvider = Provider<bool>((ref) => Env.estConfigure);

final appareilRepositoryProvider = Provider<AppareilRepository>(
  (ref) => SupabaseAppareilRepository(ref.watch(supabaseClientProvider)),
);

/// Description de l'appareil pour le serveur (surchargée en test).
class InfoAppareil {
  const InfoAppareil({required this.modele, required this.systeme});
  final String modele;
  final String systeme;
}

/// Version de l'application affichée dans la liste des appareils.
const versionApplication = '0.1.0';

final infoAppareilProvider = FutureProvider<InfoAppareil>((ref) async {
  try {
    final info = DeviceInfoPlugin();
    if (kIsWeb) {
      final w = await info.webBrowserInfo;
      return InfoAppareil(modele: 'Navigateur ${w.browserName.name}', systeme: w.platform ?? 'Web');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final a = await info.androidInfo;
        final marque = a.manufacturer.isEmpty ? '' : '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ';
        return InfoAppareil(modele: '$marque${a.model}'.trim(), systeme: 'Android ${a.version.release}');
      case TargetPlatform.iOS:
        final i = await info.iosInfo;
        return InfoAppareil(modele: i.modelName, systeme: '${i.systemName} ${i.systemVersion}');
      case TargetPlatform.windows:
        final w = await info.windowsInfo;
        return InfoAppareil(modele: w.computerName, systeme: 'Windows');
      case TargetPlatform.macOS:
        final m = await info.macOsInfo;
        return InfoAppareil(modele: m.model, systeme: 'macOS ${m.osRelease}');
      case TargetPlatform.linux:
        final l = await info.linuxInfo;
        return InfoAppareil(modele: l.prettyName, systeme: 'Linux');
      case TargetPlatform.fuchsia:
        return const InfoAppareil(modele: 'Appareil', systeme: 'Fuchsia');
    }
  } catch (_) {
    return const InfoAppareil(modele: 'Appareil inconnu', systeme: '');
  }
});

/// Identifiant de la session de connexion (champ `session_id` du jeton).
String? sessionIdDepuisJeton(String? jeton) {
  if (jeton == null) return null;
  final parties = jeton.split('.');
  if (parties.length != 3) return null;
  try {
    final charge = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parties[1]))));
    return (charge as Map)['session_id'] as String?;
  } catch (_) {
    return null;
  }
}

final sessionIdProvider = Provider<String?>((ref) {
  try {
    return sessionIdDepuisJeton(ref.watch(sessionProvider.select((s) => s?.accessToken)));
  } catch (_) {
    return null;
  }
});

/// Compte de la session ouverte (surchargé en test).
final compteSessionProvider = Provider<String?>((ref) {
  try {
    return ref.watch(sessionProvider.select((s) => s?.user.id));
  } catch (_) {
    return null;
  }
});

/// Sessions déjà décrites au serveur depuis le lancement.
final _sessionsEnregistreesProvider = Provider<Set<String>>((ref) => <String>{});

/// État de cet appareil pour le compte connecté. Jamais bloquant sur une
/// lecture impossible : le serveur reste seul juge (il refuse toute requête
/// d'un appareil non vérifié, ce qui ramène ici).
final etatAppareilProvider = FutureProvider<EtatAppareil>((ref) async {
  if (!ref.watch(appareilActifProvider)) return EtatAppareil.libre;
  if (!ref.watch(sessionOuverteProvider)) return EtatAppareil.libre;
  final compte = ref.watch(compteSessionProvider);
  final session = ref.watch(sessionIdProvider);
  if (compte == null) return EtatAppareil.libre;
  final repo = ref.watch(appareilRepositoryProvider);
  final enregistrees = ref.read(_sessionsEnregistreesProvider);

  Future<EtatAppareil> serveur() async {
    if (session != null && !enregistrees.contains(session)) {
      final info = await ref.read(infoAppareilProvider.future);
      final etat = await repo.enregistrer(modele: info.modele, systeme: info.systeme, version: versionApplication);
      enregistrees.add(session);
      return etat;
    }
    return repo.etat();
  }

  try {
    return await lireAvecCopieLocale<EtatAppareil>(
      ref,
      type: 'appareil',
      compteId: compte,
      serveur: serveur,
      versJson: (e) => e.versJson(),
      depuisJson: (j) => EtatAppareil.depuisJson((j as Map).cast<String, dynamic>()),
    );
  } catch (_) {
    return EtatAppareil.libre;
  }
});

/// Ce téléphone a un code local, mais il n'est pas (ou plus) celui du
/// compte : à confirmer une fois (compte d'avant REG-22, ou code changé sur
/// un autre appareil). Seulement en ligne et sur un appareil connu.
final codeCompteAConfirmerProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(appareilActifProvider)) return false;
  final etat = ref.watch(etatAppareilProvider).valueOrNull;
  if (etat == null || identical(etat, EtatAppareil.libre)) return false;
  if (etat.statut != StatutAppareil.approuve) return false;
  final compte = ref.watch(profilProvider.select((p) => p.valueOrNull?.id));
  if (compte == null) return false;
  final codes = ref.read(serviceCodeSecretProvider);
  if (!await codes.existe(compte)) return false;
  if (!etat.aUnCode) return true;
  return await codes.versionCompte(compte) != etat.versionCode;
});

/// Actions du code du compte. Le code local (ouverture hors connexion) est
/// toujours aligné sur le code du compte.
class AppareilController {
  AppareilController(this._ref);

  final Ref _ref;
  bool _revocationEnCours = false;

  AppareilRepository get _repo => _ref.read(appareilRepositoryProvider);
  ServiceCodeSecret get _codes => _ref.read(serviceCodeSecretProvider);
  String? get _compte => _ref.read(compteSessionProvider);

  void _relire() {
    _ref.invalidate(etatAppareilProvider);
    _ref.invalidate(codeCompteAConfirmerProvider);
  }

  /// Le code du compte vient d'être prouvé sur cet appareil : il devient le
  /// code local, et l'application s'ouvre sans le redemander.
  Future<void> _aligner(String code, int version, {bool ouvrir = true}) async {
    final compte = _compte;
    if (compte == null) return;
    try {
      await _codes.creer(compte, code);
    } on CodeRefuse {
      // Code accepté par le serveur (règles identiques, hors date de
      // naissance) : on le garde tel quel.
      await _codes.creer(compte, code, sansControle: true);
    }
    await _codes.noterVersionCompte(compte, version);
    if (ouvrir) _ref.read(identiteVerifieeProvider.notifier).state = true;
    _relire();
    _ref.rafraichirSession();
  }

  /// Nouvel appareil : code du compte.
  Future<ResultatCodeCompte> verifierCode(String code) async {
    final r = await _repo.verifierCode(code);
    if (r is CodeCompteBon) await _aligner(code, r.version);
    if (r is! CodeCompteBon) _relire();
    return r;
  }

  /// Récupération mûre (48 h) ou déblocage à l'école : nouveau code.
  Future<void> finaliserRecuperation(String nouveau) async {
    final version = await _repo.finaliserRecuperation(nouveau);
    await _aligner(nouveau, version);
  }

  Future<DemandeAppareil> demanderApprobation() async {
    final d = await _repo.demanderApprobation();
    _relire();
    return d;
  }

  Future<DemandeAppareil> lancerRecuperation() async {
    final d = await _repo.lancerRecuperation();
    _relire();
    return d;
  }

  /// Code local tout juste créé (nouveau compte, ou appareil autorisé par un
  /// autre) : il devient le code du compte. Sans réseau, la confirmation
  /// sera demandée au retour du réseau.
  Future<void> codeLocalCree(String code) async {
    final compte = _compte;
    if (compte == null || !_ref.read(appareilActifProvider)) return;
    try {
      final etat = await _repo.etat();
      if (!etat.aUnCode) {
        await _repo.definirCode(code);
        await _codes.noterVersionCompte(compte, 1);
      } else if (etat.statut == StatutAppareil.approuve) {
        final version = await _repo.choisirCodeApresAutorisation(code);
        await _codes.noterVersionCompte(compte, version);
      }
    } catch (_) {
      // Repris par l'étape « code du compte à confirmer ».
    }
    _relire();
  }

  /// Compte d'avant REG-22, ou code changé ailleurs : confirmer le code.
  /// Renvoie un message d'erreur, ou null.
  Future<String?> confirmerCodeCompte(String code) async {
    final compte = _compte;
    if (compte == null) return null;
    final etat = await _repo.etat();
    if (!etat.aUnCode) {
      // Le code local devient celui du compte : il doit être le bon.
      final local = await _codes.verifier(compte, code);
      if (local is! CodeBon) {
        return local is CodeFaux ? 'Ce n’est pas le code de ce téléphone.' : null;
      }
      await _repo.definirCode(code);
      await _codes.noterVersionCompte(compte, 1);
      _relire();
      return null;
    }
    final r = await _repo.verifierCode(code);
    switch (r) {
      case CodeCompteBon(:final version):
        await _aligner(code, version, ouvrir: false);
        return null;
      case CodeCompteFaux(:final essaisRestants):
        return essaisRestants <= 1
            ? 'Code incorrect. Encore 1 essai avant le blocage des nouveaux appareils.'
            : 'Code incorrect. Encore $essaisRestants essais.';
      case CodeCompteBloque():
        _relire();
        return 'Trop de codes faux. Réessayez plus tard.';
    }
  }

  /// Mon profil › Sécurité › Changer le code du compte.
  Future<void> changerCode(String ancien, String nouveau) async {
    final version = await _repo.changerCode(ancien, nouveau);
    await _aligner(nouveau, version, ouvrir: false);
  }

  Future<void> approuver(String demandeId) async {
    await _repo.approuver(demandeId);
    _relire();
  }

  Future<void> refuser(String demandeId) async {
    await _repo.refuser(demandeId);
    _relire();
  }

  Future<void> annulerRecuperation(String demandeId) async {
    await _repo.annulerRecuperation(demandeId);
    _relire();
  }

  /// Le serveur a fermé cette session (autre appareil, « Ce n'est pas
  /// moi ») : déconnexion et effacement des données du téléphone, code
  /// local compris.
  Future<void> sessionRevoquee() async {
    if (_revocationEnCours) return;
    _revocationEnCours = true;
    try {
      final compte = _compte;
      if (compte != null) {
        await _codes.oublier(compte);
        try {
          await _ref.read(biometrieProvider).desactiver(compte);
        } catch (_) {}
      }
      await _ref.deconnecterEtPurgerDonneesLocales();
    } finally {
      _revocationEnCours = false;
    }
  }
}

/// Mon profil › Sécurité › Mes appareils.
final mesAppareilsProvider = FutureProvider.autoDispose<List<AppareilConnecte>>(
  (ref) => ref.watch(appareilRepositoryProvider).mesAppareils(),
);

final appareilControllerProvider = Provider<AppareilController>((ref) => AppareilController(ref));

/// Refus du serveur qui concernent toute la session (voir [SurveillanceSession]).
final refusSessionProvider = StreamProvider<RefusSession>((ref) => SurveillanceSession.refus);
