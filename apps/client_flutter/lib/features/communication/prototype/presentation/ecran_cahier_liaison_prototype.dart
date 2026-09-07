import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../scolarite/application/scolarite_providers.dart';
import '../../../scolarite/domain/fiche_eleve.dart';
import '../application/communication_locale_providers.dart';
import '../domain/entree_communication_locale.dart';
import 'widgets/banniere_prototype.dart';
import 'widgets/composeur_local.dart';

/// Cahier de texte / liaison — **prototype local** (M9). Aucune table
/// `cahier_liaison` n'existe côté serveur (voir le rapport de clôture M9) :
/// cet écran simule les mots de liaison parent-enseignant, stockés
/// uniquement sur cet appareil.
///
/// Réactif au sélecteur d'enfant (`enfantActifProvider`) côté parent quand
/// [fiche] n'est pas fourni explicitement ; un enseignant qui ouvre le
/// cahier depuis la fiche d'un élève précis passe [fiche] directement.
class EcranCahierLiaison extends ConsumerWidget {
  const EcranCahierLiaison({super.key, required this.profileId, required this.profileNom, this.fiche});

  final String profileId;
  final String profileNom;
  final FicheEleve? fiche;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ficheActive = fiche ?? ref.watch(enfantActifProvider);

    if (ficheActive == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cahier de liaison')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Sélectionnez un enfant pour consulter son cahier de liaison.'),
          ),
        ),
      );
    }

    return _EcranPourFiche(fiche: ficheActive, profileId: profileId, profileNom: profileNom);
  }
}

class _EcranPourFiche extends ConsumerWidget {
  const _EcranPourFiche({required this.fiche, required this.profileId, required this.profileNom});

  final FicheEleve fiche;
  final String profileId;
  final String profileNom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entrees = ref.watch(entreesLocalesProvider(TypeEntreeLocale.motLiaison));

    return Scaffold(
      appBar: AppBar(title: Text('Cahier de liaison — ${fiche.nomComplet}')),
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
                final mots = liste.where((e) => e.destinataireLabel == fiche.id).toList()
                  ..sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
                if (mots.isEmpty) {
                  return const Center(child: Text('Aucun mot de liaison pour le moment.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: mots.length,
                  itemBuilder: (context, i) => _CarteMot(mot: mots[i]),
                );
              },
            ),
          ),
          ComposeurLocal(
            hintText: 'Écrire un mot de liaison…',
            onEnvoyer: (contenu, {required signalee}) async {
              await ref.read(communicationLocaleRepositoryProvider).ajouter(
                    construireEntreeLocale(
                      type: TypeEntreeLocale.motLiaison,
                      auteurId: profileId,
                      auteurNom: profileNom,
                      destinataireLabel: fiche.id,
                      contenu: contenu,
                      signalee: signalee,
                    ),
                  );
              ref.invalidate(entreesLocalesProvider(TypeEntreeLocale.motLiaison));
            },
          ),
        ],
      ),
    );
  }
}

class _CarteMot extends StatelessWidget {
  const _CarteMot({required this.mot});

  final EntreeCommunicationLocale mot;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(mot.auteurNom, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(_formatDate(mot.dateCreation), style: const TextStyle(fontSize: 11, color: AppColors.encreSecondaire)),
              ],
            ),
            const SizedBox(height: 6),
            Text(mot.contenu),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
