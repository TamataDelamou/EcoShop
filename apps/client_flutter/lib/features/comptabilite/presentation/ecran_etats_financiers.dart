import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../export_pdf/data/etats_financiers_pdf_builder.dart';
import '../../export_pdf/presentation/ecran_apercu_pdf.dart';
import '../../themes/application/theme_providers.dart';
import '../application/etats_financiers_providers.dart';
import '../application/pieces_comptables_providers.dart';
import '../domain/etats_financiers.dart';
import '../domain/pieces_comptables.dart';

/// États financiers (REG-03 C4) : bilan, compte de résultat et trésorerie au
/// format du référentiel de l'établissement, comparés à l'exercice précédent,
/// avec la régularisation des produits constatés d'avance et l'export PDF.
class EcranEtatsFinanciers extends ConsumerStatefulWidget {
  const EcranEtatsFinanciers({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranEtatsFinanciers> createState() => _EcranEtatsFinanciersState();
}

class _EcranEtatsFinanciersState extends ConsumerState<EcranEtatsFinanciers> {
  String? _exerciceId;
  bool _enCours = false;

  ({String etablissementId, String exerciceId}) _cle(String exerciceId) =>
      (etablissementId: widget.etablissementId, exerciceId: exerciceId);

  Future<void> _exporter(EtatFinancier etat) async {
    final etablissement = ref.read(etablissementActifProvider);
    if (etablissement == null) return;
    setState(() => _enCours = true);
    try {
      final octets = await construireEtatsFinanciersPdf(
        etat: etat,
        etablissement: etablissement,
        variante: ref.read(themeVariantProvider),
        identite: await ref.read(identitePdfProvider.future),
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EcranApercuPdf(
          titre: 'États financiers ${etat.exerciceLibelle}',
          octets: octets,
          nomFichier: 'etats-financiers-${etat.dateFin.year}.pdf',
        ),
      ));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _passerPca(String exerciceId, ApercuPca apercu) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Passer les produits constatés d\'avance ?'),
        content: Text(
          '${formaterMontant(apercu.total)} de frais encaissés couvrent des mois de l\'année scolaire situés après '
          'la fin de l\'exercice. Ils seront sortis du résultat au 31 décembre (compte 477) et réintégrés '
          'automatiquement le 1er janvier suivant.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(key: const Key('confirmer_pca'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Passer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _enCours = true);
    try {
      final montant = await ref.read(etatsFinanciersRepositoryProvider).passerPca(exerciceId);
      if (!mounted) return;
      ref.invalidate(apercuPcaProvider(exerciceId));
      ref.invalidate(etatFinancierProvider(_cle(exerciceId)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Produits constatés d\'avance passés : ${formaterMontant(montant)}.')),
      );
    } on ErreurEtatsFinanciers catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercices = ref.watch(exercicesComptablesProvider(widget.etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('États financiers')),
      body: exercices.when(
        loading: () => ListView(padding: const EdgeInsets.all(16), children: List.generate(3, (_) => const ShimmerCarteListe())),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (liste) {
          if (liste.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucun exercice comptable : ouvrez-en un pour obtenir les états financiers.', textAlign: TextAlign.center),
              ),
            );
          }
          final courant = liste.where((x) => x.id == _exerciceId).firstOrNull ?? liste.first;
          _exerciceId = courant.id;
          final etat = ref.watch(etatFinancierProvider(_cle(courant.id)));

          return DefaultTabController(
            length: 4,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: DropdownButtonFormField<String>(
                  key: const Key('etats_exercice'),
                  initialValue: courant.id,
                  decoration: const InputDecoration(labelText: 'Exercice', isDense: true),
                  items: [
                    for (final x in liste)
                      DropdownMenuItem(value: x.id, child: Text('${x.libelle}${x.cloture ? ' (clôturé)' : ' (en cours)'}')),
                  ],
                  onChanged: (v) => setState(() => _exerciceId = v),
                ),
              ),
              Expanded(
                child: etat.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text(e is ErreurEtatsFinanciers ? e.messageUtilisateur : 'États indisponibles hors connexion.'),
                  ),
                  data: (e) => Column(children: [
                    _Synthese(etat: e, enCours: _enCours, onExporter: () => _exporter(e)),
                    if (!courant.cloture && e.plan != 'simplifie') _CartePca(exerciceId: courant.id, enCours: _enCours, onPasser: _passerPca),
                    const TabBar(isScrollable: true, tabs: [
                      Tab(text: 'Actif'),
                      Tab(text: 'Passif'),
                      Tab(text: 'Résultat'),
                      Tab(text: 'Trésorerie'),
                    ]),
                    Expanded(
                      child: TabBarView(children: [
                        _TableEtat(etat: e, partie: PartieEtat.actif),
                        _TableEtat(etat: e, partie: PartieEtat.passif),
                        _TableEtat(etat: e, partie: PartieEtat.resultat),
                        _Tresorerie(etat: e),
                      ]),
                    ),
                  ]),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _Synthese extends StatelessWidget {
  const _Synthese({required this.etat, required this.enCours, required this.onExporter});

  final EtatFinancier etat;
  final bool enCours;
  final VoidCallback onExporter;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resultat = etat.resultat ?? 0;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etat.titreReferentiel, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(
                '${etat.libelleResultat} : ${formaterMontant(resultat.abs())}',
                key: const Key('resultat_exercice'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: resultat >= 0 ? palette.primaire : Theme.of(context).colorScheme.error,
                    ),
              ),
            ),
            FilledButton.tonalIcon(
              key: const Key('exporter_etats_pdf'),
              onPressed: enCours ? null : onExporter,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF'),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            Chip(
              avatar: Icon(etat.equilibre ? Icons.check_circle_outline : Icons.error_outline, size: 18),
              label: Text(etat.equilibre ? 'Bilan équilibré' : 'Bilan déséquilibré'),
            ),
            if (etat.provisoire)
              Chip(
                avatar: const Icon(Icons.info_outline, size: 18),
                label: Text(etat.cloture ? 'Présentation à valider' : 'Situation provisoire au ${dateCourte(etat.situationAu)}'),
              ),
          ]),
          if (etat.nonClasses.isNotEmpty)
            Text(
              'Comptes non repris dans les rubriques : ${etat.nonClasses.join(', ')} — à vérifier avec l\'expert-comptable.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ]),
      ),
    );
  }
}

