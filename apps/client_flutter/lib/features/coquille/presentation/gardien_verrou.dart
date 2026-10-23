import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/securite/delais_verrouillage.dart';
import '../../../core/securite/gardien_actions_sensibles.dart';
import '../../auth/application/auth_providers.dart';
import '../application/verrou_controller.dart';
import 'ecran_verrou.dart';
import 'pave_code.dart';

/// Navigateur de l'application : le verrou est posé au-dessus de lui, pour
/// couvrir aussi les pages ouvertes par-dessus l'accueil.
final cleNavigateurRacine = GlobalKey<NavigatorState>();

/// Branche le verrou (REG-18) sur toute l'application (`MaterialApp.builder`,
/// au-dessus du navigateur) :
///
/// - verrouillée : l'écran de verrouillage couvre toutes les pages ; elles ne
///   sont ni lues par l'accessibilité ni animées derrière ;
/// - arrière-plan ou écran éteint : le délai du rôle démarre ; au retour,
///   l'application est verrouillée s'il est écoulé ;
/// - dès que l'application n'est plus au premier plan, un écran uni cache
///   son contenu (liste des applications récentes) ;
/// - actions sensibles : le code est demandé dans une feuille
///   ([GardienActionsSensibles]) ;
/// - session fermée depuis le verrou (5 codes faux, « Code oublié », « Ce
///   n'est pas moi ») : retour à la première page ;
/// - Android : aperçu des applications récentes désactivé (13 et plus) ;
///   captures d'écran bloquées pour le personnel avant Android 13
///   ([DelaisVerrouillage.protegerCaptures]).
class GardienVerrou extends ConsumerStatefulWidget {
  const GardienVerrou({super.key, required this.navigateur, required this.child});

  final GlobalKey<NavigatorState> navigateur;
  final Widget child;

  @override
  ConsumerState<GardienVerrou> createState() => _GardienVerrouState();
}

class _GardienVerrouState extends ConsumerState<GardienVerrou> {
  static const _canalEcran = MethodChannel('ecoshop/ecran');

  late final AppLifecycleListener _ecouteur;
  bool _cache = false;

  @override
  void initState() {
    super.initState();
    _ecouteur = AppLifecycleListener(
      onInactive: () => _cacher(true),
      onHide: _enArrierePlan,
      onPause: _enArrierePlan,
      onShow: _auPremierPlan,
      onResume: _auPremierPlan,
    );
    ref.listenManual(verrouControllerProvider.select((e) => e.phase != PhaseVerrou.inactif), (avant, actif) {
      GardienActionsSensibles.brancher(actif ? _demanderCode : null);
      if (avant == true && !actif) widget.navigateur.currentState?.popUntil((route) => route.isFirst);
    }, fireImmediately: true);
    ref.listenManual(
      profilProvider.select((p) => p.valueOrNull?.roleRacine?.code),
      (_, role) => _protegerEcran(role),
      fireImmediately: true,
    );
  }

  void _cacher(bool cache) {
    if (_cache != cache && mounted) setState(() => _cache = cache);
  }

  void _enArrierePlan() {
    _cacher(true);
    ref.read(verrouControllerProvider.notifier).enArrierePlan();
  }

  void _auPremierPlan() {
    ref.read(verrouControllerProvider.notifier).auPremierPlan();
    _cacher(false);
  }

  Future<bool> _demanderCode(String motif) async {
    final contexte = widget.navigateur.currentContext;
    if (contexte == null || !contexte.mounted) return false;
    return demanderCodeAction(contexte, ref, motif);
  }

  Future<void> _protegerEcran(String? role) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _canalEcran.invokeMethod<void>('proteger', {
        'captures': role != null && DelaisVerrouillage.protegerCaptures([role]),
      });
    } on MissingPluginException {
      // Tests et plateformes sans le canal : rien à protéger.
    } on PlatformException catch (e) {
      debugPrint('Protection de l’écran indisponible : $e');
    }
  }

  @override
  void dispose() {
    _ecouteur.dispose();
    GardienActionsSensibles.brancher(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(verrouControllerProvider.select((e) => e.phase));
    final verrouille = phase == PhaseVerrou.verrouille;
    final theme = Theme.of(context);

    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        ExcludeSemantics(
          excluding: verrouille,
          child: TickerMode(enabled: !verrouille, child: widget.child),
        ),
        if (verrouille)
          Positioned.fill(
            // Navigateur à lui : dialogues « Code oublié », « Ce n'est pas moi ».
            // Sans animations « Hero » : celles-ci appartiennent au navigateur
            // de l'application.
            child: HeroControllerScope.none(
              child: Navigator(
                key: const ValueKey('navigateur_verrou'),
                onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const EcranVerrou()),
              ),
            ),
          ),
        if (_cache && phase != PhaseVerrou.inactif)
          Positioned.fill(
            child: ColoredBox(
              key: const ValueKey('cache_verrou'),
              color: theme.colorScheme.primary,
              child: Center(child: Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.onPrimary)),
            ),
          ),
      ],
    );
  }
}
