import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/auth/presentation/ecran_choix_role.dart';
import 'package:ecoshop_client/features/cgu/application/cgu_providers.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_statut.dart';
import 'package:ecoshop_client/features/coquille/presentation/coquille_app.dart';
import 'package:ecoshop_client/features/coquille/presentation/garde_session.dart';
import 'package:ecoshop_client/features/invitations/application/invitations_providers.dart';
import 'package:ecoshop_client/features/invitations/domain/invitation.dart';
import 'package:ecoshop_client/features/invitations/presentation/ecran_invitations.dart';
import 'package:ecoshop_client/features/invitations/presentation/ecran_invitations_etablissement.dart';
import 'package:ecoshop_client/features/regionalisation/application/regionalisation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth_repository.dart';

/// Invitations du personnel et des vendeurs : vues après la connexion,
/// acceptées ou refusées ; règle REG-16 pour les numéros ; suivi par la
/// direction.

class _RegionalisationVue extends OnboardingRegionalisationNotifier {
  @override
  Future<bool> build() async => true;
}

class _CguRienAAccepter extends CguStatutNotifier {
  @override
  Future<CguStatut?> build() async => null;
}

class _FauxInvitations implements InvitationsRepository {
  _FauxInvitations({this.recues = const [], this.envoyees = const [], this.auth});

  List<InvitationRecue> recues;
  List<InvitationEnvoyee> envoyees;
  final FauxAuthRepository? auth;
  final List<String> appels = [];
  ErreurInvitations? erreur;

  @override
  Future<List<InvitationRecue>> mesInvitations() async => recues;

  @override
  Future<void> repondre(String invitationId, {required bool accepter}) async {
    appels.add('repondre:$invitationId:$accepter');
    final e = erreur;
    if (e != null) throw e;
    final i = recues.firstWhere((r) => r.id == invitationId);
    recues = [for (final r in recues) if (r.id != invitationId) r];
    // Le serveur fixe le rôle d'un compte qui n'en avait pas.
    final a = auth;
    if (accepter && a != null && a.profil?.roleRacine == null) {
      final p = a.profil!;
      a.profil = Profil(
        id: p.id,
        identifiantCanonique: p.identifiantCanonique,
        statutCompte: p.statutCompte,
        roleRacine: RoleRacine.depuisCode(i.roleCible),
        prenom: 'Fatou',
        nom: 'Camara',
      );
    }
  }

  @override
  Future<List<InvitationEnvoyee>> invitationsEtablissement(String etablissementId) async => envoyees;

  @override
  Future<List<PosteInvitable>> postes(String etablissementId) async => const [PosteInvitable('poste-1', 'Comptable')];

  @override
  Future<void> inviter({
    required String etablissementId,
    required String identifiant,
    required RoleRacine role,
    String? posteId,
  }) async {
    appels.add('inviter:$etablissementId:$identifiant:${role.code}:$posteId');
    final e = erreur;
    if (e != null) throw e;
  }

  @override
  Future<void> revoquer(String invitationId) async => appels.add('revoquer:$invitationId');

  @override
  Future<InvitationAcceptee> accepterParCode(String code) async {
    appels.add('code:$code');
    final e = erreur;
    if (e != null) throw e;
    return const InvitationAcceptee(etablissementId: 'e1', etablissement: 'Bambino', role: 'enseignant');
  }
}

const _parEmail = InvitationRecue(
  id: 'inv-1',
  etablissement: 'École Bambino',
  roleCible: 'enseignant',
  identifiant: 'fatou@exemple.org',
  parTelephone: false,
  verifie: true,
  poste: 'Comptable',
  invitePar: 'Mariama Diallo',
);

