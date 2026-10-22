import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/env.dart';
import '../domain/auth_repository.dart';

/// Connexion avec le compte Google déjà présent sur le téléphone (REG-16).
///
/// Sur Android, le module passe par le Gestionnaire d'identifiants du
/// système : une feuille en bas de l'écran propose les comptes Google du
/// téléphone, l'utilisateur touche le sien, aucune saisie. Le jeton
/// d'identité obtenu est remis à Supabase, qui ouvre la session.
abstract interface class ConnexionGoogle {
  /// Faux si l'application n'est pas configurée pour Google, ou hors
  /// Android et iOS.
  bool get disponible;

  /// Compte Google qui a déjà autorisé EcoShop sur ce téléphone : jeton
  /// obtenu sans action, ou d'un seul appui dans la feuille du système.
  /// Null si aucun ou si l'utilisateur la ferme.
  Future<String?> jetonSilencieux();

  /// Sélecteur des comptes Google du téléphone (avec « Ajouter un compte »).
  /// Null si l'utilisateur annule.
  Future<String?> jetonInteractif();

  /// À la déconnexion : la prochaine connexion propose de nouveau le choix
  /// du compte (téléphone prêté, tablette d'école).
  Future<void> oublier();
}

class ConnexionGooglePlugin implements ConnexionGoogle {
  ConnexionGooglePlugin({
    this._serverClientId = Env.googleWebClientId,
    this._clientIdIos = Env.googleIosClientId,
  });

  final String _serverClientId;
  final String _clientIdIos;
  Future<void>? _initialisation;

  GoogleSignIn get _google => GoogleSignIn.instance;

  @override
  bool get disponible =>
      // Un identifiant client Google se termine toujours ainsi ; un champ
      // laissé vide ou encore à remplir (« <…> ») n'affiche pas le bouton.
      _serverClientId.endsWith('.apps.googleusercontent.com') &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _pret() => _initialisation ??= _google.initialize(
        serverClientId: _serverClientId,
        clientId: _clientIdIos.isEmpty ? null : _clientIdIos,
      );

  @override
  Future<String?> jetonSilencieux() async {
    if (!disponible) return null;
    try {
      await _pret();
      final tentative = _google.attemptLightweightAuthentication();
      if (tentative == null) return null;
      final compte = await tentative;
      return compte?.authentication.idToken;
    } catch (_) {
      // Aucun compte autorisé, feuille désactivée par l'utilisateur dans
      // les réglages Google : le bouton reste disponible.
      return null;
    }
  }

  @override
  Future<String?> jetonInteractif() async {
    if (!disponible) throw const ErreurAuth('GOOGLE_INDISPONIBLE');
    try {
      await _pret();
      if (!_google.supportsAuthenticate()) throw const ErreurAuth('GOOGLE_INDISPONIBLE');
      final compte = await _google.authenticate(scopeHint: const ['email', 'profile']);
      final jeton = compte.authentication.idToken;
      if (jeton == null) throw const ErreurAuth('GOOGLE_INDISPONIBLE');
      return jeton;
    } on GoogleSignInException catch (e) {
      // Sur Android, une erreur de configuration (empreinte SHA-1 absente)
      // remonte aussi en « annulé » : docs/MISE_EN_SERVICE.md, étape 5.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw ErreurAuth('GOOGLE_INDISPONIBLE', e.description);
    }
  }

  @override
  Future<void> oublier() async {
    if (!disponible || _initialisation == null) return;
    try {
      await _google.signOut();
    } catch (_) {
      // Rien à oublier.
    }
  }
}
