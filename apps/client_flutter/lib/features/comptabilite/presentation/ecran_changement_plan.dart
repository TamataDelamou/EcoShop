import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../application/comptabilite_providers.dart';
import '../application/referentiel_comptable_providers.dart';
import '../domain/changement_plan.dart';
import '../domain/pieces_comptables.dart';
import '../domain/referentiel_comptable.dart';

/// Changement de plan de comptes avec historique (REG-03 C6).
///
/// La Direction relit la table de correspondance proposée (ancien compte →
/// compte du nouveau plan), corrige ce qu'il faut, puis applique : effet au
/// premier jour de l'exercice, pièces intactes, états publiés archivés,
/// exercice précédent présenté dans le nouveau plan.
class EcranChangementPlan extends ConsumerStatefulWidget {
  const EcranChangementPlan({super.key, required this.etablissementId, required this.cible, this.forme});

  final String etablissementId;
  final ReferentielComptable cible;
  final FormeJuridique? forme;

  @override
  ConsumerState<EcranChangementPlan> createState() => _EcranChangementPlanState();
}

class _EcranChangementPlanState extends ConsumerState<EcranChangementPlan> {
  ChangementPlan? _changement;
  String? _erreur;
  bool _enCours = true;

  @override
  void initState() {
    super.initState();
    _proposer();
  }

  Future<void> _proposer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final c = await ref.read(changementPlanRepositoryProvider).proposer(widget.etablissementId, widget.cible, widget.forme);
      if (mounted) setState(() => _changement = c);
    } on ErreurChangementPlan catch (e) {
      if (mounted) setState(() => _erreur = e.messageUtilisateur);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _choisirCible(LigneCorrespondance ligne) async {
    final changement = _changement;
    if (changement == null) return;
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChoixCible(referentiel: widget.cible, ligne: ligne),
    );
    if (code == null) return;
    try {
      final c = await ref.read(changementPlanRepositoryProvider).definir(changement.id, ligne.ancienCompteId, code);
      if (mounted) setState(() => _changement = c);
    } on ErreurChangementPlan catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    }
  }

  Future<void> _appliquer() async {
    final changement = _changement;
    if (changement == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Passer en ${changement.nouveau.libelleCourt} au ${dateCourte(changement.dateEffet)} ?'),
        content: const Text(
          'Les états financiers déjà publiés sont archivés tels quels. Les pièces passées ne sont pas modifiées : '
          'elles se lisent désormais dans le nouveau plan, ce qui rend l\'exercice précédent comparable. '
          'Les anciens comptes sont retirés (plus de saisie dessus). Ce changement est définitif.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('confirmer_changement_plan'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _enCours = true);
    try {
      final r = await ref.read(changementPlanRepositoryProvider).appliquer(changement.id);
      ref.invalidate(parametresComptablesProvider(widget.etablissementId));
      ref.invalidate(planComptableProvider(widget.etablissementId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${changement.nouveau.libelleCourt} en place : ${r.comptesCharges} comptes installés, '
            '${r.exercicesArchives} exercice(s) archivé(s).'),
      ));
      Navigator.of(context).pop(true);
    } on ErreurChangementPlan catch (e) {
      if (mounted) setState(() => _erreur = e.messageUtilisateur);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _abandonner() async {
    final changement = _changement;
    if (changement != null) {
      try {
        await ref.read(changementPlanRepositoryProvider).abandonner(changement.id);
      } on ErreurChangementPlan {
        // Rien à abandonner côté serveur : on quitte simplement.
      }
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final c = _changement;
    final style = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('Passer en ${widget.cible.libelleCourt}')),
      body: _enCours && c == null
          ? const Center(child: CircularProgressIndicator())
          : c == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreur ?? '', key: const Key('erreur_changement_plan'), textAlign: TextAlign.center),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${c.ancien.libelleCourt} → ${c.nouveau.libelleCourt}', style: style.titleMedium),
                        const SizedBox(height: 4),
                        Text('Effet au ${dateCourte(c.dateEffet)}${c.exercice == null ? '' : ' (${c.exercice})'}.',
                            key: const Key('date_effet_changement')),
                        const SizedBox(height: 8),
                        Text(
                          'Chaque compte utilisé reçoit un compte du nouveau plan. Vérifiez en priorité les lignes '
                          'signalées ; votre expert-comptable peut vous aider.',
                          style: style.bodySmall?.copyWith(color: context.palette.encreSecondaire),
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          Chip(label: Text('${c.lignes.length} compte(s)')),
                          Chip(
                            key: const Key('nb_a_verifier'),
                            avatar: const Icon(Icons.flag_outlined, size: 18),
                            label: Text('${c.aVerifier} à vérifier'),
                          ),
                          if (c.aCompleter > 0)
                            Chip(
                              avatar: Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.error),
                              label: Text('${c.aCompleter} à compléter'),
                            ),
                        ]),
                      ]),
                    ),
                  ),
                  if (_erreur != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 8),
                  for (final l in c.lignes)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        key: Key('correspondance_${l.ancienCode}'),
                        leading: Icon(
                          l.aCompleter
                              ? Icons.error_outline
                              : l.aVerifier
                                  ? Icons.flag_outlined
                                  : Icons.check_circle_outline,
                          color: l.aCompleter
                              ? Theme.of(context).colorScheme.error
                              : l.aVerifier
                                  ? context.palette.accent
                                  : context.palette.primaire,
                        ),
                        title: Text('${l.ancienCode} ${l.ancienIntitule}'),
                        subtitle: Text([
                          l.aCompleter ? '→ à choisir' : '→ ${l.codeCible} ${l.intituleCible ?? ''}',
                          l.origine.libelle,
                          if (l.solde != 0) 'solde ${formaterMontant(l.solde)}',
                        ].join(' · ')),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _choisirCible(l),
                      ),
                    ),
                ]),
      bottomNavigationBar: c == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  TextButton(onPressed: _enCours ? null : _abandonner, child: const Text('Abandonner')),
                  const Spacer(),
                  FilledButton.icon(
                    key: const Key('appliquer_changement_plan'),
                    onPressed: _enCours || !c.applicable ? null : _appliquer,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Appliquer le changement'),
                  ),
                ]),
              ),
            ),
    );
  }
}

