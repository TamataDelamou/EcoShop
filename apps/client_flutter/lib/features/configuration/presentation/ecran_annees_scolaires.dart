import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/choisir_date.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/annee_scolaire.dart';
import '../../scolarite/domain/periode_scolaire.dart';
import '../application/configuration_providers.dart';
import 'elements_configuration.dart';

/// Étape 1 de la mise en route (REG-23) : années scolaires et leur
/// découpage (trimestres ou semestres).
class EcranAnneesScolaires extends ConsumerWidget {
  const EcranAnneesScolaires({super.key, required this.etablissement});

  final Etablissement etablissement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final structure = ref.watch(structureEtablissementProvider(null));
    final annees = structure.valueOrNull?.anneesScolaires ?? const <AnneeScolaire>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Années scolaires')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bouton_nouvelle_annee'),
        onPressed: () => _nouvelleAnnee(context, ref, annees),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle année'),
      ),
      body: structure.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErreurChargement(onReessayer: () => ref.invalidate(structureEtablissementProvider)),
        data: (_) => annees.isEmpty
            ? EtatVide(
                icone: Icons.event_note_outlined,
                titre: 'Aucune année scolaire',
                texte: 'Commencez par créer l’année en cours : ses trimestres (ou semestres) sont créés avec elle.',
                action: FilledButton.icon(
                  onPressed: () => _nouvelleAnnee(context, ref, annees),
                  icon: const Icon(Icons.add),
                  label: const Text('Créer l’année scolaire'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  const Explication(
                    'L’année courante est celle de l’accueil, des inscriptions, des notes et de l’emploi du temps. '
                    'Créez l’année suivante avant la rentrée : ses classes et ses frais peuvent être repris de l’année en cours.',
                  ),
                  for (final a in annees) _CarteAnnee(annee: a, etablissement: etablissement),
                ],
              ),
      ),
    );
  }

  Future<void> _nouvelleAnnee(BuildContext context, WidgetRef ref, List<AnneeScolaire> annees) async {
    final cree = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormulaireAnnee(etablissement: etablissement, annees: annees),
    );
    if (cree == true) {
      ref.invalidate(structureEtablissementProvider);
      rafraichirConfiguration(ref.invalidate, etablissementId: etablissement.id);
    }
  }
}

class _CarteAnnee extends ConsumerWidget {
  const _CarteAnnee({required this.annee, required this.etablissement});

  final AnneeScolaire annee;
  final Etablissement etablissement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: PageStorageKey('annee_${annee.id}'),
        initiallyExpanded: annee.courante,
        leading: Icon(annee.courante ? Icons.star_rounded : Icons.event_note_outlined,
            color: annee.courante ? theme.colorScheme.primary : null),
        title: Text(annee.libelle, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${formaterDate(annee.dateDebut)} → ${formaterDate(annee.dateFin)}'
            '${annee.courante ? ' · année courante' : ''}${annee.cloturee ? ' · clôturée' : ''}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          _Periodes(anneeId: annee.id),
          if (!annee.courante && !annee.cloturee)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final ok = await executer(
                    context,
                    () => ref.read(configurationRepositoryProvider).definirAnneeCourante(annee.id),
                    succes: '${annee.libelle} est désormais l’année courante.',
                  );
                  if (ok) {
                    ref.invalidate(structureEtablissementProvider);
                    rafraichirConfiguration(ref.invalidate, etablissementId: etablissement.id);
                  }
                },
                icon: const Icon(Icons.star_outline),
                label: const Text('En faire l’année courante'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Periodes extends ConsumerWidget {
  const _Periodes({required this.anneeId});

  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodes = ref.watch(structureEtablissementProvider(anneeId)).valueOrNull?.periodesTriees ?? const <PeriodeScolaire>[];
    if (periodes.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Aucune période.'));
    }
    return Column(
      children: [
        for (final p in periodes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(radius: 14, child: Text('${p.ordre}', style: const TextStyle(fontSize: 12))),
            title: Text(p.libelle),
            subtitle: Text('${formaterDate(p.dateDebut)} → ${formaterDate(p.dateFin)}'),
            trailing: IconButton(
              tooltip: 'Modifier les dates',
              icon: const Icon(Icons.edit_calendar_outlined),
              onPressed: () => _modifier(context, ref, p),
            ),
          ),
      ],
    );
  }

  Future<void> _modifier(BuildContext context, WidgetRef ref, PeriodeScolaire p) async {
    final debut = await choisirDate(
      context: context,
      initialDate: p.dateDebut,
      firstDate: DateTime(p.dateDebut.year - 1),
      lastDate: DateTime(p.dateFin.year + 1, 12, 31),
      helpText: 'Début — ${p.libelle}',
    );
    if (debut == null || !context.mounted) return;
    final fin = await choisirDate(
      context: context,
      initialDate: p.dateFin.isAfter(debut) ? p.dateFin : debut.add(const Duration(days: 60)),
      firstDate: debut.add(const Duration(days: 1)),
      lastDate: DateTime(debut.year + 1, 12, 31),
      helpText: 'Fin — ${p.libelle}',
    );
    if (fin == null || !context.mounted) return;
    final ok = await executer(
      context,
      () => ref.read(configurationRepositoryProvider).modifierPeriode(id: p.id, libelle: p.libelle, debut: debut, fin: fin),
      succes: 'Période modifiée.',
    );
    if (ok) ref.invalidate(structureEtablissementProvider);
  }
}

class _FormulaireAnnee extends ConsumerStatefulWidget {
  const _FormulaireAnnee({required this.etablissement, required this.annees});

