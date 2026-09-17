import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/features/auth/domain/destination_session.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth_repository.dart';

void main() {
  DestinationSession resoudre({
    bool session = true,
    Profil? profil,
    bool fiche = true,
    int etablissements = 0,
    bool cguAcceptee = true,
    bool regionalisationVue = true,
  }) {
    return GardeSession.resoudre(
      sessionOuverte: session,
      profil: profil,
      ficheLiee: fiche,
      nombreEtablissements: etablissements,
      cguAcceptee: cguAcceptee,
      regionalisationVue: regionalisationVue,
    );
  }

  group('GardeSession.resoudre', () {
    test('sans session, oriente vers la connexion', () {
      expect(resoudre(session: false), DestinationSession.connexion);
    });

    test('profil non chargé, n’oriente pas encore', () {
      expect(resoudre(profil: null), DestinationSession.chargement);
    });

    test('compte suspendu, oriente vers le blocage avant toute autre règle', () {
      final profil = profilTest(role: null, statut: StatutCompte.suspendu);
      // Le rôle est indéfini : sans la priorité du statut, la garde
      // proposerait le choix de rôle à un compte suspendu.
      expect(resoudre(profil: profil), DestinationSession.compteBloque);
    });

    test('compte supprimé, oriente vers le blocage', () {
      expect(
        resoudre(profil: profilTest(statut: StatutCompte.supprime)),
        DestinationSession.compteBloque,
      );
    });

    test('rôle non défini, oriente vers le choix de rôle (ch. 5.2)', () {
      expect(
        resoudre(profil: profilTest(role: null)),
        DestinationSession.choixRole,
      );
    });

    test('élève sans fiche liée, oriente vers la liaison (ch. 5.8)', () {
      expect(
        resoudre(profil: profilTest(role: RoleRacine.eleve), fiche: false),
        DestinationSession.liaisonFiche,
      );
    });

    test('seul l’élève est soumis à la liaison de fiche', () {
      for (final role in [
        RoleRacine.parent,
        RoleRacine.enseignant,
        RoleRacine.direction,
        RoleRacine.vendeur,
      ]) {
        expect(
          resoudre(profil: profilTest(role: role), fiche: false),
          DestinationSession.accueil,
          reason: 'le rôle ${role.code} n’a pas de fiche scolaire à revendiquer',
        );
      }
    });

    test('plusieurs établissements sans sélection, demande de choisir', () {
      expect(
        resoudre(
          profil: profilTest(role: RoleRacine.enseignant),
          etablissements: 3,
        ),
        DestinationSession.selectionEtablissement,
      );
    });

    test('un seul établissement, pas d’écran de sélection', () {
      expect(
        resoudre(
          profil: profilTest(role: RoleRacine.enseignant),
          etablissements: 1,
        ),
        DestinationSession.accueil,
      );
    });

    test('établissement déjà sélectionné, accès à la coquille', () {
      expect(
        resoudre(
          profil: profilTest(
            role: RoleRacine.enseignant,
            etablissementActifId: 'e1',
          ),
          etablissements: 3,
        ),
        DestinationSession.accueil,
      );
    });

    test('aucun rattachement (parent nouvellement inscrit), accès direct', () {
      expect(
        resoudre(profil: profilTest(role: RoleRacine.parent)),
        DestinationSession.accueil,
      );
    });

    test('CGU non acceptées (§34.10), oriente vers elles avant l’accueil', () {
      expect(
        resoudre(profil: profilTest(role: RoleRacine.parent), cguAcceptee: false),
        DestinationSession.cguNonAcceptees,
      );
    });

    test('CGU acceptées, accès direct à l’accueil', () {
      expect(
        resoudre(profil: profilTest(role: RoleRacine.parent), cguAcceptee: true),
        DestinationSession.accueil,
      );
    });

    test('CGU : la sélection d’établissement reste prioritaire', () {
      expect(
        resoudre(
          profil: profilTest(role: RoleRacine.enseignant),
          etablissements: 3,
          cguAcceptee: false,
        ),
        DestinationSession.selectionEtablissement,
      );
    });

    test('CGU non acceptées est prioritaire sur l’étape Langue/Région (D3)', () {
      expect(
        resoudre(
          profil: profilTest(role: RoleRacine.parent),
          cguAcceptee: false,
          regionalisationVue: false,
        ),
        DestinationSession.cguNonAcceptees,
        reason: 'obligation légale avant un simple confort d’ergonomie',
      );
    });

    test('étape Langue/Région (D3) non vue, oriente vers elle avant l’accueil', () {
      expect(
        resoudre(profil: profilTest(role: RoleRacine.parent), regionalisationVue: false),
        DestinationSession.regionalisation,
      );
    });

    test('étape Langue/Région (D3) déjà vue, accès direct à l’accueil', () {
      expect(
        resoudre(profil: profilTest(role: RoleRacine.parent), regionalisationVue: true),
        DestinationSession.accueil,
      );
    });

    test('étape Langue/Région (D3) : la sélection d’établissement reste prioritaire', () {
      expect(
        resoudre(
          profil: profilTest(role: RoleRacine.enseignant),
          etablissements: 3,
          regionalisationVue: false,
        ),
        DestinationSession.selectionEtablissement,
        reason: 'pays/devise dépendent de l’établissement résolu — pas encore le cas ici',
      );
    });
  });
}