/// Choix du compte cible : recherche dans les comptes de détail du nouveau
/// plan, ou sous-compte à garder (ex. 5711 sous 571).
class _ChoixCible extends ConsumerStatefulWidget {
  const _ChoixCible({required this.referentiel, required this.ligne});

  final ReferentielComptable referentiel;
  final LigneCorrespondance ligne;

  @override
  ConsumerState<_ChoixCible> createState() => _ChoixCibleState();
}

class _ChoixCibleState extends ConsumerState<_ChoixCible> {
  final _recherche = TextEditingController();

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comptes = ref.watch(comptesCiblesProvider(widget.referentiel)).valueOrNull ?? const <CompteCible>[];
    final q = _recherche.text.trim().toLowerCase();
    final filtres = [
      for (final c in comptes)
        if (q.isEmpty || c.code.startsWith(q) || c.intitule.toLowerCase().contains(q)) c,
    ];
    final codeLibre = RegExp(r'^[0-9]{2,}$').hasMatch(q) && !comptes.any((c) => c.code == q);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, defilement) => ListView(
        controller: defilement,
        children: [
          ListTile(
            title: Text('${widget.ligne.ancienCode} ${widget.ligne.ancienIntitule}',
                style: Theme.of(context).textTheme.titleMedium),
            subtitle: const Text('Compte du nouveau plan qui le remplace'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('recherche_cible'),
              controller: _recherche,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Numéro ou intitulé'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (codeLibre)
            ListTile(
              key: const Key('cible_sous_compte'),
              leading: const Icon(Icons.subdirectory_arrow_right),
              title: Text('Garder comme sous-compte $q'),
              subtitle: Text('Créé sous son compte de détail, avec l\'intitulé « ${widget.ligne.ancienIntitule} »'),
              onTap: () => Navigator.of(context).pop(q),
            ),
          for (final c in filtres.take(80))
            ListTile(
              key: Key('cible_${c.code}'),
              title: Text(c.libelle),
              trailing: c.code == widget.ligne.codeCible ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(c.code),
            ),
        ],
      ),
    );
  }
}
