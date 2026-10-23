import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/securite/code_secret.dart';
import '../application/verrou_controller.dart';
import 'pave_code.dart';

enum _Etape { choix, confirmation, biometrie }

/// Création du code secret (REG-18) : choix, confirmation, puis proposition
/// d'activer l'empreinte ou le visage. Obligatoire : nouveau compte, compte
/// créé avant REG-18, après « Code oublié » ou 5 codes faux.
class EcranCreationCode extends ConsumerStatefulWidget {
  const EcranCreationCode({super.key});

  @override
  ConsumerState<EcranCreationCode> createState() => _EcranCreationCodeState();
}

class _EcranCreationCodeState extends ConsumerState<EcranCreationCode> {
  _Etape _etape = _Etape.choix;
  String? _premier;
  bool _enCours = false;

  VerrouController get _controleur => ref.read(verrouControllerProvider.notifier);

  Future<String?> _choisir(String code) async {
    final refus = ReglesCode.verifierChoix(code);
    if (refus != null) return ReglesCode.message(refus);
    setState(() {
      _premier = code;
      _etape = _Etape.confirmation;
    });
    return null;
  }

  Future<String?> _confirmer(String code) async {
    if (code != _premier) {
      setState(() {
        _premier = null;
        _etape = _Etape.choix;
      });
      return 'Les deux codes sont différents. Recommencez.';
    }
    try {
      await _controleur.creerCode(code, ouvrir: false);
    } on CodeRefuse catch (e) {
      setState(() => _etape = _Etape.choix);
      return e.toString();
    }
    setState(() => _etape = _Etape.biometrie);
    return null;
  }

  Future<void> _terminer({required bool biometrie}) async {
    setState(() => _enCours = true);
    if (biometrie) {
      final ok = await _controleur.activerBiometrie();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Empreinte non activée. Vous pourrez l’activer plus tard dans « Mon profil ».')),
        );
      }
    }
    await _controleur.terminerCreation();
    if (mounted) setState(() => _enCours = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: switch (_etape) {
                  _Etape.choix => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pin_outlined, size: 40, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        'Sur ce téléphone, EcoShop s’ouvrira avec ce code. Ne le donnez à personne.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      PaveCode(
                        key: const ValueKey('choix'),
                        titre: 'Choisissez votre code secret',
                        sousTitre: '6 chiffres, sans suite évidente',
                        surCode: _choisir,
                      ),
                    ],
                  ),
                  _Etape.confirmation => PaveCode(
                    key: const ValueKey('confirmation'),
                    titre: 'Confirmez votre code secret',
                    surCode: _confirmer,
                  ),
                  _Etape.biometrie => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fingerprint, size: 56, color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        'Ouvrir avec l’empreinte ou le visage ?',
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Plus rapide que le code. Le code reste toujours possible.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _enCours ? null : () => _terminer(biometrie: true),
                        child: const Text('Activer'),
                      ),
                      TextButton(
                        onPressed: _enCours ? null : () => _terminer(biometrie: false),
                        child: const Text('Plus tard'),
                      ),
                    ],
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
