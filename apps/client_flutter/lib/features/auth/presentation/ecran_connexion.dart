import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../application/auth_providers.dart';
import '../application/connexion_controller.dart';
import '../domain/canal_otp.dart';

/// Écran de connexion (REG-16).
///
/// 1. **Continuer avec Google** : le téléphone propose ses comptes Google,
///    on touche le sien, aucune saisie. À l'ouverture de l'écran, un compte
///    qui a déjà autorisé EcoShop est proposé d'office (feuille du système).
/// 2. **Code par e-mail** : l'adresse est suggérée par le clavier (comptes
///    du téléphone), un code à 6 chiffres arrive par courriel.
///
/// La connexion par SMS est suspendue (coût) ; elle reste dans le code et
/// se réaffiche avec `--dart-define=CONNEXION_TELEPHONE=true`. Le numéro
/// est demandé après la connexion, pour compléter le profil.
class EcranConnexion extends ConsumerStatefulWidget {
  const EcranConnexion({super.key});

  @override
  ConsumerState<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends ConsumerState<EcranConnexion> {
  final _identifiantCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Compte Google déjà autorisé sur ce téléphone : proposé tout de suite.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final etat = ref.read(connexionControllerProvider);
      if (etat.etape == EtapeConnexion.identifiant) {
        ref.read(connexionControllerProvider.notifier).connecterAvecGoogle(silencieux: true);
      }
    });
  }

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
    final google = ref.watch(connexionGoogleProvider).disponible;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
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
                      etat.etape == EtapeConnexion.identifiant
                          ? 'Connectez-vous en quelques secondes'
                          : 'Vérifiez votre adresse',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    if (etat.etape == EtapeConnexion.identifiant) ...[
                      if (google) ...[
                        _BoutonGoogle(
                          enCours: etat.enCours,
                          onPressed: () => controleur.connecterAvecGoogle(),
                        ),
                        const SizedBox(height: 20),
                        const _Separateur(),
                        const SizedBox(height: 20),
                      ],
                      _SaisieIdentifiant(
                        etat: etat,
                        controleur: controleur,
                        champ: _identifiantCtrl,
                      ),
                    ] else if (etat.etape == EtapeConnexion.code)
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
      ),
    );
  }
}

class _BoutonGoogle extends StatelessWidget {
  const _BoutonGoogle({required this.enCours, required this.onPressed});

  final bool enCours;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('bouton_google'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      onPressed: enCours ? null : onPressed,
      icon: const Icon(Icons.account_circle_outlined),
      label: const Text('Continuer avec Google'),
    );
  }
}

class _Separateur extends StatelessWidget {
  const _Separateur();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('ou recevez un code par e-mail', style: style),
        ),
        const Expanded(child: Divider()),
      ],
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
        if (Env.connexionTelephone) ...[
          SegmentedButton<TypeIdentifiant>(
            segments: const [
              ButtonSegment(
                value: TypeIdentifiant.email,
                label: Text('E-mail'),
                icon: Icon(Icons.alternate_email),
              ),
              ButtonSegment(
                value: TypeIdentifiant.telephone,
                label: Text('Téléphone'),
                icon: Icon(Icons.smartphone),
              ),
            ],
            selected: {etat.canal.entree},
            onSelectionChanged: (selection) {
              controleur.choisirCanal(
                selection.first == TypeIdentifiant.email ? CanalOtp.emailOtp : CanalOtp.sms,
              );
              champ.clear();
            },
          ),
          const SizedBox(height: 20),
        ],
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
                key: const Key('champ_identifiant'),
                controller: champ,
                keyboardType: parTelephone ? TextInputType.phone : TextInputType.emailAddress,
                autofillHints: parTelephone
                    ? const [AutofillHints.telephoneNumberNational]
                    : const [AutofillHints.email],
                autocorrect: false,
                textInputAction: TextInputAction.go,
                decoration: InputDecoration(
                  labelText: parTelephone ? 'Numéro' : 'Adresse e-mail',
                  hintText: parTelephone ? '620 00 00 00' : 'vous@exemple.com',
                  prefixIcon: Icon(parTelephone ? Icons.smartphone : Icons.alternate_email),
                ),
                onSubmitted: etat.enCours ? null : controleur.demanderCode,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('bouton_recevoir_code'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: etat.enCours ? null : () => controleur.demanderCode(champ.text),
          child: etat.enCours ? const _Patienter() : const Text('Recevoir le code'),
        ),
        const SizedBox(height: 12),
        Text(
          'Pas de mot de passe à retenir : un code à 6 chiffres vous est envoyé à chaque connexion.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SaisieCode extends StatefulWidget {
  const _SaisieCode({
    required this.etat,
    required this.controleur,
    required this.champ,
  });

  final EtatConnexion etat;
  final ConnexionController controleur;
  final TextEditingController champ;

  @override
  State<_SaisieCode> createState() => _SaisieCodeState();
}

class _SaisieCodeState extends State<_SaisieCode> {
  static const _attenteRenvoi = 60;
  int _restant = _attenteRenvoi;
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _demarrer();
  }

  void _demarrer() {
    _minuteur?.cancel();
    _restant = _attenteRenvoi;
    _minuteur = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _restant--);
      if (_restant <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  void _valider(String code) {
    if (widget.etat.enCours) return;
    widget.controleur.verifierCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final etat = widget.etat;
    final parEmail = etat.canal.entree == TypeIdentifiant.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Code envoyé à ${etat.identifiantNormalise}',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        if (parEmail) ...[
          const SizedBox(height: 4),
          Text(
            'Il arrive en moins d’une minute. Regardez aussi dans « Spam » ou « Promotions ».',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          key: const Key('champ_code'),
          controller: widget.champ,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          decoration: const InputDecoration(labelText: 'Code à 6 chiffres', counterText: ''),
          // Six chiffres saisis (ou collés) : validation sans autre geste.
          onChanged: (v) {
            if (v.length == 6) _valider(v);
          },
          onSubmitted: _valider,
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: etat.enCours ? null : () => _valider(widget.champ.text),
          child: etat.enCours ? const _Patienter() : const Text('Valider'),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: etat.enCours || _restant > 0
                  ? null
                  : () {
                      widget.champ.clear();
                      widget.controleur.renvoyerCode();
                      _demarrer();
                    },
              child: Text(_restant > 0 ? 'Renvoyer le code (${_restant}s)' : 'Renvoyer le code'),
            ),
            TextButton(
              onPressed: etat.enCours
                  ? null
                  : () {
                      widget.champ.clear();
                      widget.controleur.recommencer();
                    },
              child: Text(parEmail ? 'Changer d’adresse' : 'Changer de numéro'),
            ),
          ],
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
          child: const Text('Utiliser une autre adresse'),
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
