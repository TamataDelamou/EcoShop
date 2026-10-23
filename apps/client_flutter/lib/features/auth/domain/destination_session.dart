import 'profil.dart';

/// Écran vers lequel la garde de session oriente l'utilisateur.
enum DestinationSession {
  /// Profil pas encore chargé — on n'oriente pas tant qu'on ne sait pas.
  chargement,

  /// Aucune session : parcours OTP.
  connexion,

  /// Compte suspendu ou supprimé : accès refusé, sans possibilité de contourner.
  compteBloque,

  /// Rôle racine pas encore choisi (ch. 5.2) : fin de la création du
  /// compte (espace et nom, REG-18), ou espace du représentant d'un
  /// établissement en attente de validation.
  choixRole,

  /// Compte au rôle déjà fixé (personnel invité) mais jamais finalisé et
  /// sans nom complet : nom et prénoms demandés une fois (REG-18).
  nomACompleter,

  /// Élève dont la fiche scolaire n'est pas encore revendiquée (ch. 5.8).
  liaisonFiche,

  /// Plusieurs établissements et aucun sélectionné (ch. 4).
  selectionEtablissement,

  /// CGU de la version courante du parcours (simplifié/complet, selon le
  /// rôle) non encore acceptées (§34.10). Bloquant, contrairement à la
  /// régionalisation ci-dessous — placé avant elle car il s'agit d'une
  /// obligation légale, pas d'un confort d'ergonomie.
  cguNonAcceptees,

  /// Aucun code secret sur ce téléphone pour ce compte (REG-18) : création
  /// obligatoire, puis proposition de l'empreinte.
  codeSecret,

  /// Compte tout juste créé : bienvenue, identifiant EcoShop, prochaine
  /// étape (REG-18). Affiché une fois.
  recapitulatif,

  /// Compte sans numéro de téléphone (REG-16) : on le demande une fois
  /// connecté, par e-mail ou Google. « Plus tard » est permis.
  telephoneProfil,

  /// Étape d'onboarding Langue/Région (D3), non bloquante — affichée une
  /// fois par profil, après l'établissement résolu (pays/devise en
  /// dépendent).
  regionalisation,

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
    // Défaut `true` (= déjà vue) pour ne casser aucun appelant existant qui
    // ignore ce paramètre (tests notamment) : en production,
    // `destinationProvider` transmet toujours la valeur réellement lue.
    bool regionalisationVue = true,
    // Même défaut `true` (= rien à accepter/déjà accepté) et même raison
    // que `regionalisationVue` : ne casser aucun appelant existant qui
    // ignore ce paramètre.
    bool cguAcceptee = true,
    // Défaut `false` (= rien à demander), même raison que ci-dessus.
    bool telephoneAFournir = false,
    // Défaut `false` (= code déjà créé ou verrou hors service).
    bool codeSecretACreer = false,
    // Défaut `false` (= rien à montrer).
    bool recapitulatifAMontrer = false,
  }) {
    if (!sessionOuverte) return DestinationSession.connexion;
    if (profil == null) return DestinationSession.chargement;

    if (profil.statutCompte != StatutCompte.actif) {
      return DestinationSession.compteBloque;
    }

    if (!profil.roleDefini) return DestinationSession.choixRole;

    if (!profil.inscriptionFinalisee && profil.nomIncomplet) {
      return DestinationSession.nomACompleter;
    }

    if (profil.exigeLiaisonFiche && !ficheLiee) {
      return DestinationSession.liaisonFiche;
    }

    // Un rattachement unique est sélectionné automatiquement par le contrôleur ;
    // l'écran de sélection n'a de sens qu'à partir de deux établissements
    // (cas de l'enseignant multi-établissement).
    if (profil.etablissementActifId == null && nombreEtablissements > 1) {
      return DestinationSession.selectionEtablissement;
    }

    if (!cguAcceptee) return DestinationSession.cguNonAcceptees;

    if (telephoneAFournir) return DestinationSession.telephoneProfil;

    if (codeSecretACreer) return DestinationSession.codeSecret;

    if (recapitulatifAMontrer) return DestinationSession.recapitulatif;

    if (!regionalisationVue) return DestinationSession.regionalisation;

    return DestinationSession.accueil;
  }
}
