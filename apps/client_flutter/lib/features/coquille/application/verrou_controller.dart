import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/securite/biometrie.dart';
import '../../../core/securite/code_secret.dart';
import '../../../core/securite/coffre_fort.dart';
import '../../../core/securite/delais_verrouillage.dart';
import '../../auth/application/auth_providers.dart';
import 'session_logout.dart';

export '../../../core/securite/coffre_fort.dart' show coffreFortProvider, CoffreFortMemoire;

/// Verrou de l'application (REG-18, partie C).
///
/// On prouve son identité une fois par téléphone (code e-mail ou Google) ;
/// ensuite l'application s'ouvre avec le code secret de 6 chiffres ou
/// l'empreinte. Le verrou protège un téléphone laissé sans surveillance : le
/// serveur reste la seule autorité sur les droits (RLS inchangées).

/// Verrou en service. Faux sans configuration Supabase (mode diagnostic) et
/// dans les tests qui ne portent pas sur le verrou ; les tests du verrou le
/// surchargent à vrai.
final verrouActifProvider = Provider<bool>((ref) => Env.estConfigure);

// `coffreFortProvider` vit dans le socle (`core/securite/coffre_fort.dart`) :
// la file d'envoi s'en sert aussi. Réexporté pour les appelants existants.

final serviceCodeSecretProvider = Provider<ServiceCodeSecret>(
  (ref) => ServiceCodeSecret(coffre: ref.watch(coffreFortProvider)),
);

final biometrieProvider = Provider<Biometrie>((ref) => BiometrieSysteme(ref.watch(coffreFortProvider)));

/// Heure courante (surchargée en test pour faire passer le temps).
final horlogeVerrouProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Identité vérifiée à l'instant sur ce téléphone (code e-mail ou Google) :
/// l'application s'ouvre sans redemander le code secret. Remis à faux dès
/// que le verrou l'a lu.
final identiteVerifieeProvider = StateProvider<bool>((ref) => false);

/// Compte protégé par le verrou : seulement son identifiant, pour que relire
/// le profil (choix du rôle, établissement) ne referme pas le verrou.
final compteVerrouProvider = Provider<String?>((ref) {
  if (!ref.watch(verrouActifProvider)) return null;
  if (!ref.watch(sessionOuverteProvider)) return null;
  return ref.watch(profilProvider.select((p) => p.valueOrNull?.id));
});

enum PhaseVerrou {
  /// Pas de compte connecté, ou verrou hors service.
  inactif,

  /// Lecture du coffre en cours.
  chargement,

  /// Aucun code sur ce téléphone pour ce compte : à créer (nouveau compte,
  /// compte d'avant REG-18, après « Code oublié » ou 5 échecs).
  codeACreer,

  /// Contenu caché : code ou empreinte demandés.
  verrouille,

  /// Application ouverte.
  ouvert,
}

class EtatVerrou {
  const EtatVerrou(this.phase, {this.compteId, this.biometrieActivee = false, this.essaisRestants});

  final PhaseVerrou phase;
  final String? compteId;
  final bool biometrieActivee;

  /// Après un code faux : essais restants avant la fermeture de la session.
  final int? essaisRestants;

  EtatVerrou copierAvec({
    PhaseVerrou? phase,
    bool? biometrieActivee,
    int? essaisRestants,
    bool effacerEssais = false,
  }) => EtatVerrou(
    phase ?? this.phase,
    compteId: compteId,
    biometrieActivee: biometrieActivee ?? this.biometrieActivee,
    essaisRestants: effacerEssais ? null : (essaisRestants ?? this.essaisRestants),
  );
}

class VerrouController extends Notifier<EtatVerrou> {
  DateTime? _depuis;

  ServiceCodeSecret get _codes => ref.read(serviceCodeSecretProvider);
  Biometrie get _biometrie => ref.read(biometrieProvider);
  DateTime _maintenant() => ref.read(horlogeVerrouProvider)();

  @override
  EtatVerrou build() {
    final compteId = ref.watch(compteVerrouProvider);
    _depuis = null;
    if (compteId == null) return const EtatVerrou(PhaseVerrou.inactif);
    unawaited(_initialiser(compteId));
    return EtatVerrou(PhaseVerrou.chargement, compteId: compteId);
  }

  Future<void> _initialiser(String compteId) async {
    final identiteVerifiee = ref.read(identiteVerifieeProvider);
    final existe = await _codes.existe(compteId);
    // Après la première attente : un provider ne se modifie pas pendant la
    // construction d'un autre.
    if (identiteVerifiee) ref.read(identiteVerifieeProvider.notifier).state = false;
    final bio = existe && await _biometrie.estActivee(compteId);
    if (state.compteId != compteId) return; // Compte changé entre-temps.
    state = EtatVerrou(
      !existe
          ? PhaseVerrou.codeACreer
          // Ouverture de l'application : toujours verrouillée, sauf si
          // l'identité vient d'être prouvée par e-mail ou Google.
          : identiteVerifiee
          ? PhaseVerrou.ouvert
          : PhaseVerrou.verrouille,
      compteId: compteId,
      biometrieActivee: bio,
    );
  }

