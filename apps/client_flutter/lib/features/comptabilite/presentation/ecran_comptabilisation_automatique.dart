import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/comptabilite_providers.dart';
import '../application/pieces_comptables_providers.dart';
import '../domain/comptabilisation_automatique.dart';
import '../domain/plan_comptable.dart';

/// Écritures automatiques (REG-03 C3, C5) : chaque paiement de frais
/// scolaires (espèces, Orange Money, banque) et chaque bulletin de paie
/// validé ou payé passent tout seuls en comptabilité. Cet écran
/// montre ce qui reste à rattraper, les incidents expliqués, et les comptes
/// utilisés — modifiables par l'école.
class EcranComptabilisationAutomatique extends ConsumerStatefulWidget {
  const EcranComptabilisationAutomatique({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranComptabilisationAutomatique> createState() => _EcranComptabilisationAutomatiqueState();
}

class _EcranComptabilisationAutomatiqueState extends ConsumerState<EcranComptabilisationAutomatique> {
  bool _enCours = false;

  Future<void> _rattraper() async {
    setState(() => _enCours = true);
    try {
      final r = await ref.read(comptabilisationAutomatiqueRepositoryProvider).rattraper(widget.etablissementId);
      if (!mounted) return;
      ref.invalidate(etatComptabilisationAutomatiqueProvider(widget.etablissementId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.enEchec == 0
            ? '${r.comptabilises} opération(s) comptabilisée(s).'
            : '${r.comptabilises} comptabilisé(s), ${r.enEchec} encore en attente (voir les incidents).'),
      ));
    } on ErreurComptabilisationAutomatique catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _changerCompte(RegleComptabilisation regle, List<PlanComptable> imputables) async {
    final choix = await showModalBottomSheet<({String? compteId})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, defilement) => ListView(
          controller: defilement,
          children: [
            ListTile(
              title: Text('Compte pour « ${regle.libelle} »', style: Theme.of(context).textTheme.titleMedium),
            ),
            if (regle.personnalisee)
              ListTile(
                key: const Key('regle_par_defaut'),
                leading: const Icon(Icons.restart_alt),
                title: const Text('Revenir au compte par défaut du plan'),
                onTap: () => Navigator.of(context).pop((compteId: null)),
              ),
            for (final c in imputables)
              ListTile(
                key: Key('choix_compte_${c.code}'),
                title: Text(c.libelle),
                trailing: c.id == regle.compteId ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop((compteId: c.id)),
              ),
          ],
        ),
      ),
    );
    if (choix == null || !mounted) return;
    try {
      await ref
          .read(comptabilisationAutomatiqueRepositoryProvider)
          .definirRegle(widget.etablissementId, regle.cle, choix.compteId);
      if (!mounted) return;
      ref.invalidate(etatComptabilisationAutomatiqueProvider(widget.etablissementId));
    } on ErreurComptabilisationAutomatique catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(etatComptabilisationAutomatiqueProvider(widget.etablissementId));
    final plan = ref.watch(planComptableProvider(widget.etablissementId)).value ?? const <PlanComptable>[];
    final parents = {for (final c in plan) if (c.parentId != null) c.parentId};
    final imputables = [for (final c in plan) if (c.actif && !parents.contains(c.id)) c];

    return Scaffold(
      appBar: AppBar(title: const Text('Écritures automatiques')),
      body: etat.when(
        loading: () => ListView(padding: const EdgeInsets.all(16), children: List.generate(3, (_) => const ShimmerCarteListe())),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (e) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(etatComptabilisationAutomatiqueProvider(widget.etablissementId)),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Synthese(etat: e, enCours: _enCours, onRattraper: _rattraper),
              if (e.incidents.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Incidents à traiter', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final i in e.incidents)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(Icons.warning_amber_outlined, color: Theme.of(context).colorScheme.error),
                      title: Text(i.explication),
                      subtitle: Text(
                        '${i.origine} · '
                        '${i.le.day.toString().padLeft(2, '0')}/${i.le.month.toString().padLeft(2, '0')}/${i.le.year}',
                      ),
                    ),
                  ),
              ],
              for (final (titre, aide, regles) in [
                (
                  'Comptes utilisés — frais scolaires',
                  'Débit : le compte du moyen de paiement. Crédit : le compte du type de frais.',
                  [for (final r in e.regles) if (!r.estPaie) r],
                ),
                (
                  'Comptes utilisés — paie',
                  'Bulletin validé : débit salaires (brut), crédit salaires dus (net) et retenues. '
                      'Bulletin payé : débit salaires dus, crédit paiement des salaires.',
                  [for (final r in e.regles) if (r.estPaie) r],
                ),
              ])
                if (regles.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(titre, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    aide,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.encreSecondaire),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(children: [
                      for (final r in regles)
                        ListTile(
                          key: Key('regle_${r.cle}'),
                          leading: Icon(r.estTresorerie
                              ? Icons.account_balance_wallet_outlined
                              : r.estPaie
                                  ? Icons.badge_outlined
                                  : Icons.school_outlined),
                          title: Text(r.libelle),
                          subtitle: Text('${r.compteAffiche}${r.personnalisee ? ' · choisi par l\'école' : ''}'),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _changerCompte(r, imputables),
                        ),
                    ]),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Synthese extends StatelessWidget {
  const _Synthese({required this.etat, required this.enCours, required this.onRattraper});

  final EtatComptabilisationAutomatique etat;
  final bool enCours;
  final VoidCallback onRattraper;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (!etat.active) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Comptabilité simplifiée : les paiements ne passent en comptabilité automatiquement '
            'qu\'une fois les comptes choisis ci-dessous (au moins un moyen de paiement et un type de frais).',
          ),
        ),
      );
    }
    final aJour = etat.aJour;
    final couleur = aJour ? palette.primaire : palette.accent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(aJour ? Icons.check_circle_outline : Icons.pending_actions_outlined, color: couleur),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                aJour ? 'Paiements et paie sont à jour en comptabilité.' : 'Des opérations attendent leur comptabilisation.',
                key: const Key('synthese_comptabilisation'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ]),
          if (!aJour) ...[
            const SizedBox(height: 8),
            if (etat.nonComptabilises > 0) Text('${etat.nonComptabilises} paiement(s) non comptabilisé(s)'),
            if (etat.annulationsEnAttente > 0) Text('${etat.annulationsEnAttente} annulation(s) à reporter'),
            if (etat.paiesASynchroniser > 0)
              Text('${etat.paiesASynchroniser} bulletin(s) de paie à reporter', key: const Key('paies_a_synchroniser')),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('bouton_rattraper'),
              onPressed: enCours ? null : onRattraper,
              icon: const Icon(Icons.sync),
              label: const Text('Rattraper maintenant'),
            ),
          ],
        ]),
      ),
    );
  }
}
