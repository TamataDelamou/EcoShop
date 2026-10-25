import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../export_pdf/data/etats_financiers_pdf_builder.dart';
import '../../export_pdf/presentation/ecran_apercu_pdf.dart';
import '../../themes/application/theme_providers.dart';
import '../application/etats_financiers_providers.dart';
import '../application/pieces_comptables_providers.dart';
import '../domain/etats_financiers.dart';
import '../domain/pieces_comptables.dart';

/// États financiers (REG-03 C4, C5) : bilan, compte de résultat, tableau des
/// flux de trésorerie et notes annexes au format du référentiel de
/// l'établissement, comparés à l'exercice précédent, avec la régularisation
/// des produits constatés d'avance et l'export PDF.
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
      // Tableau des flux et notes annexes joints au document s'ils sont
      // disponibles ; sinon, les états seuls.
      final depot = ref.read(etatsFinanciersRepositoryProvider);
      final exerciceId = _exerciceId;
      TableauFlux? flux;
      NotesAnnexes? notes;
      if (exerciceId != null) {
        try {
          flux = await depot.fluxTresorerie(widget.etablissementId, exerciceId);
          notes = await depot.notesAnnexes(widget.etablissementId, exerciceId);
        } on ErreurEtatsFinanciers {
          // Export des états seuls.
        }
      }
      final octets = await construireEtatsFinanciersPdf(
        etat: etat,
        flux: flux,
        notes: notes,
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
      body: Column(children: [
        const BandeauSynchronisation(),
        Expanded(
          child: exercices.when(
        loading: () => ListView(padding: const EdgeInsets.all(16), children: List.generate(3, (_) => const ShimmerCarteListe())),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e is ErreurPiecesComptables ? e.messageUtilisateur : 'Indisponible pour le moment.', textAlign: TextAlign.center),
          ),
        ),
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
            length: 5,
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
                      Tab(text: 'Flux de trésorerie'),
                      Tab(text: 'Notes annexes'),
                    ]),
                    Expanded(
                      child: TabBarView(children: [
                        _TableEtat(etat: e, partie: PartieEtat.actif),
                        _TableEtat(etat: e, partie: PartieEtat.passif),
                        _TableEtat(etat: e, partie: PartieEtat.resultat),
                        _OngletFlux(cle: _cle(courant.id)),
                        _OngletNotes(cle: _cle(courant.id)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ]),
          );
        },
      ),
        ),
      ]),
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
    final apercu = ref.watch(apercuPcaProvider(exerciceId)).valueOrNull;
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

String _cellule(Object? v, String colonne) {
  if (v == null) return '—';
  if (v is num) {
    if (colonne.contains('%')) return '${v.toStringAsFixed(1).replaceAll('.', ',')} %';
    return formaterMontant(v.toDouble());
  }
  return '$v';
}

/// Tableau des flux de trésorerie (REG-03 C5) : modèle du référentiel,
/// colonne N-1, contrôle « trésorerie de clôture = bilan ».
class _OngletFlux extends ConsumerWidget {
  const _OngletFlux({required this.cle});

  final ({String etablissementId, String exerciceId}) cle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flux = ref.watch(fluxTresorerieProvider(cle));
    final style = Theme.of(context).textTheme;
    return flux.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e is ErreurEtatsFinanciers ? e.messageUtilisateur : 'Indisponible hors connexion.')),
      data: (t) {
        final zb = t.lignes.where((l) => l.reference == 'ZB').firstOrNull?.montant;
        final ecartMethodes = t.operationnelDirect == null || zb == null ? 0.0 : zb - t.operationnelDirect!;
        final n1 = t.lignes.any((l) => l.montantN1 != null);
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          Text(
            t.methode == 'indirecte'
                ? 'Méthode indirecte (à partir de la capacité d\'autofinancement), modèle SYSCOHADA révisé.'
                : t.plan == 'sycebnl'
                    ? 'Méthode directe, modèle SYCEBNL : chaque encaissement et décaissement est classé selon sa pièce.'
                    : 'Encaissements et décaissements classés selon leur pièce.',
            style: style.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final l in t.visibles)
            Container(
              key: Key('flux_${l.reference}'),
              color: l.total ? context.palette.primaire.withValues(alpha: 0.07) : null,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 32, child: Text(l.reference, style: style.labelSmall)),
                Expanded(child: Text(l.libelle, style: l.total ? style.titleSmall : style.bodyMedium)),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(formaterMontant(l.montant), style: l.total ? style.titleSmall : style.bodyMedium),
                  if (n1) Text('N-1 : ${l.montantN1 == null ? '—' : formaterMontant(l.montantN1!)}', style: style.bodySmall),
                ]),
              ]),
            ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              key: const Key('controle_flux'),
              leading: Icon(t.concordant ? Icons.verified_outlined : Icons.error_outline,
                  color: t.concordant ? context.palette.primaire : Theme.of(context).colorScheme.error),
              title: Text(t.concordant
                  ? 'Trésorerie de clôture = trésorerie du bilan'
                  : 'Écart de ${formaterMontant(t.ecartCloture)} avec la trésorerie du bilan'),
              subtitle: Text([
                'Trésorerie du bilan : ${formaterMontant(t.tresorerieBilan)}',
                if (ecartMethodes.abs() >= 0.5)
                  'Rapprochement : les flux opérationnels constatés pièce par pièce (${formaterMontant(t.operationnelDirect!)}) '
                      'diffèrent de la méthode indirecte de ${formaterMontant(ecartMethodes)} — à analyser avec l\'expert-comptable.',
              ].join('\n')),
            ),
          ),
        ]);
      },
    );
  }
}