  /// Délai du compte : le plus court de ses rôles.
  Duration get delai {
    final role = ref.read(profilProvider).valueOrNull?.roleRacine?.code;
    return DelaisVerrouillage.pour([?role]);
  }

  /// Application en arrière-plan ou écran éteint : le délai démarre.
  void enArrierePlan() {
    if (state.phase == PhaseVerrou.ouvert) _depuis ??= _maintenant();
  }

  /// Retour au premier plan : verrouillée si le délai est écoulé.
  void auPremierPlan() {
    final depuis = _depuis;
    _depuis = null;
    if (state.phase != PhaseVerrou.ouvert || depuis == null) return;
    if (_maintenant().difference(depuis) >= delai) {
      state = state.copierAvec(phase: PhaseVerrou.verrouille, effacerEssais: true);
    }
  }

  /// Vérifie le code. Ne change pas l'écran sur un code bon pendant une
  /// action sensible ([pourAction]) : l'application était déjà ouverte.
  ///
  /// Au 5ᵉ code faux de suite : code oublié, session fermée sur ce téléphone
  /// et données locales purgées ; reconnexion par e-mail ou Google.
  Future<ResultatCode> saisirCode(String code, {bool pourAction = false}) async {
    final compteId = state.compteId;
    if (compteId == null) return const CodeBloque();
    final resultat = await _codes.verifier(compteId, code);
    switch (resultat) {
      case CodeBon():
        if (!pourAction) state = state.copierAvec(phase: PhaseVerrou.ouvert, effacerEssais: true);
      case CodeFaux(:final essaisRestants):
        state = state.copierAvec(essaisRestants: essaisRestants);
      case CodeBloque():
        await _fermerSession(compteId);
    }
    return resultat;
  }

  /// Ouverture par empreinte ou visage. Vrai si réussie.
  Future<bool> deverrouillerParBiometrie({bool pourAction = false}) async {
    final compteId = state.compteId;
    if (compteId == null || !state.biometrieActivee) return false;
    if (!await _biometrie.deverrouiller(compteId)) return false;
    if (!pourAction) state = state.copierAvec(phase: PhaseVerrou.ouvert, effacerEssais: true);
    return true;
  }

  /// Crée le code (premier code, ou nouveau après « Code oublié »). Lève
  /// [CodeRefuse] si le code est trop facile à deviner. L'écran reste sur la
  /// création ([ouvrir] faux) le temps de proposer l'empreinte.
  Future<void> creerCode(String code, {bool ouvrir = true}) async {
    final compteId = state.compteId;
    if (compteId == null) return;
    await _codes.creer(compteId, code);
    if (ouvrir) state = state.copierAvec(phase: PhaseVerrou.ouvert, effacerEssais: true);
  }

  /// Fin de la création du code (après la proposition de l'empreinte).
  Future<void> terminerCreation() async {
    final compteId = state.compteId;
    if (compteId == null || state.phase != PhaseVerrou.codeACreer) return;
    if (await _codes.existe(compteId)) {
      state = state.copierAvec(phase: PhaseVerrou.ouvert, effacerEssais: true);
    }
  }

  /// Propose l'empreinte après la création du code. Vrai si activée.
  Future<bool> activerBiometrie() async {
    final compteId = state.compteId;
    if (compteId == null) return false;
    final ok = await _biometrie.activer(compteId);
    state = state.copierAvec(biometrieActivee: ok);
    return ok;
  }

  Future<void> desactiverBiometrie() async {
    final compteId = state.compteId;
    if (compteId == null) return;
    await _biometrie.desactiver(compteId);
    state = state.copierAvec(biometrieActivee: false);
  }

  /// « Code oublié » : on reprouve son identité par e-mail ou Google, puis
  /// on choisit un nouveau code. Les opérations en attente d'envoi restent
  /// sur le téléphone (chiffrées pour ce compte).
  Future<void> codeOublie() async {
    final compteId = state.compteId;
    if (compteId != null) await _fermerSession(compteId);
  }

  /// « Ce n'est pas moi » : déconnexion, le code de ce compte reste sur le
  /// téléphone pour son retour.
  Future<void> ceNestPasMoi() => ref.deconnecterEtPurgerDonneesLocales();

  Future<void> _fermerSession(String compteId) async {
    await _codes.oublier(compteId);
    await _biometrie.desactiver(compteId);
    await ref.deconnecterEtPurgerDonneesLocales();
  }
}

final verrouControllerProvider = NotifierProvider<VerrouController, EtatVerrou>(VerrouController.new);
