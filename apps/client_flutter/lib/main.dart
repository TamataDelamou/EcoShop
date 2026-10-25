import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/erreurs/gestion_erreurs.dart';
import 'core/offline/client_avec_delai.dart';
import 'core/theme/app_palette.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_variant.dart';
import 'core/theme/ambiance_visuelle.dart';
import 'features/accessibilite/application/accessibilite_providers.dart';
import 'features/accessibilite/domain/echelle_texte.dart';
import 'features/coquille/presentation/garde_session.dart';
import 'features/coquille/presentation/gardien_verrou.dart';
import 'features/push/data/firebase_messagerie_push.dart';
import 'features/themes/application/theme_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Plus d'écran gris : écran d'erreur lisible et erreur écrite au journal.
  GestionErreurs.installer(navigateur: cleNavigateurRacine);

  // Initialisation conditionnelle : sans --dart-define, l'app démarre en mode
  // diagnostic (aucun appel réseau), conformément à Env.estConfigure.
  if (Env.estConfigure) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
      // Délai maximum par requête : un serveur injoignable ne fait plus
      // attendre l'ouverture (renouvellement du jeton compris).
      httpClient: ClientAvecDelai(http.Client()),
    );
    // Notifications push (téléphones) : éteintes sans configuration Firebase.
    await InitialisationPush.initialiser();
  }

  runApp(const RedemarrageApplication(child: ProviderScope(child: EcoShopApp())));
}

class EcoShopApp extends ConsumerWidget {
  const EcoShopApp({super.key, this.configure});

  /// Application branchée sur Supabase ; par défaut [Env.estConfigure].
  /// Forcé à vrai par les tests qui montent l'application entière.
  final bool? configure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estConfigure = configure ?? Env.estConfigure;
    // Mode diagnostic (aucun --dart-define) : les providers de thème dérivent
    // de l'établissement actif, lui-même dérivé de la session Supabase — les
    // regarder ici planterait sur `Supabase.instance` jamais initialisé. On
    // retombe alors sur la charte par défaut, exactement comme avant M15bis.
    final variante = estConfigure
        ? ref.watch(themeVariantProvider)
        : AppThemeVariant.francophoneCfa;
    final mode = estConfigure
        ? ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system
        : ThemeMode.system;
    // Accessibilité (D4, §34.9) : mêmes garde-fous qu'au-dessus en mode
    // diagnostic — regarder ces providers sans Supabase planterait sur des
    // dépendances jamais initialisées.
    final contrasteEleve = estConfigure
        ? ref.watch(contrasteEleveProvider).valueOrNull ?? false
        : false;
    final echelleTexte = estConfigure
        ? ref.watch(echelleTexteProvider).valueOrNull ?? EchelleTexte.normal
        : EchelleTexte.normal;
    // Identité de l'établissement (REG-07 B) et ambiance personnelle
    // (REG-07 C) — mêmes garde-fous qu'au-dessus en mode diagnostic.
    final ambiance = estConfigure
        ? ref.watch(ambianceProvider).valueOrNull ?? AmbianceVisuelle.etablissement
        : AmbianceVisuelle.etablissement;
    final couleurEtablissement = estConfigure ? ref.watch(identiteEtablissementProvider).couleur : null;

    return MaterialApp(
      title: 'EcoShop',
      theme: construireThemeData(
        variante,
        Brightness.light,
        contrasteEleve: contrasteEleve,
        ambiance: ambiance,
        couleurEtablissement: couleurEtablissement,
      ),
      darkTheme: construireThemeData(
        variante,
        Brightness.dark,
        contrasteEleve: contrasteEleve,
        ambiance: ambiance,
        couleurEtablissement: couleurEtablissement,
      ),
      themeMode: mode,
      debugShowCheckedModeBanner: false,
      navigatorKey: cleNavigateurRacine,
      // Taille de texte (D4, §34.9) : appliquée globalement via le
      // `textScaler` ambiant plutôt qu'écran par écran — un seul point
      // d'application, cohérent avec tout le reste de l'app (y compris les
      // écrans qui n'ont pas encore été retouchés depuis D1).
      builder: (context, enfant) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(echelleTexte.facteur)),
          // Verrou (REG-18) au-dessus du navigateur : il couvre aussi les
          // pages ouvertes par-dessus l'accueil.
          child: estConfigure ? GardienVerrou(navigateur: cleNavigateurRacine, child: enfant!) : enfant!,
        );
      },
      // Sans configuration Supabase, aucun provider d'authentification ne peut
      // fonctionner : on affiche l'écran de diagnostic du socle plutôt que de
      // laisser l'application planter sur `Supabase.instance`.
      home: estConfigure ? const RacineApp() : const AccueilSocle(),
    );
  }
}

/// Écran technique de diagnostic du socle, affiché lorsque l'application est
/// lancée sans `--dart-define=SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY`.
class AccueilSocle extends StatelessWidget {
  const AccueilSocle({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('EcoShop — Socle')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('EcoShop', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text('Supabase non configuré (--dart-define requis)'),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              children: [
                _Pastille(palette.primaire),
                _Pastille(palette.accent),
                _Pastille(palette.succes),
                _Pastille(palette.premium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille(this.couleur);

  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(backgroundColor: couleur, radius: 16);
  }
}
