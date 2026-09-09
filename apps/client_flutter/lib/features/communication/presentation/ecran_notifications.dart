import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/comm_providers.dart';
import '../domain/enums_comm.dart';
import '../domain/notif.dart';

/// Fil de notifications du compte connecté (M9) — SMS/WhatsApp/Email/Push
/// unifiés dans une seule liste côté client, marquage « lue » hors
/// connexion possible (file `sync_queue`, même politique que M7/M8).
class EcranNotifications extends ConsumerWidget {
  const EcranNotifications({super.key, required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(mesNotificationsProvider(profileId));

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(mesNotificationsProvider(profileId)),
        child: notifications.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: List.generate(5, (_) => const ShimmerCarteListe()),
          ),
          error: (erreur, _) => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Notifications indisponibles hors connexion pour le moment.'),
            ),
          ),
          data: (liste) => liste.isEmpty
              ? const Center(child: Text('Aucune notification.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: liste.length,
                  itemBuilder: (context, i) => EntreeAnimee(
                    index: i,
                    enfant: _CarteNotification(notification: liste[i], profileId: profileId),
                  ),
                ),
        ),
      ),
    );
  }
}

class _CarteNotification extends ConsumerWidget {
  const _CarteNotification({required this.notification, required this.profileId});

  final Notif notification;
  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lue = notification.estLue;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: lue ? null : context.palette.primaire.withValues(alpha: 0.05),
      child: ListTile(
        leading: Icon(_icone(notification.canal), color: lue ? context.palette.encreSecondaire : context.palette.primaire),
        title: Text(
          notification.type,
          style: TextStyle(fontWeight: lue ? FontWeight.w400 : FontWeight.w700),
        ),
        subtitle: Text(
          notification.contenu.isEmpty ? notification.canal.libelle : notification.contenu,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: lue
            ? Icon(Icons.mark_email_read_outlined, color: context.palette.succes)
            : IconButton(
                icon: Icon(Icons.mark_email_unread_outlined, color: context.palette.primaire),
                tooltip: 'Marquer comme lue',
                onPressed: () async {
                  await ref.read(commRepositoryProvider).marquerLue(notification.id, destinataire: profileId);
                  ref.invalidate(mesNotificationsProvider(profileId));
                },
              ),
      ),
    );
  }

  static IconData _icone(CanalNotification canal) => switch (canal) {
        CanalNotification.sms => Icons.sms_outlined,
        CanalNotification.whatsapp => Icons.chat_outlined,
        CanalNotification.email => Icons.email_outlined,
        CanalNotification.push => Icons.notifications_outlined,
      };
}
