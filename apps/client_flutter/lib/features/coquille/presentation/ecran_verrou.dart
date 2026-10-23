import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/securite/code_secret.dart';
import '../../auth/application/auth_providers.dart';
import '../application/verrou_controller.dart';
import 'pave_code.dart';

/// Écran d'ouverture d'un téléphone déjà connu (REG-18) : « Bonjour Awa »,
/// pavé numérique qui monte du bas de l'écran, empreinte si activée, « Ce
/// n'est pas moi » et « Code oublié ». Le contenu de l'application n'est
/// pas construit derrière.
class EcranVerrou extends ConsumerStatefulWidget {
  const EcranVerrou({super.key});

  @override
  ConsumerState<EcranVerrou> createState() => _EcranVerrouState();
}

class _EcranVerrouState extends ConsumerState<EcranVerrou> {
  @override
  void initState() {
    super.initState();
    // Empreinte proposée tout de suite si elle est activée.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(verrouControllerProvider).biometrieActivee) _biometrie();
    });
  }

  Future<void> _biometrie() => ref.read(verrouControllerProvider.notifier).deverrouillerParBiometrie();

  Future<void> _confirmer({
    required String titre,
    required String texte,
    required Future<void> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogue) => AlertDialog(
        title: Text(titre),
        content: Text(texte),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogue).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(dialogue).pop(true), child: const Text('Continuer')),
        ],
      ),
    );
    if (ok == true) await action();
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(verrouControllerProvider);
    final controleur = ref.read(verrouControllerProvider.notifier);
    final prenom = ref.watch(profilProvider).valueOrNull?.prenom;
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.colorScheme.primary,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.onPrimary),
                      const SizedBox(height: 12),
                      Text(
                        prenom == null || prenom.isEmpty ? 'Bonjour' : 'Bonjour $prenom',
                        style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.onPrimary),
                      ),
                      TextButton(
                        onPressed: () => _confirmer(
                          titre: 'Ce n’est pas vous ?',
                          texte: 'Vous allez être déconnecté de ce compte. Vous pourrez vous connecter avec le vôtre.',
                          action: controleur.ceNestPasMoi,
                        ),
                        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onPrimary),
                        child: const Text('Ce n’est pas moi'),
                      ),
                    ],
                  ),
                ),
              ),
              // Feuille qui monte du bas, comme les applications de paiement.
              TweenAnimationBuilder<Offset>(
                tween: Tween(begin: const Offset(0, 1), end: Offset.zero),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, decalage, enfant) => FractionalTranslation(translation: decalage, child: enfant),
                child: Material(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PaveCode(
                            titre: 'Votre code secret',
                            surBiometrie: etat.biometrieActivee ? _biometrie : null,
                            surCode: (code) async {
                              final resultat = await controleur.saisirCode(code);
                              return switch (resultat) {
                                CodeFaux(:final essaisRestants) => messageCodeFaux(essaisRestants),
                                _ => null,
                              };
                            },
                          ),
                          TextButton(
                            onPressed: () => _confirmer(
                              titre: 'Code oublié',
                              texte:
                                  'Vous allez recevoir un code par e-mail (ou utiliser Google) pour prouver '
                                  'que c’est bien vous, puis choisir un nouveau code secret.',
                              action: controleur.codeOublie,
                            ),
                            child: const Text('Code oublié'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
