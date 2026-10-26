import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/securite/gardien_actions_sensibles.dart';
import '../application/appareil_providers.dart';
import '../domain/etat_appareil.dart';
import 'ecran_code_compte.dart';
import 'surveillance_appareils.dart';

/// « Dernière utilisation : aujourd'hui à 14 h 05 ».
String quandLisible(DateTime d, {DateTime? maintenant}) {
  final m = maintenant ?? DateTime.now();
  final jour = DateTime(d.year, d.month, d.day);
  final aujourdhui = DateTime(m.year, m.month, m.day);
  final ecart = aujourdhui.difference(jour).inDays;
  if (ecart == 0) return 'aujourd’hui à ${heure(d)}';
  if (ecart == 1) return 'hier à ${heure(d)}';
  return 'le ${dateHeure(d)}';
}

String _d2(int n) => n.toString().padLeft(2, '0');

/// Mon profil › Sécurité › Mes appareils (REG-22, partie B).
class EcranMesAppareils extends ConsumerWidget {
  const EcranMesAppareils({super.key});

  Future<void> _deconnecter(BuildContext context, WidgetRef ref, {AppareilConnecte? appareil}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(appareil == null ? 'Déconnecter tous les autres appareils ?' : 'Déconnecter ${appareil.modele} ?'),
        content: const Text(
          'L’appareil est déconnecté dès sa prochaine requête, et ses données EcoShop sont effacées à son retour '
          'sur le réseau. Un e-mail vous le confirme.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Déconnecter')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messager = ScaffoldMessenger.of(context);
    final repo = ref.read(appareilRepositoryProvider);
    try {
      if (appareil == null) {
        final n = await avecCode('Déconnecter tous les autres appareils', repo.deconnecterAutres);
        messager.showSnackBar(SnackBar(content: Text(n == 0 ? 'Aucun autre appareil.' : '$n appareil(s) déconnecté(s).')));
      } else {
        await avecCode('Déconnecter ${appareil.modele}', () => repo.deconnecterAppareil(appareil.sessionId));
        messager.showSnackBar(SnackBar(content: Text('${appareil.modele} est déconnecté.')));
      }
    } on ActionSensibleAnnulee {
      return;
    } catch (e) {
      messager.showSnackBar(SnackBar(content: Text(messageErreur(e))));
    }
    ref.invalidate(mesAppareilsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appareils = ref.watch(mesAppareilsProvider);
    final etat = ref.watch(etatAppareilProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes appareils')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(mesAppareilsProvider);
          ref.invalidate(etatAppareilProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Demandes en cours, au-dessus de la liste.
            if (etat?.recuperationEnCours != null) BandeauRecuperation(demande: etat!.recuperationEnCours!),
            for (final d in etat?.autorisationsATraiter ?? const <DemandeAppareil>[])
              Card(
                child: ListTile(
                  leading: const Icon(Icons.phonelink_lock_outlined),
                  title: Text('${d.modele ?? 'Un appareil'} demande à entrer'),
                  subtitle: Text('Jusqu’à ${heure(d.echeance)}'),
                  trailing: FilledButton.tonal(
                    onPressed: () async {
                      final choix = await showDialog<bool>(context: context, builder: (_) => InviteAutorisation(demande: d));
                      if (choix == null) return;
                      final c = ref.read(appareilControllerProvider);
                      try {
                        if (choix) {
                          await avecCode('Autoriser un nouvel appareil', () => c.approuver(d.id));
                        } else {
                          await c.refuser(d.id);
                        }
                      } on ActionSensibleAnnulee {
                        return;
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageErreur(e))));
                        }
                      }
                      ref.invalidate(mesAppareilsProvider);
                    },
                    child: const Text('Répondre'),
                  ),
                ),
              ),
            ...appareils.when(
              loading: () => const [Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
              error: (e, _) => [Text(messageErreur(e), key: const Key('erreur_mes_appareils'))],
              data: (liste) => [
                for (final a in liste) _CarteAppareil(appareil: a, deconnecter: () => _deconnecter(context, ref, appareil: a)),
                if (liste.where((a) => !a.cetAppareil).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const Key('bouton_deconnecter_autres'),
                    onPressed: () => _deconnecter(context, ref),
                    icon: const Icon(Icons.logout),
                    label: const Text('Déconnecter tous les autres appareils'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CarteAppareil extends StatelessWidget {
  const _CarteAppareil({required this.appareil, required this.deconnecter});

  final AppareilConnecte appareil;
  final VoidCallback deconnecter;

  @override
  Widget build(BuildContext context) {
    final a = appareil;
    final schema = Theme.of(context).colorScheme;
    final icone = (a.systeme ?? '').startsWith('Android') || (a.systeme ?? '').startsWith('iOS')
        ? Icons.smartphone
        : Icons.devices_other;
    return Card(
      key: Key('appareil_${a.sessionId}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 32, color: schema.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.modele, style: Theme.of(context).textTheme.titleMedium),
                  if (a.cetAppareil)
                    Text('Cet appareil', style: TextStyle(color: schema.primary, fontWeight: FontWeight.w600)),
                  if (a.aVerifier) Text('Pas encore vérifié', style: TextStyle(color: schema.error)),
                  Text('Dernière utilisation : ${quandLisible(a.derniereUtilisation)}'),
                  Text('Connecté depuis le ${_d2(a.connecteLe.day)}/${_d2(a.connecteLe.month)}'),
                ],
              ),
            ),
            if (!a.cetAppareil)
              TextButton(
                key: Key('deconnecter_${a.sessionId}'),
                onPressed: deconnecter,
                child: const Text('Déconnecter'),
              ),
          ],
        ),
      ),
    );
  }
}
