import 'profil.dart';

/// Écran vers lequel la garde de session oriente l'utilisateur.
enum DestinationSession {
  /// Profil pas encore chargé — on n'oriente pas tant qu'on ne sait pas.
  chargement,

  /// Aucune session : parcours OTP.
  connexion,

  /// Compte suspendu ou supprimé : accès refusé, sans possibilité de contourner.
  compteBloque,

  /// Rôle racine pas encore choisi (ch. 5.2).
  choixRole,

  /// Élève dont la fiche scolaire n'est pas encore revendiquée (ch. 5.8).
  liaisonFiche,

  /// Plusieurs établissements et aucun sélectionné (ch. 4).
  selectionEtablissement,

  /// Coquille applicative.
  accueil,
}

/// Garde de session — règle d'orientation unique de l'application.
///
/// Fonction pure, volontairement séparée de tout widget : c'est la seule
/// définition de « où doit se trouver l'utilisateur », et elle est
/// intégralement testable sans Supabase ni arbre de widgets.
///
/// Cette garde est un confort d'ergonomie, **pas** un contrôle de sécurité :
/// contourner l'écran ne donne accès à aucune donnée, RLS refusant côté
/// serveur (ch. 34).
abstract final class GardeSession {
  static DestinationSession resoudre({
    required bool sessionOuverte,
    required Profil? profil,
    required bool ficheLiee,
    required int nombreEtablissements,
  }) {
    if (!sessionOuverte) return DestinationSession.connexion;
    if (profil == null) return DestinationSession.chargement;

    if (profil.statutCompte != StatutCompte.actif) {
      return DestinationSession.compteBloque;
    }

    if (!profil.roleDefini) return DestinationSession.choixRole;

    if (profil.exigeLiaisonFiche && !ficheLiee) {
      return DestinationSession.liaisonFiche;
    }

    // Un rattachement unique est sélectionné automatiquement par le contrôleur ;
    // l'écran de sélection n'a de sens qu'à partir de deux établissements
    // (cas de l'enseignant multi-établissement).
    if (profil.etablissementActifId == null && nombreEtablissements > 1) {
      return DestinationSession.selectionEtablissement;
    }

    return DestinationSession.accueil;
  }
}
