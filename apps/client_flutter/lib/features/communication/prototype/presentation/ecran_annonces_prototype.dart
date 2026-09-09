import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../../core/widgets/entree_animee.dart';
import '../../../../core/widgets/shimmer.dart';
import '../application/communication_locale_providers.dart';
import '../domain/entree_communication_locale.dart';
import 'widgets/banniere_prototype.dart';
import 'widgets/composeur_local.dart';

/// Annonces & fil d'actualités — **prototype local** (M9). Aucune table
/// `annonces` n'existe côté serveur (voir le rapport de clôture M9) : cet
/// écran simule la publication ciblée et l'accusé de réception, stockés
/// uniquement sur cet appareil.
class EcranAnnonces extends ConsumerStatefulWidget {
  const EcranAnnonces({super.key, required this.profileId, required this.profileNom, required this.peutPublier});

  final String profileId;
  final String profileNom;

  /// Ergonomique uniquement — sans backend réel, aucune RLS ne protège cette
  /// distinction : à ne jamais présenter comme une garantie de sécurité.
  final bool peutPublier;

  @override
  ConsumerState<EcranAnnonces> createState() => _EcranAnnoncesState();
}

class _EcranAnnoncesState extends ConsumerState<EcranAnnonces> {
  final _cibleCtrl = TextEditingController(text: 'Tout établissement');
  bool _important = false;

  @override
  void dispose() {
    _cibleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final annonces = ref.watch(entreesLocalesProvider(TypeEntreeLocale.annonce));

    return Scaffold(
      appBar: AppBar(title: const Text('Annonces')),
      body: Column(
        children: [
          const BanniereProtoype(),
          Expanded(
            child: annonces.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(3, (_) => const ShimmerCarteListe()),
              ),
              error: (erreur, _) => const Center(child: Text('Prototype local indisponible.')),
              data: (liste) => liste.isEmpty
                  ? const Center(child: Text('Aucune annonce publiée.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: liste.length,
                      itemBuilder: (context, i) => EntreeAnimee(
                        index: i,
                        enfant: _CarteAnnonce(annonce: liste[i], profileId: widget.profileId),
                      ),
                    ),
            ),
          ),
          if (widget.peutPublier)
            ComposeurLocal(
              hintText: 'Rédiger une annonce…',
              champsSupplementaires: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cibleCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Ciblage (établissement, classe, niveau, rôle)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Importante', style: TextStyle(fontSize: 11)),
                        Switch(value: _important, onChanged: (v) => setState(() => _important = v)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              onEnvoyer: (contenu, {required signalee}) async {
                await ref.read(communicationLocaleRepositoryProvider).ajouter(
                      construireEntreeLocale(
                        type: TypeEntreeLocale.annonce,
                        auteurId: widget.profileId,
                        auteurNom: widget.profileNom,
                        destinataireLabel:
                            _cibleCtrl.text.trim().isEmpty ? 'Tout établissement' : _cibleCtrl.text.trim(),
                        contenu: contenu,
                        important: _important,
                        signalee: signalee,
                      ),
                    );
                ref.invalidate(entreesLocalesProvider(TypeEntreeLocale.annonce));
                setState(() => _important = false);
              },
            ),
        ],
      ),
    );
  }
}

class _CarteAnnonce extends ConsumerWidget {
  const _CarteAnnonce({required this.annonce, required this.profileId});

  final EntreeCommunicationLocale annonce;
  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(annonce.destinataireLabel, style: TextStyle(color: context.palette.encreSecondaire, fontSize: 12)),
                ),
                if (annonce.important)
                  Icon(Icons.priority_high, size: 16, color: context.palette.erreur),
              ],
            ),
            const SizedBox(height: 4),
            Text(annonce.contenu),
            const SizedBox(height: 6),
            Text('Par ${annonce.auteurNom}', style: TextStyle(fontSize: 11, color: context.palette.encreSecondaire)),
            if (annonce.important) ...[
              const SizedBox(height: 8),
              annonce.accuseReception
                  ? Row(
                      children: [
                        Icon(Icons.check_circle_outline, size: 16, color: context.palette.succes),
                        const SizedBox(width: 4),
                        Text('Lecture confirmée', style: TextStyle(color: context.palette.succes, fontSize: 12)),
                      ],
                    )
                  : OutlinedButton.icon(
                      icon: const Icon(Icons.done_outlined, size: 16),
                      label: const Text('Accuser réception'),
                      onPressed: () async {
                        await ref
                            .read(communicationLocaleRepositoryProvider)
                            .marquerAccuseReception(TypeEntreeLocale.annonce, annonce.id);
                        ref.invalidate(entreesLocalesProvider(TypeEntreeLocale.annonce));
                      },
                    ),
            ],
          ],
        ),
      ),
    );
  }
}
