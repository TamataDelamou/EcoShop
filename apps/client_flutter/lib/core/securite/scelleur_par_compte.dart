import '../db/scelleur_copies.dart';
import 'chiffrement_file.dart';

/// Copies chiffrées par compte avec la clé de la file d'envoi (REG-18).
///
/// Les réglages de l'appareil ([domainesAppareil] : thème, identifiant de
/// l'appareil, copie de session qui permet l'ouverture hors connexion, suivi
/// de l'amorçage) restent en clair : ils sont lus avant même qu'un compte
/// soit connu, et ne contiennent aucune donnée d'élève.
class ScelleurParCompte implements ScelleurCopies {
  ScelleurParCompte(this._chiffreur, this._compteCourant);

  final ChiffreurFile _chiffreur;

  /// Compte connecté à l'instant de la lecture ou de l'écriture.
  final String? Function() _compteCourant;

  static const domainesAppareil = {
    'core',
    'preferences',
    'preferences_accueil',
    'push',
    'session_locale',
    'amorcage_suivi',
  };

  @override
  Future<String?> sceller(String domaine, String clair) async {
    final compte = _compteCourant();
    if (domainesAppareil.contains(domaine) || compte == null) return clair;
    try {
      return await _chiffreur.chiffrer(compte, clair);
    } catch (_) {
      // Coffre du système en panne : pas de copie plutôt qu'une copie en
      // clair lisible par le compte suivant.
      return null;
    }
  }

  @override
  Future<String?> ouvrir(String domaine, String stocke) async {
    final compte = _compteCourant();
    if (!ChiffreurFile.estChiffre(stocke)) {
      // En clair : réglage de l'appareil, ou copie faite hors session. Une
      // copie en clair d'un domaine de compte, lue par un compte connecté,
      // date d'avant le scellement et peut venir d'un autre compte : ignorée
      // (elle sera relue du serveur).
      return domainesAppareil.contains(domaine) || compte == null ? stocke : null;
    }
    if (compte == null) return null;
    return _chiffreur.dechiffrer(compte, stocke);
  }
}
