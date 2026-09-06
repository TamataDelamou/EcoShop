import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/connexion_controller.dart';
import '../domain/canal_otp.dart';

/// Écran de connexion — parcours OTP (cahier v4.1, ch. 5.4).
///
/// Deux entrées (téléphone / e-mail) × quatre canaux. Le numéro est normalisé
/// en E.164 par le contrôleur avant tout appel réseau.
class EcranConnexion extends ConsumerStatefulWidget {
  const EcranConnexion({super.key});

  @override
  ConsumerState<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends ConsumerState<EcranConnexion> {
  final _identifiantCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _identifiantCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(connexionControllerProvider);
    final controleur = ref.read(connexionControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'EcoShop',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connexion sécurisée par code à usage unique',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (etat.etape == EtapeConnexion.identifiant)
                    _SaisieIdentifiant(
                      etat: etat,
                      controleur: controleur,
                      champ: _identifiantCtrl,
                    )
                  else if (etat.etape == EtapeConnexion.code)
                    _SaisieCode(
                      etat: etat,
                      controleur: controleur,
                      champ: _codeCtrl,
                    )
                  else
                    _LienEnvoye(etat: etat, controleur: controleur),
                  if (etat.codeErreur != null) ...[
                    const SizedBox(height: 16),
                    _Erreur(code: etat.codeErreur!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SaisieIdentifiant extends StatelessWidget {
  const _SaisieIdentifiant({
    required this.etat,
    required this.controleur,
    required this.champ,
  });

  final EtatConnexion etat;
  final ConnexionController controleur;
  final TextEditingController champ;

  @override
  Widget build(BuildContext context) {
    final parTelephone = etat.canal.entree == TypeIdentifiant.telephone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TypeIdentifiant>(
          segments: const [
            ButtonSegment(
              value: TypeIdentifiant.telephone,
              label: Text('Téléphone'),
              icon: Icon(Icons.smartphone),
            ),
            ButtonSegment(
              value: TypeIdentifiant.email,
              label: Text('E-mail'),
              icon: Icon(Icons.alternate_email),
            ),
          ],
          selected: {etat.canal.entree},
          onSelectionChanged: (selection) {
            // Changer d'entrée impose de repartir sur un canal compatible.
            controleur.choisirCanal(CanalOtp.pourEntree(selection.first).first);
            champ.clear();
          },
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (parTelephone) ...[
              SizedBox(
                width: 96,
                child: TextFormField(
                  initialValue: etat.indicatifPays,
                  decoration: const InputDecoration(labelText: 'Indicatif'),
                  keyboardType: TextInputType.phone,
                  onChanged: controleur.choisirIndicatif,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: TextField(
                controller: champ,
                autofocus: true,
                keyboardType: parTelephone
                    ? TextInputType.phone
                    : TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: parTelephone ? 'Numéro' : 'Adresse e-mail',
                  hintText: parTelephone ? '620 00 00 00' : 'vous@exemple.com',
                ),
                onSubmitted: etat.enCours ? null : controleur.demanderCode,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Recevoir le code par', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final canal in CanalOtp.pourEntree(etat.canal.entree))
              ChoiceChip(
                label: Text(canal.libelle),
                selected: etat.canal == canal,
                onSelected: (_) => controleur.choisirCanal(canal),
              ),
          ],
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed:
              etat.enCours ? null : () => controleur.demanderCode(champ.text),
          child: etat.enCours
              ? const _Patienter()
              : const Text('Recevoir le code'),
        ),
      ],
    );
  }
}

class _SaisieCode extends StatelessWidget {
  const _SaisieCode({
    required this.etat,
    required this.controleur,
    required this.champ,
  });

  final EtatConnexion etat;
  final ConnexionController controleur;
  final TextEditingController champ;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Code envoyé à ${etat.identifiantNormalise}',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: champ,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
          decoration: const InputDecoration(labelText: 'Code à 6 chiffres'),
          onSubmitted: etat.enCours ? null : controleur.verifierCode,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed:
              etat.enCours ? null : () => controleur.verifierCode(champ.text),
          child: etat.enCours ? const _Patienter() : const Text('Valider'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: etat.enCours
              ? null
              : () {
                  champ.clear();
                  controleur.recommencer();
                },
          child: const Text('Modifier l’identifiant'),
        ),
      ],
    );
  }
}

class _LienEnvoye extends StatelessWidget {
  const _LienEnvoye({required this.etat, required this.controleur});

  final EtatConnexion etat;
  final ConnexionController controleur;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 48),
        const SizedBox(height: 16),
        Text(
          'Un lien de connexion a été envoyé à ${etat.identifiantNormalise}. '
          'Ouvrez-le depuis cet appareil pour accéder à votre compte.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: controleur.recommencer,
          child: const Text('Utiliser un autre identifiant'),
        ),
      ],
    );
  }
}

class _Erreur extends StatelessWidget {
  const _Erreur({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: schema.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: schema.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              messageErreurAuth(code),
              style: TextStyle(color: schema.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _Patienter extends StatelessWidget {
  const _Patienter();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
