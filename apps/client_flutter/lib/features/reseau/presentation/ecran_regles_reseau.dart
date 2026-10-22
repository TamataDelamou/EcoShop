import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../application/transferts_providers.dart';
import '../domain/regles_transferts.dart';
import 'elements_reseau.dart';

/// Règles du réseau (REG-17) : politique de frais, grille, conditions de
/// transfert.
///
/// - Direction Générale : choisit tout ([peutRegler]).
/// - Adjoint : compose la grille ([peutComposerGrille]).
/// - Direction d'une école ([etablissementId]) : lit les règles, compare la
///   grille à ses tarifs, l'adopte si elle est indicative.
class EcranReglesReseau extends ConsumerWidget {
  const EcranReglesReseau({
    super.key,
    required this.reseauId,
    required this.nom,
    this.etablissementId,
    this.peutRegler = false,
    this.peutComposerGrille = false,
  });

  final String reseauId;
  final String nom;
  final String? etablissementId;
  final bool peutRegler;
  final bool peutComposerGrille;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cle = (reseauId: reseauId, etablissementId: etablissementId);
    final regles = ref.watch(reglesReseauProvider(cle));
    return Scaffold(
      appBar: AppBar(title: Text('Règles — $nom')),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(reglesReseauProvider(cle)),
              child: regles.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  ErreurChargementReseau(erreur: e, reessayer: () => ref.invalidate(reglesReseauProvider(cle))),
                ]),
                data: (r) => peutRegler || peutComposerGrille
                    ? _Reglage(regles: r, peutRegler: peutRegler)
                    : _Lecture(regles: r, etablissementId: etablissementId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _signaler(BuildContext context, String texte) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));

// ---------------------------------------------------------------------------
// Lecture (direction d'une école)
// ---------------------------------------------------------------------------
class _Lecture extends ConsumerStatefulWidget {
  const _Lecture({required this.regles, this.etablissementId});

  final ReglesReseau regles;
  final String? etablissementId;

  @override
  ConsumerState<_Lecture> createState() => _LectureState();
}

class _LectureState extends ConsumerState<_Lecture> {
  bool _enCours = false;

  Future<void> _adopter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Adopter la grille du réseau ?'),
        content: const Text(
          'Les tarifs de l’année en cours de votre école seront remplacés par ceux de la grille. '
          'Vous pourrez encore les ajuster ensuite (grille indicative).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Adopter')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _enCours = true);
    try {
      await ref
          .read(transfertsReseauRepositoryProvider)
          .appliquerGrille(widget.regles.reseauId, etablissementId: widget.etablissementId);
      ref.invalidate(reglesReseauProvider);
      if (mounted) _signaler(context, 'Grille adoptée : vos tarifs sont à jour.');
    } catch (e) {
      if (mounted) _signaler(context, messageErreurReseau(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.regles;
    final palette = context.palette;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Frais de scolarité', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Card(
          child: ListTile(
            leading: Icon(r.grilleCommune ? Icons.lock_outline : Icons.tune),
            title: Text(politiquesFrais[r.politiqueFrais] ?? r.politiqueFrais),
            subtitle: Text(explicationsPolitiques[r.politiqueFrais] ?? ''),
          ),
        ),
        if (r.grille.isNotEmpty) ...[
          const SizedBox(height: 8),
          _TableauGrille(regles: r, avecTarifEcole: widget.etablissementId != null),
          if (r.politiqueFrais == 'indicative' && widget.etablissementId != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _enCours ? null : _adopter,
              icon: const Icon(Icons.download_done_outlined),
              label: const Text('Adopter la grille pour mon école'),
            ),
          ],
        ],
        const SizedBox(height: 24),
        Text('Transferts d’élèves entre écoles du réseau', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final c in r.conditionsTransfert)
          ListTile(
            dense: true,
            leading: Icon(Icons.check_circle_outline, color: palette.primaire),
            title: Text(c),
          ),
      ],
    );
  }
}

class _TableauGrille extends StatelessWidget {
  const _TableauGrille({required this.regles, required this.avecTarifEcole});

