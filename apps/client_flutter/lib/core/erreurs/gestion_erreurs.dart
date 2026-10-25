import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Gestion des erreurs inattendues de l'application.
///
/// En version publiée, un widget qui plante pendant sa construction affiche
/// par défaut un rectangle gris, sans explication ni sortie. On le remplace
/// par un écran lisible avec « Revenir à l'accueil », et chaque erreur est
/// écrite dans le journal du téléphone (logcat Android, préfixe
/// `EcoShop-ERREUR`), y compris les erreurs asynchrones non attrapées.
abstract final class GestionErreurs {
  /// Dernières erreurs (les plus récentes en fin), pour les tests et le
  /// support : jamais envoyées au serveur.
  static final List<String> dernieres = <String>[];

  static const _maxGardees = 20;

  /// Reconstruit l'arbre de l'application (voir [RedemarrageApplication]).
  static VoidCallback? _redemarrer;

  /// Navigateur racine, pour revenir à l'accueil sans tout reconstruire.
  static GlobalKey<NavigatorState>? _navigateur;

  static void installer({GlobalKey<NavigatorState>? navigateur}) {
    _navigateur = navigateur;
    final precedent = FlutterError.onError;
    FlutterError.onError = (details) {
      enregistrer(details.exception, details.stack, contexte: details.context?.toDescription());
      if (kDebugMode) {
        (precedent ?? FlutterError.presentError)(details);
      }
    };
    PlatformDispatcher.instance.onError = (erreur, pile) {
      enregistrer(erreur, pile, contexte: 'erreur asynchrone non attrapée');
      return true;
    };
    ErrorWidget.builder = (details) => EcranErreurInattendue(details: details);
  }

  /// Écrit l'erreur dans le journal du téléphone.
  static void enregistrer(Object erreur, StackTrace? pile, {String? contexte}) {
    final ligne = 'EcoShop-ERREUR${contexte == null ? '' : ' ($contexte)'} : $erreur';
    dernieres.add(ligne);
    if (dernieres.length > _maxGardees) dernieres.removeAt(0);
    // debugPrint est conservé en version publiée : il va dans logcat.
    debugPrint(ligne);
    if (pile != null) debugPrint(pile.toString().split('\n').take(12).join('\n'));
    developer.log(ligne, name: 'EcoShop', error: erreur, stackTrace: pile, level: 1000);
  }

  /// « Revenir à l'accueil » : dépile jusqu'à la première page ; si l'erreur
  /// est sur la première page (ou au-dessus du navigateur), l'application
  /// est reconstruite.
  static void revenirAccueil() {
    final navigateur = _navigateur?.currentState;
    if (navigateur != null && navigateur.canPop()) {
      navigateur.popUntil((route) => route.isFirst);
      return;
    }
    _redemarrer?.call();
  }
}

/// Enveloppe la racine de l'application : « Revenir à l'accueil » peut la
/// reconstruire entièrement (nouvel état), quand l'erreur touche l'accueil
/// lui-même.
class RedemarrageApplication extends StatefulWidget {
  const RedemarrageApplication({super.key, required this.child});

  final Widget child;

  @override
  State<RedemarrageApplication> createState() => _RedemarrageApplicationState();
}

class _RedemarrageApplicationState extends State<RedemarrageApplication> {
  Key _cle = UniqueKey();

  @override
  void initState() {
    super.initState();
    GestionErreurs._redemarrer = () {
      if (mounted) setState(() => _cle = UniqueKey());
    };
  }

  @override
  void dispose() {
    GestionErreurs._redemarrer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _cle, child: widget.child);
}

/// Écran affiché à la place d'un widget qui a planté.
///
/// Autonome : il peut s'afficher au-dessus de l'application elle-même
/// (aucun thème ni direction de texte garantis), d'où ses couleurs et sa
/// [Directionality] explicites.
class EcranErreurInattendue extends StatelessWidget {
  const EcranErreurInattendue({super.key, this.details});

  final FlutterErrorDetails? details;

  @override
  Widget build(BuildContext context) {
    final sombre = MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
    final fond = sombre ? const Color(0xFF1C1B1F) : const Color(0xFFFFFBFE);
    final encre = sombre ? const Color(0xFFE6E1E5) : const Color(0xFF1C1B1F);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        key: const Key('ecran_erreur_inattendue'),
        color: fond,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: encre),
                const SizedBox(height: 12),
                Text(
                  'Un problème est survenu',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: encre, decoration: TextDecoration.none),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vos données enregistrées ne sont pas perdues.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: encre, decoration: TextDecoration.none),
                ),
                const SizedBox(height: 20),
                // Material propre : pas d'ancêtre Material garanti ici.
                Material(
                  color: const Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    key: const Key('bouton_revenir_accueil'),
                    borderRadius: BorderRadius.circular(24),
                    onTap: GestionErreurs.revenirAccueil,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Text(
                        'Revenir à l’accueil',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
