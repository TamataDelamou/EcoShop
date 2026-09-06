import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/e164_validator.dart';
import '../domain/auth_repository.dart';
import '../domain/canal_otp.dart';
import 'auth_providers.dart';

/// Étape du parcours OTP (ch. 5.4).
enum EtapeConnexion {
  /// Saisie de l'identifiant et choix du canal.
  identifiant,

  /// Code envoyé, en attente de saisie.
  code,

  /// Lien magique envoyé : la session s'ouvrira depuis le lien profond.
  lienEnvoye,
}

/// État immuable de l'écran de connexion.
class EtatConnexion {
  const EtatConnexion({
    this.etape = EtapeConnexion.identifiant,
    this.canal = CanalOtp.sms,
    this.indicatifPays = '+224',
    this.identifiantNormalise,
    this.enCours = false,
    this.codeErreur,
  });

  final EtapeConnexion etape;
  final CanalOtp canal;

  /// Indicatif pays sélectionné pour l'entrée téléphone.
  final String indicatifPays;

  /// Identifiant effectivement transmis à Supabase (E.164 ou e-mail).
  final String? identifiantNormalise;

  final bool enCours;

  /// Code d'erreur métier, à traduire à l'affichage.
  final String? codeErreur;

  EtatConnexion copierAvec({
    EtapeConnexion? etape,
    CanalOtp? canal,
    String? indicatifPays,
    String? identifiantNormalise,
    bool? enCours,
    String? codeErreur,
    bool effacerErreur = false,
  }) {
    return EtatConnexion(
      etape: etape ?? this.etape,
      canal: canal ?? this.canal,
      indicatifPays: indicatifPays ?? this.indicatifPays,
      identifiantNormalise: identifiantNormalise ?? this.identifiantNormalise,
      enCours: enCours ?? this.enCours,
      codeErreur: effacerErreur ? null : (codeErreur ?? this.codeErreur),
    );
  }
}

/// Contrôleur du parcours OTP.
///
/// Le contrôleur ne décide de rien : il normalise l'entrée (E.164 avant tout
/// appel, ch. 5.4.1), appelle le port et transporte le code d'erreur renvoyé
/// par le serveur.
class ConnexionController extends Notifier<EtatConnexion> {
  @override
  EtatConnexion build() => const EtatConnexion();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  void choisirCanal(CanalOtp canal) {
    state = state.copierAvec(canal: canal, effacerErreur: true);
  }

  void choisirIndicatif(String indicatif) {
    state = state.copierAvec(indicatifPays: indicatif, effacerErreur: true);
  }

  /// Revient à la saisie de l'identifiant (bouton « modifier le numéro »).
  void recommencer() {
    state = EtatConnexion(canal: state.canal, indicatifPays: state.indicatifPays);
  }

  /// Normalise puis demande l'envoi du code. [saisie] est le numéro local ou
  /// l'adresse e-mail, tels que tapés par l'utilisateur.
  Future<void> demanderCode(String saisie) async {
    final identifiant = _normaliser(saisie);
    if (identifiant == null) {
      state = state.copierAvec(codeErreur: 'IDENTIFIANT_INVALIDE');
      return;
    }

    state = state.copierAvec(
      enCours: true,
      effacerErreur: true,
      identifiantNormalise: identifiant,
    );

    try {
      await _repo.demanderCode(identifiant: identifiant, canal: state.canal);
      state = state.copierAvec(
        enCours: false,
        etape: state.canal.demandeSaisieCode
            ? EtapeConnexion.code
            : EtapeConnexion.lienEnvoye,
      );
    } on ErreurAuth catch (e) {
      state = state.copierAvec(enCours: false, codeErreur: e.code);
    }
  }

  /// Vérifie le code saisi et ouvre la session.
  Future<void> verifierCode(String code) async {
    final identifiant = state.identifiantNormalise;
    if (identifiant == null) {
      state = state.copierAvec(codeErreur: 'IDENTIFIANT_INVALIDE');
      return;
    }

    state = state.copierAvec(enCours: true, effacerErreur: true);

    try {
      await _repo.verifierCode(
        identifiant: identifiant,
        canal: state.canal,
        code: code.trim(),
      );
      state = state.copierAvec(enCours: false);
      // La session vient de changer : la garde relit profil, fiche et
      // rattachements plutôt que de supposer l'état d'arrivée.
      ref.rafraichirSession();
    } on ErreurAuth catch (e) {
      state = state.copierAvec(enCours: false, codeErreur: e.code);
    }
  }

  /// Normalisation selon l'entrée du canal choisi.
  String? _normaliser(String saisie) {
    if (state.canal.entree == TypeIdentifiant.telephone) {
      return Validators.normalizeE164(
        indicatifPays: state.indicatifPays,
        numeroLocal: saisie,
      );
    }
    final email = saisie.trim().toLowerCase();
    return _motifEmail.hasMatch(email) ? email : null;
  }

  static final RegExp _motifEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$');
}

final connexionControllerProvider =
    NotifierProvider<ConnexionController, EtatConnexion>(
  ConnexionController.new,
);

/// Traduction des codes d'erreur en messages utilisateur.
///
/// Table unique, pour que la formulation ne diverge pas d'un écran à l'autre.
String messageErreurAuth(String code) => switch (code) {
      'IDENTIFIANT_INVALIDE' =>
        'Identifiant invalide. Vérifiez le numéro ou l’adresse e-mail.',
      'ROLE_DEJA_DEFINI' => 'Votre rôle a déjà été défini.',
      'ROLE_NON_AUTO_INSCRIPTIBLE' =>
        'Ce rôle s’obtient par invitation de votre établissement.',
      'TROP_DE_TENTATIVES' =>
        'Trop de tentatives. Réessayez dans une heure.',
      'LIAISON_IMPOSSIBLE' =>
        'Aucune fiche ne correspond à ce matricule et à cette date de naissance.',
      'ETABLISSEMENT_NON_MEMBRE' =>
        'Vous n’êtes pas membre de cet établissement.',
      'INVITATION_EXPIREE' => 'Cette invitation a expiré.',
      'INVITATION_DEJA_TRAITEE' => 'Cette invitation a déjà été utilisée.',
      'INVITATION_AUTRE_DESTINATAIRE' =>
        'Cette invitation ne vous est pas destinée.',
      'AUTH_REQUISE' => 'Votre session a expiré, reconnectez-vous.',
      'CANAL_SANS_CODE' =>
        'Ce canal ouvre la session depuis le lien reçu, sans code.',
      _ => 'Une erreur est survenue. Réessayez.',
    };
