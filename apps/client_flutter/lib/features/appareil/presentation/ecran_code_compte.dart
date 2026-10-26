import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/securite/code_secret.dart';
import '../../coquille/application/session_logout.dart';
import '../../coquille/presentation/pave_code.dart';
import '../application/appareil_providers.dart';
import '../domain/etat_appareil.dart';

String _d2(int n) => n.toString().padLeft(2, '0');

/// « 27/10 à 14 h 05 ».
String dateHeure(DateTime d) => '${_d2(d.day)}/${_d2(d.month)} à ${heure(d)}';

/// « 14 h 05 ».
String heure(DateTime d) => '${d.hour} h ${_d2(d.minute)}';

String messageErreur(Object e) => e is ErreurCodeCompte ? e.message : 'Pas de connexion. Réessayez.';

/// Texte d'un blocage des nouveaux appareils.
String texteBlocage(EtatAppareil etat) => etat.bloquePasMoi
    ? 'Vous avez signalé une connexion qui n’était pas la vôtre : les nouveaux appareils sont bloqués '
        'jusqu’à ce que vous changiez le code depuis votre téléphone habituel.'
    : 'Trop de codes faux : les nouveaux appareils sont bloqués jusqu’au ${dateHeure(etat.bloqueJusquA!)}.';

enum _Vue { saisie, attente, recuperation, ecole, nouveauCode }

/// Nouvel appareil (REG-22) : le code du compte est demandé avant tout le
/// reste. « Code oublié ? » propose trois voies : autorisation depuis un
/// appareil connu, récupération par e-mail (48 h), déblocage à l'école.
class EcranCodeCompte extends ConsumerStatefulWidget {
  const EcranCodeCompte({super.key});

  @override
  ConsumerState<EcranCodeCompte> createState() => _EcranCodeCompteState();
}

class _EcranCodeCompteState extends ConsumerState<EcranCodeCompte> {
  _Vue? _vue;
  String? _message;
  bool _enCours = false;
  Timer? _relecture;

  AppareilController get _controleur => ref.read(appareilControllerProvider);

  @override
  void dispose() {
    _relecture?.cancel();
    super.dispose();
  }

  /// Vue de départ : celle de la demande en cours, s'il y en a une.
  _Vue _vueDe(EtatAppareil etat) {
    if (_vue != null) return _vue!;
    final approbation = etat.monApprobation;
    if (approbation != null && approbation.echeance.isAfter(DateTime.now())) return _Vue.attente;
    if (etat.maRecuperation != null) return _Vue.recuperation;
    return _Vue.saisie;
  }

  void _aller(_Vue vue) {
    _relecture?.cancel();
    if (vue == _Vue.attente) {
      // Relecture régulière : l'autre appareil peut autoriser à tout moment.
      _relecture = Timer.periodic(const Duration(seconds: 3), (_) => ref.invalidate(etatAppareilProvider));
    }
    setState(() {
      _vue = vue;
      _message = null;
    });
  }