class _CartePca extends ConsumerWidget {
  const _CartePca({required this.exerciceId, required this.enCours, required this.onPasser});

  final String exerciceId;
  final bool enCours;
  final Future<void> Function(String, ApercuPca) onPasser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apercu = ref.watch(apercuPcaProvider(exerciceId)).value;
    if (apercu == null || (apercu.total == 0 && !apercu.dejaPasses)) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: ListTile(
        leading: Icon(apercu.dejaPasses ? Icons.task_alt : Icons.event_repeat_outlined),
        title: Text(apercu.dejaPasses
            ? 'Produits constatés d\'avance passés'
            : 'Produits constatés d\'avance : ${formaterMontant(apercu.total)}'),
        subtitle: Text(apercu.dejaPasses
            ? 'La part de l\'année scolaire qui couvre l\'exercice suivant est reportée.'
            : 'Part des frais encaissés qui couvre l\'exercice suivant (année scolaire à cheval).'),
        trailing: apercu.dejaPasses
            ? null
            : FilledButton(
                key: const Key('passer_pca'),
                onPressed: enCours ? null : () => onPasser(exerciceId, apercu),
                child: const Text('Passer'),
              ),
      ),
    );
  }
}

class _TableEtat extends StatelessWidget {
  const _TableEtat({required this.etat, required this.partie});

  final EtatFinancier etat;
  final PartieEtat partie;

  @override
  Widget build(BuildContext context) {
    final lignes = etat.partie(partie);
    final n1 = etat.exercicePrecedent != null;
    final style = Theme.of(context).textTheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: lignes.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final l = lignes[i];
        final fond = l.total ? context.palette.primaire.withValues(alpha: 0.07) : null;
        return Container(
          key: Key('ligne_${partie.code}_${l.reference}'),
          color: fond,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 32, child: Text(l.reference, style: style.labelSmall)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.libelle, style: l.total ? style.titleSmall : style.bodyMedium),
                if (l.brut != null && (l.amortissements ?? 0) != 0)
                  Text('Brut ${formaterMontant(l.brut!)} − amort. ${formaterMontant(l.amortissements!)}',
                      style: style.bodySmall),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formaterMontant(l.montant), style: l.total ? style.titleSmall : style.bodyMedium),
              if (n1)
                Text('N-1 : ${l.montantN1 == null ? '—' : formaterMontant(l.montantN1!)}', style: style.bodySmall),
            ]),
          ]),
        );
      },
    );
  }
}

class _Tresorerie extends StatelessWidget {
  const _Tresorerie({required this.etat});

  final EtatFinancier etat;

  @override
  Widget build(BuildContext context) {
    final t = etat.tresorerie;
    Widget ligne(String libelle, double v, {bool fort = false}) => ListTile(
          dense: true,
          title: Text(libelle, style: fort ? Theme.of(context).textTheme.titleSmall : null),
          trailing: Text(formaterMontant(v), style: fort ? Theme.of(context).textTheme.titleSmall : null),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      ligne('Solde au début de l\'exercice', t.soldeDebut),
      ligne('Encaissements', t.encaissements),
      ligne('Décaissements', t.decaissements),
      const Divider(),
      ligne('Solde à la fin', t.soldeFin, fort: true),
      const SizedBox(height: 8),
      Text(
        'Banques, Orange Money et caisse. C\'est l\'état de base du Système minimal de trésorerie.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ]);
  }
}
