import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/e164_validator.dart';
import '../../coquille/application/verrou_controller.dart';
import '../data/connexion_google.dart';
import '../domain/auth_repository.dart';
import '../domain/canal_otp.dart';
import '../domain/identifiant_ecoshop.dart';
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
    // Code par e-mail par défaut : la connexion par SMS est suspendue
    // (REG-16), elle reste dans le code pour être rouverte.
    this.canal = CanalOtp.emailOtp,
    this.indicatifPays = '+224',
    this.identifiantNormalise,
    this.parIdentifiantEcoshop = false,
    this.adresseMasquee,
    this.enCours = false,
    this.connecte = false,
    this.codeErreur,
  });

  final EtapeConnexion etape;
  final CanalOtp canal;

  /// Indicatif pays sélectionné pour l'entrée téléphone.
  final String indicatifPays;

  /// Identifiant effectivement transmis à Supabase (E.164 ou e-mail).
  final String? identifiantNormalise;

  /// Connexion avec l'identifiant EcoShop (REG-18) : le code part à l'adresse
  /// du compte, que le téléphone ne voit que masquée.
  final bool parIdentifiantEcoshop;

  /// « a•••@gmail.com » : adresse où le code a été envoyé (identifiant).
  final String? adresseMasquee;

  final bool enCours;

  /// Session ouverte par ce parcours : plus rien à envoyer au serveur. Un
  /// second appui sur « Valider » renverrait un code déjà utilisé, refusé
  /// comme « expiré ».
  final bool connecte;

  /// Code d'erreur métier, à traduire à l'affichage.
  final String? codeErreur;

  EtatConnexion copierAvec({
    EtapeConnexion? etape,
    CanalOtp? canal,
    String? indicatifPays,
    String? identifiantNormalise,
    bool? parIdentifiantEcoshop,
    String? adresseMasquee,
    bool? enCours,
    bool? connecte,
    String? codeErreur,
    bool effacerErreur = false,
  }) {
    return EtatConnexion(
      etape: etape ?? this.etape,
      canal: canal ?? this.canal,
      indicatifPays: indicatifPays ?? this.indicatifPays,
      identifiantNormalise: identifiantNormalise ?? this.identifiantNormalise,
      parIdentifiantEcoshop: parIdentifiantEcoshop ?? this.parIdentifiantEcoshop,
      adresseMasquee: adresseMasquee ?? this.adresseMasquee,
      enCours: enCours ?? this.enCours,
      connecte: connecte ?? this.connecte,
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
    if (state.canal.entree == TypeIdentifiant.email && IdentifiantEcoshop.ressemble(saisie)) {
      return _demanderCodeParIdentifiant(saisie);
    }
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

  /// Identifiant EcoShop : le serveur envoie le code à l'adresse du compte.
  /// Une faute de frappe (caractère de contrôle) est signalée sans appel.
  Future<void> _demanderCodeParIdentifiant(String saisie) async {
    final identifiant = IdentifiantEcoshop.normaliser(saisie);
    if (identifiant == null) {
      state = state.copierAvec(codeErreur: 'IDENTIFIANT_ECOSHOP_INVALIDE');
      return;
    }
    state = state.copierAvec(
      enCours: true,
      effacerErreur: true,
      identifiantNormalise: identifiant,
      parIdentifiantEcoshop: true,
    );
    try {
      final adresse = await _repo.demanderCodeParIdentifiant(identifiant);
      state = state.copierAvec(enCours: false, etape: EtapeConnexion.code, adresseMasquee: adresse);
    } on ErreurAuth catch (e) {
      state = state.copierAvec(enCours: false, codeErreur: e.code);
    }
  }

  /// Renvoie un code au même identifiant (déjà normalisé).
  Future<void> renvoyerCode() async {
    final identifiant = state.identifiantNormalise;
    if (identifiant == null || state.enCours || state.connecte) return;
    state = state.copierAvec(enCours: true, effacerErreur: true);
    try {
      if (state.parIdentifiantEcoshop) {
        await _repo.demanderCodeParIdentifiant(identifiant);
      } else {
        await _repo.demanderCode(identifiant: identifiant, canal: state.canal);
      }
      state = state.copierAvec(enCours: false);
    } on ErreurAuth catch (e) {
      state = state.copierAvec(enCours: false, codeErreur: e.code);
    }
  }

  /// Vérifie le code saisi et ouvre la session.
  Future<void> verifierCode(String code) async {
    if (state.enCours || state.connecte) return;
    final identifiant = state.identifiantNormalise;
    if (identifiant == null) {
      state = state.copierAvec(codeErreur: 'IDENTIFIANT_INVALIDE');
      return;
    }

    state = state.copierAvec(enCours: true, effacerErreur: true);
    _identiteVerifiee(true);

    try {
      if (state.parIdentifiantEcoshop) {
        await _repo.verifierCodeParIdentifiant(identifiant: identifiant, code: code.trim());
      } else {
        await _repo.verifierCode(
          identifiant: identifiant,
          canal: state.canal,
          code: code.trim(),
        );
      }
      state = state.copierAvec(enCours: false, connecte: true);
      // La session vient de changer : la garde relit profil, fiche et
      // rattachements plutôt que de supposer l'état d'arrivée.
      ref.rafraichirSession();
    } on ErreurAuth catch (e) {
      _identiteVerifiee(false);
      state = state.copierAvec(enCours: false, codeErreur: e.code);
    }
  }

  /// Connexion avec le compte Google du téléphone (REG-16).
  ///
  /// [silencieux] : tentative à l'ouverture de l'écran, pour un compte qui a
  /// déjà autorisé EcoShop ; aucune erreur n'est affichée si elle échoue,
  /// le bouton reste là.
  ///
  /// Une seule demande Google à la fois (REG-29) : un deuxième appel pendant
  /// qu'une feuille du système est ouverte (double appui, écran reconstruit)
  /// n'en ouvre pas une autre, qui resterait affichée derrière.
  Future<void> connecterAvecGoogle({bool silencieux = false}) {
    final google = ref.read(connexionGoogleProvider);
    if (!google.disponible || state.enCours || state.connecte) return Future.value();
    return _demandeGoogle ??= _connecterAvecGoogle(google, silencieux).whenComplete(() => _demandeGoogle = null);
  }

  Future<void>? _demandeGoogle;

  Future<void> _connecterAvecGoogle(ConnexionGoogle google, bool silencieux) async {
    if (!silencieux) state = state.copierAvec(enCours: true, effacerErreur: true);

    try {
      final jeton = silencieux ? await google.jetonSilencieux() : await google.jetonInteractif();
      if (jeton == null) {
        state = state.copierAvec(enCours: false);
        return;
      }
      state = state.copierAvec(enCours: true, effacerErreur: true);
      _identiteVerifiee(true);
      await _repo.connecterAvecGoogle(jeton);
      state = state.copierAvec(enCours: false, connecte: true);
      ref.rafraichirSession();
    } on ErreurAuth catch (e) {
      _identiteVerifiee(false);
      state = silencieux
          ? state.copierAvec(enCours: false)
          : state.copierAvec(enCours: false, codeErreur: e.code);
    } catch (_) {
      _identiteVerifiee(false);
      state = silencieux
          ? state.copierAvec(enCours: false)
          : state.copierAvec(enCours: false, codeErreur: 'GOOGLE_INDISPONIBLE');
    }
  }

  /// Identité prouvée à l'instant (code ou Google) : le verrou (REG-18)
  /// ouvre l'application sans redemander le code secret. Posé avant l'appel :
  /// la session peut s'ouvrir avant que l'appel ne rende la main.
  void _identiteVerifiee(bool valeur) => ref.read(identiteVerifieeProvider.notifier).state = valeur;

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
      'IDENTIFIANT_ECOSHOP_INVALIDE' =>
        'Identifiant EcoShop incorrect. Il a la forme EC-XXXX-XXX : vérifiez chaque caractère.',
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
      'GOOGLE_INDISPONIBLE' =>
        'Connexion Google impossible pour le moment. Recevez plutôt un code par e-mail.',
      'OTP_EXPIRED' => 'Code expiré ou incorrect. Demandez un nouveau code.',
      'OVER_EMAIL_SEND_RATE_LIMIT' || 'OVER_REQUEST_RATE_LIMIT' =>
        'Trop de demandes de code. Patientez une minute, puis réessayez.',
      'EMAIL_ADDRESS_INVALID' => 'Cette adresse e-mail n’est pas acceptée.',
      'TELEPHONE_INVALIDE' =>
        'Numéro invalide. Vérifiez l’indicatif et le numéro.',
      'TELEPHONE_DEJA_UTILISE' =>
        'Ce numéro est déjà confirmé sur un autre compte. Rapprochez-vous de l’école.',
      'TELEPHONE_NON_DECLARE' =>
        'Cette personne a changé de numéro entre-temps. Actualisez la liste.',
      'IDENTIFIANT_NON_VERIFIE' =>
        'Votre numéro n’est pas encore confirmé. Faites-le confirmer par l’école, '
            'ou demandez que l’invitation soit envoyée à votre adresse e-mail.',
      'CANAL_SANS_CODE' =>
        'Ce canal ouvre la session depuis le lien reçu, sans code.',
      _ => 'Une erreur est survenue. Réessayez.',
    };