  Future<void> _action(Future<void> Function() action) async {
    setState(() {
      _enCours = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _message = messageErreur(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<String?> _saisir(String code) async {
    try {
      final r = await _controleur.verifierCode(code);
      return switch (r) {
        CodeCompteBon() => null,
        CodeCompteFaux(:final essaisRestants) => essaisRestants <= 1
            ? 'Code incorrect. Encore 1 essai, puis les nouveaux appareils seront bloqués 1 heure.'
            : 'Code incorrect. Encore $essaisRestants essais.',
        CodeCompteBloque() => 'Trop de codes faux. Les nouveaux appareils sont bloqués pour le moment.',
      };
    } catch (e) {
      return messageErreur(e);
    }
  }

  Future<void> _codeOublie() async {
    final choix = await showModalBottomSheet<_Vue>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (feuille) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Code oublié ?', style: Theme.of(feuille).textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                key: const Key('choix_autoriser_autre_appareil'),
                leading: const Icon(Icons.phonelink_lock_outlined),
                title: const Text('Autoriser depuis un autre appareil'),
                subtitle: const Text('Votre téléphone habituel vous demande « Autoriser ce nouvel appareil ? »'),
                onTap: () => Navigator.of(feuille).pop(_Vue.attente),
              ),
              ListTile(
                key: const Key('choix_recuperation_email'),
                leading: const Icon(Icons.mark_email_read_outlined),
                title: const Text('Récupérer par e-mail (48 h)'),
                subtitle: const Text('Par sécurité, le nouveau code se choisit 48 heures après'),
                onTap: () => Navigator.of(feuille).pop(_Vue.recuperation),
              ),
              ListTile(
                key: const Key('choix_ecole'),
                leading: const Icon(Icons.school_outlined),
                title: const Text('Me présenter à l’école'),
                subtitle: const Text('La direction vous débloque, en votre présence'),
                onTap: () => Navigator.of(feuille).pop(_Vue.ecole),
              ),
            ],
          ),
        ),
      ),
    );
    if (choix == null || !mounted) return;
    switch (choix) {
      case _Vue.attente:
        await _action(() async {
          await _controleur.demanderApprobation();
          _aller(_Vue.attente);
        });
      case _Vue.recuperation:
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Récupérer par e-mail'),
            content: const Text(
              'Un e-mail vous prévient tout de suite. Vous pourrez choisir un nouveau code dans 48 heures, '
              'sur ce téléphone. Pendant ce temps, vos autres appareils peuvent annuler la récupération.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Lancer')),
            ],
          ),
        );
        if (ok == true) {
          await _action(() async {
            await _controleur.lancerRecuperation();
            _aller(_Vue.recuperation);
          });
        }
      default:
        _aller(choix);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(etatAppareilProvider).valueOrNull ?? EtatAppareil.libre;
    final theme = Theme.of(context);
    final vue = _vueDe(etat);
    final prenom = etat.prenom;

    final contenu = switch (vue) {
      _Vue.saisie => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nouvel appareil : saisissez le code de votre compte, celui qui ouvre EcoShop sur votre téléphone habituel.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (etat.bloque)
            _Encadre(icone: Icons.block, texte: texteBlocage(etat), cle: 'message_blocage')
          else
            PaveCode(key: const Key('pave_code_compte'), titre: 'Code de votre compte', surCode: _saisir),
          TextButton(key: const Key('bouton_code_oublie'), onPressed: _enCours ? null : _codeOublie,
              child: const Text('Code oublié ?')),
        ],
      ),
      _Vue.attente => _VueAttente(
        demande: etat.monApprobation,
        enCours: _enCours,
        renvoyer: () => _action(() async => _controleur.demanderApprobation()),
        autreSolution: () => _aller(_Vue.saisie),
      ),
      _Vue.recuperation => _VueRecuperation(
        demande: etat.maRecuperation,
        choisir: () => _aller(_Vue.nouveauCode),
        retour: () => _aller(_Vue.saisie),
      ),
      _Vue.ecole => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Encadre(
            icone: Icons.school_outlined,
            cle: 'texte_ecole',
            texte: 'Présentez-vous à la direction de votre école avec une pièce d’identité. Elle vous débloque '
                'en votre présence ; vous avez alors 30 minutes pour choisir un nouveau code ici.\n\n'
                'Membre de la direction ou fondateur : contactez l’équipe GSG, qui vérifie votre identité.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('bouton_debloque_choisir'),
            onPressed: () => _aller(_Vue.nouveauCode),
            child: const Text('J’ai été débloqué(e) : choisir un nouveau code'),
          ),
          TextButton(onPressed: () => _aller(_Vue.saisie), child: const Text('Retour')),
        ],
      ),
      _Vue.nouveauCode => ChoixNouveauCode(
        valider: (code) async {
          try {
            await _controleur.finaliserRecuperation(code);
            return null;
          } catch (e) {
            return messageErreur(e);
          }
        },
        retour: () => _aller(_Vue.saisie),
      ),
    };

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_outlined, size: 40, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      prenom == null || prenom.isEmpty ? 'Bonjour' : 'Bonjour $prenom',
                      key: const Key('bonjour_code_compte'),
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    contenu,
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(_message!, key: const Key('erreur_code_compte'),
                          style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: () => ref.deconnecterEtPurgerDonneesLocales(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Se déconnecter'),
                    ),
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

class _VueAttente extends StatelessWidget {
  const _VueAttente({required this.demande, required this.enCours, required this.renvoyer, required this.autreSolution});

  final DemandeAppareil? demande;
  final bool enCours;
  final VoidCallback renvoyer;
  final VoidCallback autreSolution;

  @override
  Widget build(BuildContext context) {
    final expiree = demande == null || !demande!.echeance.isAfter(DateTime.now());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!expiree) const Padding(padding: EdgeInsets.only(bottom: 16), child: CircularProgressIndicator()),
        _Encadre(
          icone: Icons.phonelink_lock_outlined,
          cle: 'texte_attente_autorisation',
          texte: expiree
              ? 'La demande a expiré. Renvoyez-la, puis touchez « Autoriser » sur votre téléphone habituel.'
              : 'Ouvrez EcoShop sur votre téléphone habituel et touchez « Autoriser ». '
                  'La demande expire à ${heure(demande!.echeance)}.',
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: enCours ? null : renvoyer, child: const Text('Renvoyer la demande')),
        TextButton(onPressed: autreSolution, child: const Text('Choisir une autre solution')),
      ],
    );
  }
}

