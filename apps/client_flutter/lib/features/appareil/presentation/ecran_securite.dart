import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coquille/presentation/pave_code.dart';
import '../application/appareil_providers.dart';
import 'ecran_code_compte.dart';

/// Mon profil › Sécurité (REG-22).
class EcranSecurite extends ConsumerWidget {
  const EcranSecurite({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(etatAppareilProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Sécurité')),
      body: ListView(
        children: [
          ListTile(
            key: const Key('menu_changer_code_compte'),
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Changer le code du compte'),
            subtitle: const Text('Le même code sur tous vos appareils ; demandé sur tout nouvel appareil'),
            trailing: const Icon(Icons.chevron_right),
            enabled: etat?.aUnCode ?? false,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranChangerCodeCompte())),
          ),
          if (etat != null && etat.bloque)
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Nouveaux appareils bloqués'),
              subtitle: Text(texteBlocage(etat)),
            ),
        ],
      ),
    );
  }
}

/// Ancien code, puis nouveau code (deux fois). En ligne, depuis un appareil
/// connu. Lève aussi un blocage « Ce n'est pas moi ».
class EcranChangerCodeCompte extends ConsumerStatefulWidget {
  const EcranChangerCodeCompte({super.key});

  @override
  ConsumerState<EcranChangerCodeCompte> createState() => _EcranChangerCodeCompteState();
}

class _EcranChangerCodeCompteState extends ConsumerState<EcranChangerCodeCompte> {
  String? _ancien;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Changer le code du compte')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _ancien == null
                ? PaveCode(
                    key: const Key('pave_ancien_code'),
                    titre: 'Code actuel du compte',
                    surCode: (code) async {
                      setState(() => _ancien = code);
                      return null;
                    },
                  )
                : ChoixNouveauCode(
                    titre: 'Nouveau code du compte',
                    retour: () => setState(() => _ancien = null),
                    valider: (code) async {
                      try {
                        await ref.read(appareilControllerProvider).changerCode(_ancien!, code);
                      } catch (e) {
                        setState(() => _ancien = null);
                        return messageErreur(e);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Code changé. Vos autres appareils vous le demanderont une fois.'),
                        ));
                        Navigator.of(context).pop();
                      }
                      return null;
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
