import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/sync/journal_rejets.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../application/amorcage_controller.dart';
import '../application/sync_composition.dart';

/// Âge lisible d'une date : « à l'instant », « il y a 5 min », « il y a
/// 2 h », « le 28/10 ».
String ageLisible(DateTime date, {DateTime? maintenant}) {
  final ecart = (maintenant ?? DateTime.now()).difference(date);
  if (ecart.inMinutes < 1) return 'à l’instant';
  if (ecart.inMinutes < 60) return 'il y a ${ecart.inMinutes} min';
  if (ecart.inHours < 24) return 'il y a ${ecart.inHours} h';
  String deux(int v) => v.toString().padLeft(2, '0');
  return 'le ${deux(date.day)}/${deux(date.month)}';
}

/// Taille lisible : « 850 Ko », « 12,4 Mo ».
String tailleLisible(int octets) {
  if (octets < 1024 * 1024) return '${(octets / 1024).ceil()} Ko';
  return '${(octets / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
}

/// Envois en attente, lus de la file (lot 5).
final envoisEnAttenteProvider = FutureProvider.autoDispose<List<SyncEntree>>((ref) {
  ref.watch(suiviSyncProvider);
  return ref.watch(syncRepositoryProvider).entreesEnAttente();
});

/// Refus du serveur à montrer.
final refusSynchronisationProvider = FutureProvider.autoDispose<List<RejetSynchronisation>>((ref) {
  ref.watch(suiviSyncProvider);
  return ref.watch(journalRejetsProvider).lister();
});

final _statistiquesCopiesProvider = FutureProvider.autoDispose<({int copies, int octets})>((ref) {
  return CacheDocumentStore.statistiques(ref.watch(databaseProvider));
});

/// « État de la synchronisation » (REG-35, lot 5) : un seul endroit pour
/// voir ce qui est sur l'appareil, ce qui attend d'être envoyé et ce que le
/// serveur a refusé — avec les mêmes mots partout (« en attente », « envoi
/// en cours », « refusé »), comme le recommandent les guides des
/// applications hors ligne.
class EcranEtatSynchronisation extends ConsumerStatefulWidget {
  const EcranEtatSynchronisation({super.key});

  @override
  ConsumerState<EcranEtatSynchronisation> createState() => _EcranEtatSynchronisationState();
}

class _EcranEtatSynchronisationState extends ConsumerState<EcranEtatSynchronisation> {
  bool _enCours = false;

  Future<void> _synchroniser() async {
    setState(() => _enCours = true);
    try {
      await ref.read(syncEngineProvider).synchroniser(forcer: true);
      await ref.read(amorcageProvider.notifier).lancerSiNecessaire(force: true);
    } catch (_) {
      // Le bandeau et cet écran montrent ce qui reste à faire.
    } finally {
      ref.invalidate(envoisEnAttenteProvider);
      ref.invalidate(refusSynchronisationProvider);
      ref.invalidate(_statistiquesCopiesProvider);
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enLigne = ref.watch(estEnLigneProvider);
    final amorcage = ref.watch(amorcageProvider);
    final derniere = ref.watch(derniereAmorcageProvider).valueOrNull;
    final envois = ref.watch(envoisEnAttenteProvider);
    final refus = ref.watch(refusSynchronisationProvider);
    final stats = ref.watch(_statistiquesCopiesProvider).valueOrNull;
    final wifi = ref.watch(wifiSeulementProvider).valueOrNull ?? false;
    final schema = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // 1. État général
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(enLigne ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                      color: enLigne ? schema.primary : schema.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      enLigne ? 'Connecté au serveur' : 'Hors connexion — vos saisies sont gardées sur l’appareil',
                      key: const Key('etat_connexion'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  derniere == null
                      ? 'Données de votre espace pas encore préparées pour le hors connexion.'
                      : 'Données de votre espace préparées ${ageLisible(derniere)}.',
                  key: const Key('etat_derniere_preparation'),
                ),
                if (amorcage.enCours && amorcage.total > 0) ...[
                  const SizedBox(height: 8),
                  Text('Préparation en cours : ${amorcage.faites} / ${amorcage.total}'),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: amorcage.progression),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('bouton_synchroniser'),
                  onPressed: enLigne && !_enCours ? _synchroniser : null,
                  icon: const Icon(Icons.sync),
                  label: Text(_enCours ? 'Synchronisation…' : 'Synchroniser maintenant'),
                ),
                if (!enLigne)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Disponible au retour du réseau. Tout part ensuite automatiquement.'),
                  ),
              ]),
            ),
          ),

          // 2. Envois en attente
          const _Titre('En attente d’envoi'),
          envois.when(
            data: (liste) => liste.isEmpty
                ? const _Vide('Rien en attente : tout ce que vous avez saisi est arrivé au serveur.', cle: 'envois_vides')
                : Card(
                    child: Column(children: [
                      for (final e in liste)
                        ListTile(
                          key: ValueKey('envoi_${e.id}'),
                          leading: Icon(e.statut == SyncStatut.echec ? Icons.sync_problem_outlined : Icons.schedule_send_outlined),
                          title: Text(libelleOperation(e)),
                          subtitle: Text(e.statut == SyncStatut.enCours
                              ? 'Envoi en cours'
                              : e.tentatives > 0
                                  ? 'En attente — nouvel essai automatique (${e.tentatives} essai(s))'
                                  : 'En attente — part au retour du réseau'),
                        ),
                    ]),
                  ),
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const _Vide('File d’envoi illisible pour le moment.'),
          ),

          // 3. Refus
          const _Titre('Refusé par le serveur'),
          refus.when(
            data: (liste) => liste.isEmpty
                ? const _Vide('Aucun refus.', cle: 'refus_vides')
                : Card(
                    child: Column(children: [
                      for (final r in liste)
                        ListTile(
                          leading: Icon(Icons.report_outlined, color: schema.error),
                          title: Text(r.libelle),
                          subtitle: Text('${r.message}\nNon enregistré : corrigez puis ressaisissez si besoin.'),
                          isThreeLine: true,
                          trailing: TextButton(
                            onPressed: () async {
                              await ref.read(journalRejetsProvider).retirer(r.id);
                              ref.invalidate(refusSynchronisationProvider);
                            },
                            child: const Text('Compris'),
                          ),
                        ),
                    ]),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // 4. Sur l'appareil
          const _Titre('Sur cet appareil'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: const Text('Données gardées pour le hors connexion'),
                subtitle: Text(stats == null
                    ? '…'
                    : '${stats.copies} copie(s), ${tailleLisible(stats.octets)} — chiffrées pour chaque compte'),
              ),
              SwitchListTile(
                key: const Key('interrupteur_wifi_seulement'),
                secondary: const Icon(Icons.wifi),
                title: const Text('Préparer le hors connexion en Wi-Fi seulement'),
                subtitle: const Text('Économise les données mobiles. Les saisies, elles, partent toujours dès qu’il y a du réseau.'),
                value: wifi,
                onChanged: (v) => ref.read(wifiSeulementProvider.notifier).definir(v),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(texte, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _Vide extends StatelessWidget {
  const _Vide(this.texte, {this.cle});
  final String texte;
  final String? cle;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(texte, key: cle == null ? null : Key(cle!)),
        ),
      );
}