  final Etablissement etablissement;
  final List<AnneeScolaire> annees;

  @override
  ConsumerState<_FormulaireAnnee> createState() => _FormulaireAnneeState();
}

class _FormulaireAnneeState extends ConsumerState<_FormulaireAnnee> {
  late DateTime _debut;
  late DateTime _fin;
  late final TextEditingController _libelle;
  String _decoupage = 'trimestre';
  bool _courante = true;
  String? _reprendreDe;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    // Rentrée d'octobre en Guinée : année suivante si l'actuelle existe.
    final derniere = widget.annees.isEmpty
        ? null
        : (widget.annees.toList()..sort((a, b) => b.dateDebut.compareTo(a.dateDebut))).first;
    final maintenant = DateTime.now();
    final an = derniere != null ? derniere.dateDebut.year + 1 : (maintenant.month >= 8 ? maintenant.year : maintenant.year - 1);
    _debut = DateTime(an, 10, 1);
    _fin = DateTime(an + 1, 6, 30);
    _libelle = TextEditingController(text: '$an-${an + 1}');
    _reprendreDe = derniere?.id;
    _courante = derniere == null;
  }

  @override
  void dispose() {
    _libelle.dispose();
    super.dispose();
  }

  Future<void> _choisir(bool debut) async {
    final d = await choisirDate(
      context: context,
      initialDate: debut ? _debut : _fin,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: debut ? 'Rentrée' : 'Fin de l’année',
    );
    if (d != null) setState(() => debut ? _debut = d : _fin = d);
  }

  Future<void> _valider() async {
    setState(() => _enCours = true);
    final ok = await executer(
      context,
      () => ref.read(configurationRepositoryProvider).creerAnnee(
            etablissementId: widget.etablissement.id,
            libelle: _libelle.text,
            debut: _debut,
            fin: _fin,
            decoupage: _decoupage,
            courante: _courante,
            reprendreDe: _reprendreDe,
          ),
      succes: 'Année ${_libelle.text.trim()} créée.',
    );
    if (!mounted) return;
    setState(() => _enCours = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bas = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bas),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouvelle année scolaire', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              key: const Key('champ_libelle_annee'),
              controller: _libelle,
              decoration: const InputDecoration(labelText: 'Nom', hintText: '2026-2027', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _choisir(true),
                    icon: const Icon(Icons.event),
                    label: Text('Rentrée : ${formaterDate(_debut)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _choisir(false),
                    icon: const Icon(Icons.event_available),
                    label: Text('Fin : ${formaterDate(_fin)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'trimestre', label: Text('3 trimestres')),
                ButtonSegment(value: 'semestre', label: Text('2 semestres')),
              ],
              selected: {_decoupage},
              onSelectionChanged: (s) => setState(() => _decoupage = s.first),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _courante,
              onChanged: (v) => setState(() => _courante = v),
              title: const Text('Année courante'),
              subtitle: const Text('Celle de l’accueil, des inscriptions et des notes.'),
            ),
            if (widget.annees.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _reprendreDe,
                decoration: const InputDecoration(labelText: 'Reprendre les classes et les frais de', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Ne rien reprendre')),
                  for (final a in widget.annees) DropdownMenuItem<String?>(value: a.id, child: Text(a.libelle)),
                ],
                onChanged: (v) => setState(() => _reprendreDe = v),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('valider_annee'),
              onPressed: _enCours ? null : _valider,
              icon: _enCours
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Créer l’année'),
            ),
          ],
        ),
      ),
    );
  }
}