const _parTelephoneNonConfirme = InvitationRecue(
  id: 'inv-2',
  etablissement: 'Lycée Donka',
  roleCible: 'vendeur',
  identifiant: '+224620111111',
  parTelephone: true,
  verifie: false,
);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester, {required FauxAuthRepository auth, required _FauxInvitations invitations}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        invitationsRepositoryProvider.overrideWithValue(invitations),
        sessionOuverteProvider.overrideWithValue(true),
        databaseProvider.overrideWithValue(db),
        onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
        cguStatutProvider.overrideWith(_CguRienAAccepter.new),
      ],
      child: const MaterialApp(home: RacineApp()),
    ));
    await tester.pumpAndSettle();
  }

  Profil sansRole() => const Profil(id: 'p-fatou', identifiantCanonique: 'fatou@exemple.org', statutCompte: StatutCompte.actif);

  group('Après la connexion', () {
    testWidgets('compte neuf invité : l’invitation passe avant le choix d’espace ; accepter donne le rôle prévu',
        (tester) async {
      final auth = FauxAuthRepository(profil: sansRole());
      final inv = _FauxInvitations(recues: [_parEmail], auth: auth);
      await monter(tester, auth: auth, invitations: inv);

      expect(find.byType(EcranInvitations), findsOneWidget);
      expect(find.byType(EcranChoixRole), findsNothing, reason: 'ne pas choisir Élève ou Parent à la place');
      expect(find.text('École Bambino'), findsOneWidget);
      expect(find.textContaining('Mariama Diallo vous invite comme Enseignant (Comptable)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('accepter_inv-1')));
      await tester.pumpAndSettle();

      expect(inv.appels, ['repondre:inv-1:true']);
      expect(auth.profil?.roleRacine, RoleRacine.enseignant);
      expect(find.byType(CoquilleApp), findsOneWidget);
    });

    testWidgets('refuser demande confirmation puis prévient l’école', (tester) async {
      final auth = FauxAuthRepository(profil: sansRole());
      final inv = _FauxInvitations(recues: [_parEmail], auth: auth);
      await monter(tester, auth: auth, invitations: inv);

      await tester.tap(find.byKey(const Key('refuser_inv-1')));
      await tester.pumpAndSettle();
      expect(find.text('Refuser l’invitation ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await tester.pumpAndSettle();

      expect(inv.appels, ['repondre:inv-1:false']);
      // Plus d'invitation : le compte neuf choisit son espace.
      expect(find.byType(EcranChoixRole), findsOneWidget);
    });

    testWidgets('« Continuer sans invitation » : choix de l’espace, rien n’est refusé', (tester) async {
      final inv = _FauxInvitations(recues: [_parEmail]);
      await monter(tester, auth: FauxAuthRepository(profil: sansRole()), invitations: inv);

      await tester.tap(find.byKey(const Key('invitations_plus_tard')));
      await tester.pumpAndSettle();

      expect(find.byType(EcranChoixRole), findsOneWidget);
      expect(inv.appels, isEmpty);
    });

    testWidgets('numéro seulement déclaré : invitation visible, aucune réponse possible (REG-16)', (tester) async {
      final inv = _FauxInvitations(recues: [_parTelephoneNonConfirme]);
      await monter(tester, auth: FauxAuthRepository(profil: sansRole()), invitations: inv);

      expect(find.text('Lycée Donka'), findsOneWidget);
      expect(find.byKey(const Key('invitation_numero_non_confirme')), findsOneWidget);
      expect(find.byKey(const Key('accepter_inv-2')), findsNothing);
      expect(find.byKey(const Key('refuser_inv-2')), findsNothing);
    });

    testWidgets('compte en service invité : « Plus tard », puis retrouvée dans « Mon profil »', (tester) async {
      final inv = _FauxInvitations(recues: [_parEmail]);
      await monter(tester, auth: FauxAuthRepository(profil: profilTest(role: RoleRacine.vendeur)), invitations: inv);

      expect(find.byType(EcranInvitations), findsOneWidget);
      expect(find.text('Plus tard'), findsOneWidget);
      await tester.tap(find.byKey(const Key('invitations_plus_tard')));
      await tester.pumpAndSettle();
      expect(find.byType(CoquilleApp), findsOneWidget);

      await tester.tap(find.byKey(const Key('raccourci_profil')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('profil_mes_invitations')), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.byKey(const Key('profil_mes_invitations')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('accepter_inv-1')), findsOneWidget);
    });

    testWidgets('invitation déjà traitée ailleurs : message clair', (tester) async {
      final inv = _FauxInvitations(recues: [_parEmail])..erreur = const ErreurInvitations('INVITATION_DEJA_TRAITEE');
      await monter(tester, auth: FauxAuthRepository(profil: sansRole()), invitations: inv);

      await tester.tap(find.byKey(const Key('accepter_inv-1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('déjà reçu une réponse'), findsOneWidget);
    });

    testWidgets('sans invitation : rien ne change', (tester) async {
      await monter(tester, auth: FauxAuthRepository(profil: profilTest(role: RoleRacine.parent)), invitations: _FauxInvitations());
      expect(find.byType(EcranInvitations), findsNothing);
      expect(find.byType(CoquilleApp), findsOneWidget);
    });
  });

  group('Direction', () {
    Future<void> monterDirection(WidgetTester tester, _FauxInvitations inv) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [invitationsRepositoryProvider.overrideWithValue(inv)],
        child: const MaterialApp(home: EcranInvitationsEtablissement(etablissementId: 'etab-1')),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('inviter par e-mail : adresse normalisée, rôle et poste transmis', (tester) async {
      final inv = _FauxInvitations();
      await monterDirection(tester, inv);

      await tester.tap(find.byKey(const Key('bouton_inviter')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ_identifiant_invite')), ' Fatou@Exemple.ORG ');
      await tester.tap(find.byKey(const Key('choix_poste_invite')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comptable').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bouton_envoyer_invitation')));
      await tester.pumpAndSettle();

      expect(inv.appels, ['inviter:etab-1:fatou@exemple.org:enseignant:poste-1']);
      expect(find.text('Invitation envoyée.'), findsOneWidget);
    });

    testWidgets('par téléphone : avertissement (pas de SMS, numéro à confirmer à l’école)', (tester) async {
      final inv = _FauxInvitations();
      await monterDirection(tester, inv);
      await tester.tap(find.byKey(const Key('bouton_inviter')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ_identifiant_invite')), '+224 620 11 11 11');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('avertissement_telephone')), findsOneWidget);
      await tester.tap(find.byKey(const Key('bouton_envoyer_invitation')));
      await tester.pumpAndSettle();
      expect(inv.appels, ['inviter:etab-1:+224620111111:enseignant:null']);
    });

    testWidgets('saisie invalide : refusée avant tout appel ; refus du serveur affiché', (tester) async {
      final inv = _FauxInvitations();
      await monterDirection(tester, inv);
      await tester.tap(find.byKey(const Key('bouton_inviter')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ_identifiant_invite')), '620111111');
      await tester.tap(find.byKey(const Key('bouton_envoyer_invitation')));
      await tester.pumpAndSettle();
      expect(inv.appels, isEmpty);
      expect(find.textContaining('avec l’indicatif'), findsOneWidget);

      inv.erreur = const ErreurInvitations('DEJA_MEMBRE');
      await tester.enterText(find.byKey(const Key('champ_identifiant_invite')), 'prof@exemple.org');
      await tester.tap(find.byKey(const Key('bouton_envoyer_invitation')));
      await tester.pumpAndSettle();
      expect(find.textContaining('déjà membre'), findsOneWidget);
    });

    testWidgets('suivi et retrait d’une invitation en attente', (tester) async {
      final inv = _FauxInvitations(envoyees: const [
        InvitationEnvoyee(id: 'e1', identifiant: 'a@exemple.org', roleCible: 'enseignant', statut: StatutInvitation.enAttente),
        InvitationEnvoyee(
            id: 'e2', identifiant: 'b@exemple.org', roleCible: 'vendeur', statut: StatutInvitation.acceptee, membre: 'Ibrahima Sow'),
      ]);
      await monterDirection(tester, inv);

      expect(find.textContaining('Acceptée par Ibrahima Sow'), findsOneWidget);
      expect(find.byKey(const Key('retirer_e2')), findsNothing, reason: 'acceptée : plus rien à retirer');
      await tester.tap(find.byKey(const Key('retirer_e1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Retirer'));
      await tester.pumpAndSettle();
      expect(inv.appels, ['revoquer:e1']);
    });
  });

  test('normalisation de la saisie de la direction', () {
    expect(normaliserIdentifiantInvitation(' A@B.org '), 'a@b.org');
    expect(normaliserIdentifiantInvitation('+224 620-11.11 11'), '+224620111111');
    expect(normaliserIdentifiantInvitation('620111111'), isNull, reason: 'indicatif obligatoire');
    expect(normaliserIdentifiantInvitation('a@b'), isNull);
  });
}