class _VueRecuperation extends StatelessWidget {
  const _VueRecuperation({required this.demande, required this.choisir, required this.retour});

  final DemandeAppareil? demande;
  final VoidCallback choisir;
  final VoidCallback retour;

  @override
  Widget build(BuildContext context) {
    final d = demande;
    final mure = d != null && !d.echeance.isAfter(DateTime.now());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Encadre(
          icone: Icons.mark_email_read_outlined,
          cle: 'texte_recuperation',
          texte: d == null
              ? 'Aucune récupération en cours.'
              : mure
              ? 'Les 48 heures sont passées : choisissez votre nouveau code.'
              : 'Récupération en cours. Vous pourrez choisir un nouveau code à partir du ${dateHeure(d.echeance)}, '
                  'sur ce téléphone. Un e-mail vous a été envoyé.',
        ),
        const SizedBox(height: 12),
        if (mure) FilledButton(key: const Key('bouton_choisir_apres_48h'), onPressed: choisir,
            child: const Text('Choisir mon nouveau code')),
        TextButton(onPressed: retour, child: const Text('Retour')),
      ],
    );
  }
}

/// Choix d'un nouveau code (deux saisies). [valider] renvoie un message
/// d'erreur, ou null.
class ChoixNouveauCode extends StatefulWidget {
  const ChoixNouveauCode({super.key, required this.valider, this.retour, this.titre = 'Choisissez un nouveau code'});

  final Future<String?> Function(String code) valider;
  final VoidCallback? retour;
  final String titre;

  @override
  State<ChoixNouveauCode> createState() => _ChoixNouveauCodeState();
}

class _ChoixNouveauCodeState extends State<ChoixNouveauCode> {
  String? _premier;
  String? _erreur;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_premier == null)
          PaveCode(
            key: const ValueKey('nouveau_code_choix'),
            titre: widget.titre,
            sousTitre: _erreur ?? '6 chiffres, sans suite évidente. Le même code sur tous vos appareils.',
            surCode: (code) async {
              final refus = ReglesCode.verifierChoix(code);
              if (refus != null) return ReglesCode.message(refus);
              setState(() {
                _premier = code;
                _erreur = null;
              });
              return null;
            },
          )
        else
          PaveCode(
            key: const ValueKey('nouveau_code_confirmation'),
            titre: 'Confirmez le nouveau code',
            surCode: (code) async {
              if (code != _premier) {
                setState(() {
                  _premier = null;
                  _erreur = 'Les deux codes sont différents. Recommencez.';
                });
                return null;
              }
              final erreur = await widget.valider(code);
              if (erreur != null && mounted) {
                setState(() {
                  _premier = null;
                  _erreur = erreur;
                });
              }
              return null;
            },
          ),
        if (widget.retour != null) TextButton(onPressed: widget.retour, child: const Text('Retour')),
      ],
    );
  }
}

