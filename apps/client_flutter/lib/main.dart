import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/theme/app_palette.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_variant.dart';
import 'features/coquille/presentation/garde_session.dart';
import 'features/themes/application/theme_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisation conditionnelle : sans --dart-define, l'app démarre en mode
  // diagnostic (aucun appel réseau), conformément à Env.estConfigure.
  if (Env.estConfigure) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    );
  }

  runApp(const ProviderScope(child: EcoShopApp()));
}

class EcoShopApp extends ConsumerWidget {
  const EcoShopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mode diagnostic (aucun --dart-define) : les providers de thème dérivent
    // de l'établissement actif, lui-même dérivé de la session Supabase — les
    // regarder ici planterait sur `Supabase.instance` jamais initialisé. On
    // retombe alors sur la charte par défaut, exactement comme avant M15bis.
    final variante = Env.estConfigure
        ? ref.watch(themeVariantProvider)
        : AppThemeVariant.francophoneCfa;
    final mode = Env.estConfigure
        ? ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system
        : ThemeMode.system;

    return MaterialApp(
      title: 'EcoShop',
      theme: construireThemeData(variante, Brightness.light),
      darkTheme: construireThemeData(variante, Brightness.dark),
      themeMode: mode,
      debugShowCheckedModeBanner: false,
      // Sans configuration Supabase, aucun provider d'authentification ne peut
      // fonctionner : on affiche l'écran de diagnostic du socle plutôt que de
      // laisser l'application planter sur `Supabase.instance`.
      home: Env.estConfigure ? const RacineApp() : const AccueilSocle(),
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
