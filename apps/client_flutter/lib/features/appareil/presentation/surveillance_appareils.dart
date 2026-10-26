import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/securite/gardien_actions_sensibles.dart';
import '../application/appareil_providers.dart';
import '../domain/etat_appareil.dart';
import 'ecran_code_compte.dart';

/// Sur un appareil connu (REG-22) : relit l'état régulièrement et au retour
/// au premier plan ; montre « Autoriser ce nouvel appareil ? » et le bandeau
/// « Récupération du code en cours ».
class SurveillanceAppareils extends ConsumerStatefulWidget {
  const SurveillanceAppareils({super.key, this.intervalle = const Duration(seconds: 45)});

  final Duration intervalle;

  @override
  ConsumerState<SurveillanceAppareils> createState() => _SurveillanceAppareilsState();
}

class _SurveillanceAppareilsState extends ConsumerState<SurveillanceAppareils> with WidgetsBindingObserver {
  Timer? _minuterie;
  final _dejaPresentees = <String>{};
  bool _inviteOuverte = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _minuterie = Timer.periodic(widget.intervalle, (_) => ref.invalidate(etatAppareilProvider));
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(etatAppareilProvider);
  }

  Future<void> _presenter(DemandeAppareil d) async {
    if (_inviteOuverte) return;
    _inviteOuverte = true;
    _dejaPresentees.add(d.id);
    final controleur = ref.read(appareilControllerProvider);
    final messager = ScaffoldMessenger.maybeOf(context);
    final choix = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogue) => InviteAutorisation(demande: d),
    );
    _inviteOuverte = false;
    if (choix == null) return;
    try {
      if (choix) {
        await avecCode('Autoriser un nouvel appareil', () => controleur.approuver(d.id));
        messager?.showSnackBar(const SnackBar(content: Text('Nouvel appareil autorisé.')));
      } else {
        await controleur.refuser(d.id);
        messager?.showSnackBar(const SnackBar(
          content: Text('Connexion fermée. Changez maintenant le code de votre compte (Mon profil › Sécurité).'),
        ));
      }
    } on ActionSensibleAnnulee {
      _dejaPresentees.remove(d.id);
    } catch (e) {
      messager?.showSnackBar(SnackBar(content: Text(messageErreur(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(etatAppareilProvider).valueOrNull;
    if (etat == null || etat.statut != StatutAppareil.approuve) return const SizedBox.shrink();

    final nouvelles = [
      for (final d in etat.autorisationsATraiter)
        if (!_dejaPresentees.contains(d.id) && d.echeance.isAfter(DateTime.now())) d,
    ];
    if (nouvelles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _presenter(nouvelles.first);
      });
    }

    final recup = etat.recuperationEnCours;
    if (recup == null) return const SizedBox.shrink();
    return BandeauRecuperation(demande: recup);
  }
}

/// « Autoriser ce nouvel appareil ? » — vrai : autoriser ; faux : « Ce
/// n'est pas moi ».
class InviteAutorisation extends StatelessWidget {
  const InviteAutorisation({super.key, required this.demande});

  final DemandeAppareil demande;

  @override
  Widget build(BuildContext context) {
    final quand = demande.demandeLe;
    return AlertDialog(
      key: const Key('invite_autorisation_appareil'),
      icon: const Icon(Icons.phonelink_lock_outlined),
      title: const Text('Autoriser ce nouvel appareil ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(demande.modele ?? 'Appareil inconnu', style: Theme.of(context).textTheme.titleMedium),
          if (quand != null) Text('Demandé à ${heure(quand)}'),
          const SizedBox(height: 12),
          const Text('Autorisez seulement si c’est vous, maintenant, sur cet appareil.'),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('bouton_pas_moi_appareil'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Ce n’est pas moi'),
        ),
        FilledButton(
          key: const Key('bouton_autoriser_appareil'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Autoriser'),
        ),
      ],
    );
  }
}

/// Bandeau sur les appareils connus pendant une récupération du code.
class BandeauRecuperation extends ConsumerWidget {
  const BandeauRecuperation({super.key, required this.demande});

  final DemandeAppareil demande;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schema = Theme.of(context).colorScheme;
    return Material(
      color: schema.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: schema.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Une récupération du code est en cours (fin le ${dateHeure(demande.echeance)}).',
                key: const Key('bandeau_recuperation'),
                style: TextStyle(color: schema.onErrorContainer),
              ),
            ),
            TextButton(
              key: const Key('bouton_annuler_recuperation'),
              onPressed: () async {
                final messager = ScaffoldMessenger.maybeOf(context);
                try {
                  await avecCode('Annuler la récupération du code',
                      () => ref.read(appareilControllerProvider).annulerRecuperation(demande.id));
                  messager?.showSnackBar(const SnackBar(content: Text('Récupération annulée.')));
                } on ActionSensibleAnnulee {
                  // Rien.
                } catch (e) {
                  messager?.showSnackBar(SnackBar(content: Text(messageErreur(e))));
                }
              },
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
  }
}
