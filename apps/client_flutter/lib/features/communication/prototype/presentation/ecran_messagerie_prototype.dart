import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/shimmer.dart';
import '../application/communication_locale_providers.dart';
import '../domain/entree_communication_locale.dart';
import 'widgets/banniere_prototype.dart';
import 'widgets/composeur_local.dart';

/// Messagerie — **prototype local** (M9). Aucune table `conversations`/
/// `messages` n'existe côté serveur (voir le rapport de clôture M9) : cet
/// écran simule des fils de discussion groupés par étiquette libre, stockés
/// uniquement sur cet appareil (`CommunicationLocaleRepository`).
class EcranMessagerie extends ConsumerWidget {
  const EcranMessagerie({super.key, required this.profileId, required this.profileNom});

  final String profileId;
  final String profileNom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entrees = ref.watch(entreesLocalesProvider(TypeEntreeLocale.message));

    return Scaffold(
      appBar: AppBar(title: const Text('Messagerie')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Nouvelle conversation'),
        onPressed: () => _nouvelleConversation(context),
      ),
      body: Column(
        children: [
          const BanniereProtoype(),
          Expanded(
            child: entrees.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(3, (_) => const ShimmerCarteListe()),
              ),
              error: (erreur, _) => const Center(child: Text('Prototype local indisponible.')),
              data: (liste) {
                final fils = _regrouperParFil(liste);
                if (fils.isEmpty) {
                  return const Center(child: Text('Aucune conversation. Créez-en une.'));
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final entree in fils.entries)
                      _CarteConversation(
                        label: entree.key,
                        dernierMessage: entree.value,
                        onTap: () => _ouvrirFil(context, entree.key),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Map<String, EntreeCommunicationLocale> _regrouperParFil(List<EntreeCommunicationLocale> liste) {
    final parLabel = <String, EntreeCommunicationLocale>{};
    for (final entree in liste) {
      final existante = parLabel[entree.destinataireLabel];
      if (existante == null || entree.dateCreation.isAfter(existante.dateCreation)) {
        parLabel[entree.destinataireLabel] = entree;
      }
    }
    return parLabel;
  }

  Future<void> _nouvelleConversation(BuildContext context) async {
    final controleur = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouvelle conversation'),
        content: TextField(
          controller: controleur,
          decoration: const InputDecoration(hintText: 'Nom du contact ou du groupe (ex. classe CM2-A)'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controleur.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty || !context.mounted) return;
    _ouvrirFil(context, label);
  }

  void _ouvrirFil(BuildContext context, String label) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EcranFilMessagerie(label: label, profileId: profileId, profileNom: profileNom),
      ),
    );
  }
}

class _CarteConversation extends StatelessWidget {
  const _CarteConversation({required this.label, required this.dernierMessage, required this.onTap});

  final String label;
  final EntreeCommunicationLocale dernierMessage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.group_outlined)),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(dernierMessage.contenu, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
    );
  }
}

class _EcranFilMessagerie extends ConsumerWidget {
  const _EcranFilMessagerie({required this.label, required this.profileId, required this.profileNom});

  final String label;
  final String profileId;
  final String profileNom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entrees = ref.watch(entreesLocalesProvider(TypeEntreeLocale.message));

    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: Column(
        children: [
          const BanniereProtoype(),
          Expanded(
            child: entrees.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (erreur, _) => const Center(child: Text('Prototype local indisponible.')),
              data: (liste) {
                final messages = liste.where((e) => e.destinataireLabel == label).toList()
                  ..sort((a, b) => a.dateCreation.compareTo(b.dateCreation));
                if (messages.isEmpty) {
                  return const Center(child: Text('Aucun message. Écrivez le premier.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _Bulle(message: messages[i], estMoi: messages[i].auteurId == profileId),
                );
              },
            ),
          ),
          ComposeurLocal(
            hintText: 'Écrire à $label…',
            onEnvoyer: (contenu, {required signalee}) async {
              await ref.read(communicationLocaleRepositoryProvider).ajouter(
                    construireEntreeLocale(
                      type: TypeEntreeLocale.message,
                      auteurId: profileId,
                      auteurNom: profileNom,
                      destinataireLabel: label,
                      contenu: contenu,
                      signalee: signalee,
                    ),
                  );
              ref.invalidate(entreesLocalesProvider(TypeEntreeLocale.message));
            },
          ),
        ],
      ),
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.message, required this.estMoi});

  final EntreeCommunicationLocale message;
  final bool estMoi;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: estMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 280),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          couleurBordure: estMoi ? context.palette.primaire.withValues(alpha: 0.3) : null,
          enfant: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!estMoi)
                Text(message.auteurNom, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              Text(message.contenu),
              if (message.signalee)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(Icons.flag_outlined, size: 14, color: context.palette.accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
