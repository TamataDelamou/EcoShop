import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../communication/application/comm_providers.dart';
import '../../communication/presentation/ecran_notifications.dart';
import '../application/push_providers.dart';
import '../domain/messagerie_push.dart';

/// Branche les notifications push sur l'application, une fois le compte
/// ouvert (invisible à l'écran).
///
/// - Demande l'autorisation d'afficher des notifications, puis rattache le
///   téléphone au compte (retenté au retour du réseau).
/// - Application ouverte : la notification s'affiche en bandeau en bas de
///   l'écran, avec « Voir », et la boîte de notifications est rafraîchie.
/// - Notification touchée dans la barre du téléphone : ouvre la boîte de
///   notifications.
class EcouteurPush extends ConsumerStatefulWidget {
  const EcouteurPush({super.key, required this.profilId});

  final String profilId;

  @override
  ConsumerState<EcouteurPush> createState() => _EcouteurPushState();
}

class _EcouteurPushState extends ConsumerState<EcouteurPush> {
  final _abonnements = <StreamSubscription<Object>>[];
  final _dejaOuvertes = <String>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(_demarrer);
  }

  Future<void> _demarrer() async {
    final messagerie = ref.read(messageriePushProvider);
    final service = ref.read(servicePushProvider);
    if (messagerie == null || service == null || !mounted) return;

    _abonnements
      ..add(messagerie.messagesPremierPlan.listen(_afficherBandeau))
      ..add(messagerie.messagesOuverts.listen(_ouvrir))
      // Écouté avant `enregistrer()` : c'est par là qu'arrive l'identifiant.
      ..add(messagerie.identifiantEnregistre.listen((id) => service.rattacher(widget.profilId, id)));

    final initial = await messagerie.messageInitial().catchError((Object _) => null);
    if (initial != null) _ouvrir(initial);

    try {
      await messagerie.demanderAutorisation();
    } catch (_) {
      // Refus ou boîte de dialogue indisponible : la boîte de notifications
      // de l'application reste la référence.
    }
    await _inscrire();
  }

  /// Sans réseau, l'inscription échoue : retentée au retour du réseau.
  Future<void> _inscrire() async {
    try {
      await ref.read(messageriePushProvider)?.enregistrer();
    } catch (_) {
      // Retenté au retour du réseau.
    }
  }

  void _afficherBandeau(MessagePush message) {
    if (!mounted) return;
    ref.invalidate(mesNotificationsProvider(widget.profilId));
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.titre != null)
              Text(
                message.titre!,
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onInverseSurface),
              ),
            if (message.corps != null) Text(message.corps!),
          ],
        ),
        action: SnackBarAction(label: 'Voir', onPressed: _ouvrirBoite),
      ),
    );
  }

  void _ouvrir(MessagePush message) {
    final id = message.notificationId;
    if (id != null && !_dejaOuvertes.add(id)) return;
    ref.invalidate(mesNotificationsProvider(widget.profilId));
    _ouvrirBoite();
  }

  void _ouvrirBoite() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EcranNotifications(profileId: widget.profilId)),
    );
  }

  @override
  void dispose() {
    for (final a in _abonnements) {
      a.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Retour du réseau : le rattachement manqué est retenté.
    ref.listen<bool>(estEnLigneProvider, (avant, maintenant) {
      if (maintenant && avant == false) _inscrire();
    });
    return const SizedBox.shrink();
  }
}
