import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../paiement_mobile/presentation/widgets/identite_orange_money.dart' show formaterMontantMobile;
import '../application/pointage_providers.dart';
import '../domain/pointage.dart';

/// Relance des familles en retard de paiement (REG-09) : retard calculé sur
/// les tranches échues ; le payeur reçoit un push (gratuit), et un SMS si
/// la Direction le choisit et que l'école a des crédits. Une même famille
/// n'est pas relancée deux fois dans la semaine.
class EcranRelancesImpayes extends ConsumerStatefulWidget {
  const EcranRelancesImpayes({super.key, required this.etablissementId, this.devise = 'GNF'});

  final String etablissementId;
  final String devise;

  @override
  ConsumerState<EcranRelancesImpayes> createState() => _EcranRelancesImpayesState();
}

class _EcranRelancesImpayesState extends ConsumerState<EcranRelancesImpayes> {
  bool _sms = false;
  bool _enCours = false;
  final Set<String> _exclus = {};

  Future<void> _relancer(ApercuRelances apercu) async {
    final cibles = [
      for (final f in apercu.familles)
        if (!_exclus.contains(f.inscriptionId) && !f.relanceeRecemment) f.inscriptionId,
    ];
    if (cibles.isEmpty) return;
    setState(() => _enCours = true);
    try {
      final bilan = await ref.read(pointageRepositoryProvider).relancer(widget.etablissementId, sms: _sms, inscriptions: cibles);
      ref.invalidate(apercuRelancesProvider(widget.etablissementId));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Relances envoyées'),
          content: Text([
            '${bilan.familles} famille(s) relancée(s) : ${bilan.push} avis dans l\'application.',
            if (_sms) '${bilan.sms} SMS envoyé(s).',
            if (bilan.smsNonEnvoyes > 0) '${bilan.smsNonEnvoyes} SMS non envoyé(s) : crédit épuisé ou numéro inconnu.',
            if (bilan.dejaRelancees > 0) '${bilan.dejaRelancees} famille(s) déjà relancée(s) cette semaine.',
          ].join('\n')),
          actions: [FilledButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK'))],
        ),
      );
    } on ErreurPointage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final apercu = ref.watch(apercuRelancesProvider(widget.etablissementId));
    final a = apercu.valueOrNull;
    final cibles = a == null
        ? 0
        : a.familles.where((f) => !_exclus.contains(f.inscriptionId) && !f.relanceeRecemment).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Relancer les impayés')),
      body: apercu.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e is ErreurPointage ? e.messageUtilisateur : 'Indisponible pour le moment.')),
        data: (a) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              a.familles.isEmpty
                  ? 'Aucune famille en retard sur les tranches échues.'
                  : '${a.familles.length} élève(s) en retard — ${formaterMontantMobile(a.totalEnRetard, widget.devise)} au total.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Le retard compte seulement les tranches dont la date limite est passée. Les élèves boursiers ne sont pas relancés.',
              style: TextStyle(color: palette.encreSecondaire, fontSize: 12),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _sms,
              onChanged: (v) => setState(() => _sms = v),
              title: const Text('Envoyer aussi un SMS'),
              subtitle: Text('${a.creditsSms} crédit(s) SMS disponible(s) — un crédit par payeur prévenu.'),
            ),
            const Divider(),
            for (final f in a.familles)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: !_exclus.contains(f.inscriptionId) && !f.relanceeRecemment,
                onChanged: f.relanceeRecemment
                    ? null
                    : (v) => setState(() => v == true ? _exclus.remove(f.inscriptionId) : _exclus.add(f.inscriptionId)),
                title: Text(f.nomComplet),
                subtitle: Text([
                  if (f.classe != null) f.classe!,
                  'retard ${formaterMontantMobile(f.enRetard, widget.devise)}',
                  if (f.relanceeRecemment) 'déjà relancée cette semaine',
                ].join(' · ')),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _enCours || a == null || cibles == 0 ? null : () => _relancer(a),
            icon: const Icon(Icons.campaign_outlined),
            label: Text(_enCours ? 'Envoi…' : 'Relancer $cibles famille(s)'),
          ),
        ),
      ),
    );
  }
}