/// Notes annexes (REG-03 C5) : notes calculées et notes rédigées par
/// l'école, modifiables tant que l'exercice est ouvert.
class _OngletNotes extends ConsumerWidget {
  const _OngletNotes({required this.cle});

  final ({String etablissementId, String exerciceId}) cle;

  Future<void> _rediger(BuildContext context, WidgetRef ref, NoteAnnexe note) async {
    final texte = await showDialog<String>(context: context, builder: (_) => _DialogueNote(note: note));
    if (texte == null) return;
    try {
      await ref.read(etatsFinanciersRepositoryProvider).enregistrerNote(cle.exerciceId, note.modifiable!, texte);
      ref.invalidate(notesAnnexesProvider(cle));
    } on ErreurEtatsFinanciers catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesAnnexesProvider(cle));
    final style = Theme.of(context).textTheme;
    return notes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(e is ErreurEtatsFinanciers ? e.messageUtilisateur : 'Indisponible hors connexion.')),
      data: (n) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        if (!n.cloture)
          Text('Les notes rédigées se complètent avant la clôture de l\'exercice ; elles sont ensuite figées.',
              style: style.bodySmall),
        for (final note in n.notes)
          Card(
            key: Key('note_${note.code}'),
            child: ExpansionTile(
              title: Text('Note ${note.code} — ${note.titre}'),
              subtitle: note.vide ? Text(note.modifiable != null ? 'À rédiger' : 'Sans objet', style: style.bodySmall) : null,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.estTableau && note.lignes.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 36,
                      dataRowMinHeight: 32,
                      dataRowMaxHeight: 48,
                      columns: [for (final c in note.colonnes) DataColumn(label: Text(c, style: style.labelSmall))],
                      rows: [
                        for (final l in note.lignes)
                          DataRow(cells: [
                            for (var i = 0; i < note.colonnes.length; i++)
                              DataCell(Text(i < l.length ? _cellule(l[i], note.colonnes[i]) : '')),
                          ]),
                      ],
                    ),
                  ),
                if (!note.estTableau && !note.vide) Text(note.texte!),
                if (note.modifiable != null && !n.cloture)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: Key('rediger_${note.modifiable}'),
                      onPressed: () => _rediger(context, ref, note),
                      icon: const Icon(Icons.edit_note_outlined),
                      label: Text(note.code == '1' ? 'Ajouter des précisions' : 'Rédiger'),
                    ),
                  ),
              ],
            ),
          ),
      ]),
    );
  }
}

class _DialogueNote extends StatefulWidget {
  const _DialogueNote({required this.note});

  final NoteAnnexe note;

  @override
  State<_DialogueNote> createState() => _DialogueNoteState();
}

class _DialogueNoteState extends State<_DialogueNote> {
  // La note 1 mêle texte généré et précisions de l'école : on ne reprend
  // pas le texte généré dans la saisie.
  late final _texte = TextEditingController(text: widget.note.code == '1' ? '' : widget.note.texte);

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.note.titre),
      content: SizedBox(
        width: 520,
        child: TextField(
          key: const Key('texte_note'),
          controller: _texte,
          autofocus: true,
          minLines: 4,
          maxLines: 12,
          maxLength: 8000,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Retour')),
        FilledButton(
          key: const Key('enregistrer_note'),
          onPressed: () => Navigator.of(context).pop(_texte.text),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
