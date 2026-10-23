import '../../../core/db/cache_document_store.dart';
import '../domain/messagerie_push.dart';

/// Rattache le téléphone au compte connecté, pour que le serveur sache où
/// envoyer les notifications push (arrivée au portail, absence, relance de
/// scolarité, étapes d'un dossier d'inscription).
///
/// Hors connexion d'abord : sans réseau, rien n'est perdu — le rattachement
/// est retenté à chaque ouverture de l'application et à chaque retour du
/// réseau. Le dernier rattachement réussi est gardé sur l'appareil, pour ne
/// pas rappeler le serveur à chaque ouverture ; il est renouvelé chaque
/// semaine, ce qui tient à jour la date de dernier contact côté serveur.
class ServicePush {
  ServicePush({
    required this.messagerie,
    required this.memoire,
    required this.enregistrer,
    required this.retirer,
    required this.plateforme,
    DateTime Function()? maintenant,
  }) : _maintenant = maintenant ?? DateTime.now;

  final MessageriePush messagerie;
  final CacheDocumentStore memoire;
  final Future<void> Function(String identifiant, String plateforme) enregistrer;
  /// [jetonAcces] : celui du compte, lu avant la fermeture de la session
  /// (l'appel part quand elle est déjà fermée sur l'appareil).
  final Future<void> Function(String identifiant, String? jetonAcces) retirer;
  final String plateforme;
  final DateTime Function() _maintenant;

  static const _type = 'rattachement';
  static const _cle = 'appareil';
  static const renouvellement = Duration(days: 7);

  /// `true` si le téléphone ([identifiant]) est rattaché à [profilId] côté
  /// serveur ; `false` si c'est à retenter (pas de réseau).
  Future<bool> rattacher(String profilId, String identifiant) async {
    if (identifiant.isEmpty) return false;
    final connu = await memoire.lireDocumentDate(_type, _cle);
    if (connu != null &&
        connu.document['identifiant'] == identifiant &&
        connu.document['profil'] == profilId &&
        _maintenant().difference(connu.misAJourLe) < renouvellement) {
      return true;
    }
    try {
      await enregistrer(identifiant, plateforme);
    } catch (_) {
      return false;
    }
    await memoire.ecrireDocument(_type, _cle, {'identifiant': identifiant, 'profil': profilId});
    return true;
  }

  /// À la déconnexion : ce téléphone ne doit plus recevoir les
  /// notifications du compte (tablette partagée, téléphone prêté).
  ///
  /// Le serveur est prévenu s'il est joignable ; dans tous les cas le
  /// téléphone est désinscrit du service push, et le serveur l'oublie au
  /// premier envoi refusé.
  Future<void> detacher({String? jetonAcces}) async {
    final connu = await memoire.lireDocument(_type, _cle);
    final identifiant = connu?['identifiant'] as String?;
    if (identifiant != null) {
      try {
        await retirer(identifiant, jetonAcces).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Hors connexion : la désinscription ci-dessous suffit.
      }
    }
    await memoire.supprimerDocument(_type, _cle);
    try {
      await messagerie.desenregistrer().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Rien d'autre à faire hors connexion.
    }
  }
}
