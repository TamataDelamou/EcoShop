import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/comptabilite_providers.dart';
import '../application/referentiel_comptable_providers.dart';
import '../domain/referentiel_comptable.dart';
import 'ecran_changement_plan.dart';

/// Référentiel comptable (REG-03, lot C1) : l'établissement voit son
/// référentiel actuel, répond à trois questions, reçoit une recommandation
/// motivée et DÉCIDE. La base applique ensuite le plan de comptes et ses
/// verrous ; ce gating client est purement ergonomique.
class EcranReferentielComptable extends ConsumerStatefulWidget {
  const EcranReferentielComptable({super.key, required this.etablissementId, this.devise = 'GNF'});

  final String etablissementId;
  final String devise;

  @override
  ConsumerState<EcranReferentielComptable> createState() => _EcranReferentielComptableState();
}

class _EcranReferentielComptableState extends ConsumerState<EcranReferentielComptable> {
  FormeJuridique? _forme;
  final _chiffreAffaires = TextEditingController();
  bool _souhaitReglementaire = true;

  RecommandationReferentiel? _recommandation;
  ReferentielComptable? _selection;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _chiffreAffaires.dispose();
    super.dispose();
  }

  double? get _montant {
    final brut = _chiffreAffaires.text.replaceAll(RegExp(r'[^0-9]'), '');
    return brut.isEmpty ? null : double.parse(brut);
  }

  Future<void> _recommander() async {
    final forme = _forme;
    if (forme == null) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final r = await ref.read(referentielComptableRepositoryProvider).recommander(
            formeJuridique: forme,
            chiffreAffaires: _montant,
            devise: widget.devise,
            souhaitReglementaire: _souhaitReglementaire,
          );
      if (!mounted) return;
      setState(() {
        _recommandation = r;
        _selection = r.referentiel;
      });
    } on ErreurReferentielComptable catch (e) {
      if (mounted) setState(() => _erreur = e.messageUtilisateur);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _confirmer(ParametresComptables actuel) async {
    final choix = _selection;
    if (choix == null) return;
    final remplacePlan = choix.estReglementaire && _planDe(choix) != _planDe(actuel.referentiel);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Adopter : ${choix.libelleCourt} ?'),
        content: Text(remplacePlan
            ? 'Le plan de comptes réglementaire sera installé. Les comptes libres actuels, sans écriture, '
                'seront retirés. Les comptes réglementaires ne pourront plus être modifiés ; vous pourrez '
                'créer des sous-comptes (par exemple 52101 pour une banque précise).'
            : 'Votre plan de comptes actuel est conservé ; seul le référentiel appliqué change.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('confirmer_referentiel'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final resultat = await ref.read(referentielComptableRepositoryProvider).choisir(
            etablissementId: widget.etablissementId,
            referentiel: choix,
            formeJuridique: _forme,
            chiffreAffaires: _montant,
          );
      ref.invalidate(parametresComptablesProvider(widget.etablissementId));
      ref.invalidate(planComptableProvider(widget.etablissementId));
      if (!mounted) return;
      setState(() => _recommandation = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(resultat.comptesCharges > 0
            ? '${resultat.referentiel.libelleCourt} adopté : ${resultat.comptesCharges} comptes installés.'
            : '${resultat.referentiel.libelleCourt} adopté.'),
      ));
    } on ErreurReferentielComptable catch (e) {
      if (mounted) {
        setState(() {
          _erreur = e.messageUtilisateur;
          _changementPossible = e.code == 'ECRITURES_EXISTANTES' ? choix : null;
        });
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  /// Référentiel refusé faute de pouvoir changer de plan directement :
  /// changement préparé avec table de correspondance (REG-03 C6).
  ReferentielComptable? _changementPossible;

  Future<void> _preparerChangement(ReferentielComptable cible) async {
    final applique = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => EcranChangementPlan(etablissementId: widget.etablissementId, cible: cible, forme: _forme),
    ));
    if (applique == true && mounted) {
      setState(() {
        _changementPossible = null;
        _erreur = null;
        _recommandation = null;
      });
    }
  }

  static String? _planDe(ReferentielComptable r) => switch (r) {
        ReferentielComptable.syscohadaSmt || ReferentielComptable.syscohadaNormal => 'syscohada',
        ReferentielComptable.sycebnl => 'sycebnl',
        ReferentielComptable.simplifie => null,
      };

  @override
  Widget build(BuildContext context) {
    final parametres = ref.watch(parametresComptablesProvider(widget.etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Référentiel comptable')),
      body: parametres.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (actuel) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CarteActuelle(parametres: actuel),
            const SizedBox(height: 24),
            Text(actuel.jamaisChoisi ? 'Choisir votre référentiel' : 'Changer de référentiel',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Trois questions ; EcoShop recommande, vous décidez.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.encreSecondaire)),
            const SizedBox(height: 16),
            _question(context, '1. Forme juridique de l\'établissement'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in FormeJuridique.values)
                  ChoiceChip(
                    key: Key('forme_${f.code}'),
                    label: Text(f.libelle),
                    selected: _forme == f,
                    onSelected: (_) => setState(() {
                      _forme = f;
                      _recommandation = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _question(context, '2. Chiffre d\'affaires annuel estimé (facultatif)'),
            TextField(
              key: const Key('chiffre_affaires'),
              controller: _chiffreAffaires,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                suffixText: widget.devise,
                helperText: 'Total annuel des frais encaissés (scolarité, inscriptions, cantine…), hors taxes.',
              ),
              onChanged: (_) => setState(() => _recommandation = null),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const Key('souhait_reglementaire'),
              contentPadding: EdgeInsets.zero,
              title: const Text('3. Souhaitez-vous une comptabilité réglementaire (OHADA) ?'),
              subtitle: const Text('Exigée par la loi pour les entreprises et les associations.'),
              value: _souhaitReglementaire,
              onChanged: (v) => setState(() {
                _souhaitReglementaire = v;
                _recommandation = null;
              }),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('bouton_recommander'),
              onPressed: _forme == null || _enCours ? null : _recommander,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Voir la recommandation'),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_changementPossible != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('preparer_changement_plan'),
                onPressed: () => _preparerChangement(_changementPossible!),
                icon: const Icon(Icons.swap_horiz),
                label: Text('Préparer le passage en ${_changementPossible!.libelleCourt}'),
              ),
            ],
            if (_recommandation != null) ...[
              const SizedBox(height: 20),
              _CarteRecommandation(
                recommandation: _recommandation!,
                selection: _selection,
                actuel: actuel.referentiel,
                onSelection: (r) => setState(() => _selection = r),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('bouton_adopter'),
                onPressed: _enCours || _selection == null ? null : () => _confirmer(actuel),
                child: Text(_selection == actuel.referentiel && !actuel.jamaisChoisi
                    ? 'Confirmer ce référentiel'
                    : 'Adopter ce référentiel'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _question(BuildContext context, String texte) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texte, style: Theme.of(context).textTheme.labelLarge),
      );
}

class _CarteActuelle extends StatelessWidget {
  const _CarteActuelle({required this.parametres});

  final ParametresComptables parametres;

  @override
  Widget build(BuildContext context) {
    final r = parametres.referentiel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: context.palette.primaire.withValues(alpha: 0.12),
              child: Icon(r.estReglementaire ? Icons.verified_outlined : Icons.edit_note_outlined,
                  color: context.palette.primaire),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(parametres.jamaisChoisi ? 'Référentiel actuel (par défaut)' : 'Référentiel actuel',
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(r.libelle, key: const Key('referentiel_actuel'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(r.description, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarteRecommandation extends StatelessWidget {
  const _CarteRecommandation({
    required this.recommandation,
    required this.selection,
    required this.actuel,
    required this.onSelection,
  });

  final RecommandationReferentiel recommandation;
  final ReferentielComptable? selection;
  final ReferentielComptable actuel;
  final ValueChanged<ReferentielComptable> onSelection;

  @override
  Widget build(BuildContext context) {
    final options = [recommandation.referentiel, ...recommandation.alternatives.where((a) => a != recommandation.referentiel)];
    final seuil = recommandation.seuilSmt;

    return Card(
      color: context.palette.primaire.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.lightbulb_outline, color: context.palette.primaire),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Recommandé : ${recommandation.referentiel.libelle}',
                    key: const Key('referentiel_recommande'), style: Theme.of(context).textTheme.titleSmall),
              ),
            ]),
            const SizedBox(height: 8),
            Text(recommandation.raison),
            if (seuil != null) ...[
              const SizedBox(height: 8),
              Text(
                'Seuil du Système minimal de trésorerie : ${_formater(seuil)} ${recommandation.seuilDevise ?? ''}'
                '${recommandation.seuilAConfirmer ? ' (équivalent indicatif, à confirmer par un expert-comptable)' : ''}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            RadioGroup<ReferentielComptable>(
              groupValue: selection,
              onChanged: (v) {
                if (v != null) onSelection(v);
              },
              child: Column(
                children: [
                  for (final r in options)
                    RadioListTile<ReferentielComptable>(
                      key: Key('option_${r.code}'),
                      contentPadding: EdgeInsets.zero,
                      value: r,
                      title: Text(r.libelle),
                      subtitle: Text(_sousTitre(r)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sousTitre(ReferentielComptable r) {
    final etiquettes = [
      if (r == recommandation.referentiel) 'Recommandé',
      if (r == actuel) 'Actuel',
    ];
    return etiquettes.isEmpty ? r.description : '${etiquettes.join(' · ')} — ${r.description}';
  }

  static String _formater(double montant) {
    final chiffres = montant.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < chiffres.length; i++) {
      if (i > 0 && (chiffres.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(chiffres[i]);
    }
    return buffer.toString();
  }
}
