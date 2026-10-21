import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../paiement_mobile/application/paiement_mobile_providers.dart';
import '../../paiement_mobile/presentation/widgets/identite_orange_money.dart' show formaterMontantMobile;
import '../application/pointage_providers.dart';
import '../domain/pointage.dart';

/// Crédits SMS de l'établissement (REG-09) : solde, achats à GSG,
/// historique. Les SMS servent aux alertes d'absence ou de sortie et aux
/// relances d'impayés ; les avis en push restent gratuits.
class EcranCreditsSms extends ConsumerWidget {
  const EcranCreditsSms({super.key, required this.etablissementId, this.devise = 'GNF'});

  final String etablissementId;
  final String devise;

  Future<void> _acheter(BuildContext context, WidgetRef ref, PackSms pack) async {
    try {
      final url = await ref.read(pointageRepositoryProvider).acheterPack(etablissementId, pack.code);
      await ref.read(lanceurUrlProvider).ouvrir(url);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Une fois le paiement confirmé, les crédits apparaissent ici (tirez pour actualiser).'),
      ));
    } on ErreurPointage catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final credits = ref.watch(creditsSmsProvider(etablissementId));
    return Scaffold(
      appBar: AppBar(title: const Text('Crédits SMS')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(creditsSmsProvider(etablissementId)),
        child: credits.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(e is ErreurPointage ? e.messageUtilisateur : 'Indisponible pour le moment.'),
            ),
          ]),
          data: (c) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text('${c.solde}', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: palette.primaire)),
                      const Text('SMS disponibles'),
                      const SizedBox(height: 8),
                      Text(
                        'Un SMS de 160 caractères = 1 crédit. Un SMS non distribué est recrédité.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.encreSecondaire, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Acheter des crédits', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (c.packs.isEmpty)
                Text(
                  "Aucun pack en vente pour le moment. Contactez GSG : il peut créditer votre école après un virement ou un paiement mobile.",
                  style: TextStyle(color: palette.encreSecondaire),
                ),
              for (final p in c.packs)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.sms_outlined),
                    title: Text(p.libelle),
                    subtitle: Text(
                      '${formaterMontantMobile(p.prix, p.devise)} · '
                      '${formaterMontantMobile((p.prix / p.quantite).roundToDouble(), p.devise)} le SMS',
                    ),
                    trailing: FilledButton(onPressed: () => _acheter(context, ref, p), child: const Text('Acheter')),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Historique', style: Theme.of(context).textTheme.titleMedium),
              if (c.mouvements.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Aucun mouvement.', style: TextStyle(color: palette.encreSecondaire)),
                ),
              for (final m in c.mouvements)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(m.quantite >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                      color: m.quantite >= 0 ? palette.succes : palette.encreSecondaire),
                  title: Text(m.libelle),
                  subtitle: Text(
                    '${m.le.day.toString().padLeft(2, '0')}/${m.le.month.toString().padLeft(2, '0')} '
                    '${m.le.hour.toString().padLeft(2, '0')}:${m.le.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: Text('${m.quantite > 0 ? '+' : ''}${m.quantite}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
