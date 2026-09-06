import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/coquille/presentation/garde_session.dart';

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

class EcoShopApp extends StatelessWidget {
  const EcoShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoShop',
      theme: appTheme(),
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
            const Wrap(
              spacing: 8,
              children: [
                _Pastille(AppColors.bleuElectrique),
                _Pastille(AppColors.orangePop),
                _Pastille(AppColors.vertMenthe),
                _Pastille(AppColors.dore),
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