  final ReglesReseau regles;
  final bool avecTarifEcole;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final devise = regles.deviseCode;
    return Card(
      child: Column(
        children: [
          for (final l in regles.grille)
            ListTile(
              title: Text(l.niveau),
              subtitle: Text([
                'Scolarité ${montantReseau(l.montantAnnuel, devise)}',
                if (l.fraisInscription > 0) 'inscription ${montantReseau(l.fraisInscription, devise)}',
                if (avecTarifEcole)
                  l.tarifEcole == null
                      ? 'votre tarif : non fixé'
                      : 'votre tarif : ${montantReseau(l.tarifEcole!, devise)}',
              ].join(' · ')),
              trailing: avecTarifEcole && l.tarifEcole != null && l.tarifEcole != l.montantAnnuel
                  ? Icon(Icons.compare_arrows, color: palette.accent)
                  : null,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Réglage (Direction Générale, adjoint pour la grille)
// ---------------------------------------------------------------------------
class _LigneSaisie {
  _LigneSaisie({this.niveauId, String montant = '', String inscription = ''})
      : montant = TextEditingController(text: montant),
        inscription = TextEditingController(text: inscription);

  String? niveauId;
  final TextEditingController montant;
  final TextEditingController inscription;
}

class _Reglage extends ConsumerStatefulWidget {
  const _Reglage({required this.regles, required this.peutRegler});

  final ReglesReseau regles;
  final bool peutRegler;

  @override
  ConsumerState<_Reglage> createState() => _ReglageState();
}

class _ReglageState extends ConsumerState<_Reglage> {
  late ReglesReseau _regles = widget.regles;
  late final List<_LigneSaisie> _lignes = [
    for (final l in widget.regles.grille)
      _LigneSaisie(
        niveauId: l.niveauId,
        montant: l.montantAnnuel.toStringAsFixed(0),
        inscription: l.fraisInscription == 0 ? '' : l.fraisInscription.toStringAsFixed(0),
      ),
  ];
  bool _enCours = false;

  @override
  void dispose() {
    for (final l in _lignes) {
      l.montant.dispose();
      l.inscription.dispose();
    }
    super.dispose();
  }

  static String _chiffres(String s) => s.replaceAll(RegExp(r'\D'), '');

  List<LigneGrilleReseau>? _grilleSaisie() {
    final vus = <String?>{};
    final r = <LigneGrilleReseau>[];
    for (final l in _lignes) {
      final montant = double.tryParse(_chiffres(l.montant.text));
      if (montant == null) return null;
      if (!vus.add(l.niveauId)) return null;
      r.add(LigneGrilleReseau(
        niveauId: l.niveauId,
        niveau: '',
        montantAnnuel: montant,
        fraisInscription: double.tryParse(_chiffres(l.inscription.text)) ?? 0,
      ));
    }
    return r;
  }

  Future<void> _enregistrerGrille() async {
    final grille = _grilleSaisie();
    if (grille == null) {
      _signaler(context, 'Chaque ligne doit avoir un montant, et chaque niveau une seule ligne.');
      return;
    }
    setState(() => _enCours = true);
    try {
      await ref.read(transfertsReseauRepositoryProvider).enregistrerGrille(_regles.reseauId, grille);
      ref.invalidate(reglesReseauProvider);
      if (mounted) {
        _signaler(
          context,
          _regles.grilleCommune
              ? 'Grille enregistrée et appliquée à toutes les écoles du réseau.'
              : 'Grille enregistrée.',
        );
      }
    } catch (e) {
      if (mounted) _signaler(context, messageErreurReseau(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _enregistrerRegles() async {
    if (_regles.grilleCommune && !widget.regles.grilleCommune) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Imposer la grille commune ?'),
          content: const Text(
            'Les tarifs de l’année en cours de toutes les écoles membres seront remplacés par la grille du réseau, '
            'et les écoles ne pourront plus les modifier elles-mêmes.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Imposer')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _enCours = true);
    try {
      final r = await ref.read(transfertsReseauRepositoryProvider).parametrer(_regles);
      ref.invalidate(reglesReseauProvider);
      if (mounted) {
        setState(() => _regles = r);
        _signaler(context, 'Règles du réseau enregistrées.');
      }
    } catch (e) {
      if (mounted) _signaler(context, messageErreurReseau(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _appliquerPartout() async {
    setState(() => _enCours = true);
    try {
      final n = await ref.read(transfertsReseauRepositoryProvider).appliquerGrille(_regles.reseauId);
      if (mounted) _signaler(context, 'Grille appliquée à $n école(s).');
    } catch (e) {
      if (mounted) _signaler(context, messageErreurReseau(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final niveaux = _regles.niveaux;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Frais de scolarité', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        RadioGroup<String>(
          groupValue: _regles.politiqueFrais,
          onChanged: (v) {
            if (!widget.peutRegler || v == null) return;
            setState(() => _regles = _regles.copierAvec(politiqueFrais: v));
          },
          child: Column(
            children: [
              for (final p in politiquesFrais.entries)
                RadioListTile<String>(
                  value: p.key,
                  title: Text(p.value),
                  subtitle: Text(explicationsPolitiques[p.key] ?? ''),
                ),
            ],
          ),
        ),
        if (_regles.politiqueFrais != 'autonome') ...[
          const SizedBox(height: 16),
          Text('Grille du réseau (${_regles.deviseCode})', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Une ligne « Tous niveaux » sert de tarif par défaut ; ajoutez une ligne par niveau qui diffère.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final (i, l) in _lignes.indexed)
            Card(
              key: ObjectKey(l),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: l.niveauId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Niveau'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('Tous niveaux (par défaut)')),
                              for (final n in niveaux) DropdownMenuItem<String?>(value: n.id, child: Text(n.nom)),
                            ],
                            onChanged: (v) => setState(() => l.niveauId = v),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Retirer la ligne',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() => _lignes.removeAt(i)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: l.montant,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Scolarité annuelle'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: l.inscription,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Inscription'),
                          ),
                        ),
                        const SizedBox(width: 44),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _enCours ? null : () => setState(() => _lignes.add(_LigneSaisie())),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une ligne'),
              ),
              FilledButton.icon(
                onPressed: _enCours || _lignes.isEmpty ? null : _enregistrerGrille,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Enregistrer la grille'),
              ),
              if (widget.regles.politiqueFrais == 'indicative' && widget.regles.grille.isNotEmpty)
                TextButton.icon(
                  onPressed: _enCours ? null : _appliquerPartout,
                  icon: const Icon(Icons.done_all),
                  label: const Text('Appliquer à toutes les écoles'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Text('Transferts d’élèves', style: theme.textTheme.titleMedium),
        SwitchListTile(
          value: _regles.transfertsOuverts,
          onChanged: widget.peutRegler ? (v) => setState(() => _regles = _regles.copierAvec(transfertsOuverts: v)) : null,
          title: const Text('Transferts ouverts entre les écoles du réseau'),
        ),
        if (_regles.transfertsOuverts) ...[
          SwitchListTile(
            value: _regles.quitusRequis,
            onChanged: widget.peutRegler ? (v) => setState(() => _regles = _regles.copierAvec(quitusRequis: v)) : null,
            title: const Text('Frais de l’année soldés avant le départ'),
            subtitle: const Text('Sinon l’élève peut partir avec un solde, qui reste dû à l’école de départ.'),
          ),
          SwitchListTile(
            value: _regles.validationReseau,
            onChanged: widget.peutRegler ? (v) => setState(() => _regles = _regles.copierAvec(validationReseau: v)) : null,
            title: const Text('Validation par la Direction Générale'),
            subtitle: const Text('Sinon l’école d’accueil décide seule.'),
          ),
          SwitchListTile(
            value: _regles.inscriptionOfferte,
            onChanged:
                widget.peutRegler ? (v) => setState(() => _regles = _regles.copierAvec(inscriptionOfferte: v)) : null,
            title: const Text('Frais d’inscription offerts à l’arrivée'),
          ),
          SwitchListTile(
            value: _regles.dossierPartage,
            onChanged: widget.peutRegler ? (v) => setState(() => _regles = _regles.copierAvec(dossierPartage: v)) : null,
            title: const Text('Dossier transmis à l’école d’accueil'),
            subtitle: const Text('Classe, assiduité de l’année, parents et personne à prévenir.'),
          ),
        ],
        if (widget.peutRegler) ...[
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _enCours ? null : _enregistrerRegles,
            child: const Text('Enregistrer les règles'),
          ),
        ],
      ],
    );
  }
}