class _Encadre extends StatelessWidget {
  const _Encadre({required this.icone, required this.texte, required this.cle});

  final IconData icone;
  final String texte;
  final String cle;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: schema.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: schema.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(texte, key: Key(cle))),
        ],
      ),
    );
  }
}

/// Compte d'avant REG-22 (« votre code devient le code de votre compte »)
/// ou code changé sur un autre appareil : saisi une fois, en ligne.
class EcranCodeCompteAConfirmer extends ConsumerStatefulWidget {
  const EcranCodeCompteAConfirmer({super.key});

  @override
  ConsumerState<EcranCodeCompteAConfirmer> createState() => _EcranCodeCompteAConfirmerState();
}

class _EcranCodeCompteAConfirmerState extends ConsumerState<EcranCodeCompteAConfirmer> {
  bool _nouveauCode = false;
  String? _message;

  AppareilController get _controleur => ref.read(appareilControllerProvider);

  Future<void> _codeOublie() async {
    final etat = ref.read(etatAppareilProvider).valueOrNull;
    final recup = etat?.maRecuperation;
    if (recup != null && !recup.echeance.isAfter(DateTime.now())) {
      setState(() => _nouveauCode = true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Code oublié'),
        content: Text(recup != null
            ? 'Récupération en cours : vous pourrez choisir un nouveau code à partir du ${dateHeure(recup.echeance)}.'
            : 'Recevez un e-mail et choisissez un nouveau code dans 48 heures, sur ce téléphone. '
                'Ou présentez-vous à la direction de l’école, qui vous débloque en votre présence.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Fermer')),
          if (recup == null)
            FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Récupérer par e-mail')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _controleur.lancerRecuperation();
    } catch (e) {
      if (mounted) setState(() => _message = messageErreur(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(etatAppareilProvider).valueOrNull ?? EtatAppareil.libre;
    final theme = Theme.of(context);
    final premier = !etat.aUnCode;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.devices_outlined, size: 40, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      premier ? 'Votre code devient le code de votre compte' : 'Le code de votre compte a changé',
                      key: const Key('titre_code_compte_a_confirmer'),
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      premier
                          ? 'Le même code ouvrira EcoShop sur tous vos appareils, et il sera demandé sur tout '
                              'nouvel appareil. Saisissez votre code actuel pour le confirmer.'
                          : 'Il a été changé sur un autre appareil. Saisissez le nouveau code une fois : il remplace '
                              'celui de ce téléphone.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (_nouveauCode)
                      ChoixNouveauCode(
                        valider: (code) async {
                          try {
                            await _controleur.finaliserRecuperation(code);
                            return null;
                          } catch (e) {
                            return messageErreur(e);
                          }
                        },
                        retour: () => setState(() => _nouveauCode = false),
                      )
                    else ...[
                      PaveCode(
                        key: const Key('pave_code_a_confirmer'),
                        titre: premier ? 'Votre code actuel' : 'Nouveau code du compte',
                        surCode: (code) async {
                          try {
                            return await _controleur.confirmerCodeCompte(code);
                          } catch (e) {
                            return messageErreur(e);
                          }
                        },
                      ),
                      if (!premier) TextButton(onPressed: _codeOublie, child: const Text('Code oublié ?')),
                    ],
                    if (_message != null)
                      Text(_message!, style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => ref.deconnecterEtPurgerDonneesLocales(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Se déconnecter'),
                    ),
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
