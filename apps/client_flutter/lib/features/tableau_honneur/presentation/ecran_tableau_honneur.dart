import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configuration/application/configuration_providers.dart';
import '../../configuration/domain/configuration.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../../scolarite/domain/inscription.dart';
import '../../scolarite/domain/periode_scolaire.dart';
import '../data/tableau_honneur_repository.dart';

/// Tableau d'honneur (REG-39) : meilleurs élèves de chaque classe (bulletins
/// publiés de la période choisie) et distinctions de l'école (meilleur
/// professeur, prix d'excellence, meilleure conduite…). Visible de toute la
/// communauté de l'école ; la direction décerne les distinctions.
class EcranTableauHonneur extends ConsumerStatefulWidget {
  const EcranTableauHonneur({super.key, required this.etablissementId, required this.anneeId, this.direction = false});

  final String etablissementId;
  final String anneeId;
  final bool direction;

  @override
  ConsumerState<EcranTableauHonneur> createState() => _EcranTableauHonneurState();
}

class _EcranTableauHonneurState extends ConsumerState<EcranTableauHonneur> {
  String? _periodeId;
  bool _periodeChoisie = false;

  ParamsHonneur get _params => (etablissementId: widget.etablissementId, anneeId: widget.anneeId, periodeId: _periodeId);

  Future<void> _decerner() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormulaireDistinction(
        etablissementId: widget.etablissementId,
        anneeId: widget.anneeId,
        periodeId: _periodeId,
      ),
    );
    if (ok == true) ref.invalidate(tableauHonneurProvider(_params));
  }

  @override
  Widget build(BuildContext context) {
    final structure = ref.watch(structureEtablissementProvider(widget.anneeId)).valueOrNull;
    final periodes = structure?.periodesTriees ?? const <PeriodeScolaire>[];
    // Par défaut : la dernière période commencée.
    if (!_periodeChoisie && periodes.isNotEmpty) {
      final maintenant = DateTime.now();
      final commencees = periodes.where((p) => !p.dateDebut.isAfter(maintenant)).toList();
      _periodeId = (commencees.isNotEmpty ? commencees.last : periodes.first).id;
      _periodeChoisie = true;
    }
    final tableau = ref.watch(tableauHonneurProvider(_params));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tableau d’honneur')),
      floatingActionButton: widget.direction
          ? FloatingActionButton.extended(
              key: const Key('bouton_decerner'),
              onPressed: _decerner,
              icon: const Icon(Icons.military_tech_outlined),
              label: const Text('Décerner'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(tableauHonneurProvider(_params)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (periodes.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final p in periodes)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('periode_${p.id}'),
                        label: Text(p.libelle),
                        selected: _periodeId == p.id,
                        onSelected: (_) => setState(() => _periodeId = p.id),
                      ),
                    ),
                  ChoiceChip(
                    label: const Text('Année'),
                    selected: _periodeId == null,
                    onSelected: (_) => setState(() => _periodeId = null),
                  ),
                ]),
              ),
            tableau.when(
              loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              error: (_, _) => const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Tableau d’honneur indisponible hors connexion pour le moment.', textAlign: TextAlign.center),
              ),
              data: (t) {
                final distinctionsPersonnel = t.distinctions.where((d) => d.categorie != 'eleve').toList();
                final distinctionsEleves = t.distinctions.where((d) => d.categorie == 'eleve').toList();
                final parClasse = <String, List<EleveHonneur>>{};
                for (final e in t.eleves) {
                  parClasse.putIfAbsent(e.classeNom, () => []).add(e);
                }
                if (t.eleves.isEmpty && t.distinctions.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Rien pour le moment. Les meilleurs élèves apparaissent dès que les bulletins de la période '
                      'sont publiés${widget.direction ? ' ; les distinctions, quand vous en décernez' : ''}.',
                      key: const Key('honneur_vide'),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (distinctionsPersonnel.isNotEmpty) ...[
                    _Titre('Enseignants et personnel à l’honneur', theme),
                    for (final d in distinctionsPersonnel) _CarteDistinction(distinction: d, direction: widget.direction, params: _params),
                  ],
                  if (parClasse.isNotEmpty) ...[
                    _Titre('Meilleurs élèves', theme),
                    for (final entree in parClasse.entries)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(entree.key, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            for (final e in entree.value)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                leading: _Medaille(rang: e.rang),
                                title: Text(e.nom),
                                trailing: e.moyenne == null
                                    ? null
                                    : Text('${e.moyenne!.toStringAsFixed(2).replaceAll('.', ',')} / 20',
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                              ),
                          ]),
                        ),
                      ),
                  ],
                  if (distinctionsEleves.isNotEmpty) ...[
                    _Titre('Distinctions des élèves', theme),
                    for (final d in distinctionsEleves) _CarteDistinction(distinction: d, direction: widget.direction, params: _params),
                  ],
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte, this.theme);

  final String texte;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Text(texte.toUpperCase(),
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      );
}

class _Medaille extends StatelessWidget {
  const _Medaille({required this.rang});

  final int rang;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (rang) {
      1 => const Color(0xFFC9A227),
      2 => const Color(0xFF9EA4AA),
      _ => const Color(0xFFB0703C),
    };
    return Semantics(
      label: rang == 1 ? '1er' : '${rang}e',
      child: CircleAvatar(
        radius: 16,
        backgroundColor: couleur,
        child: Text('$rang', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _CarteDistinction extends ConsumerWidget {
  const _CarteDistinction({required this.distinction, required this.direction, required this.params});

  final Distinction distinction;
  final bool direction;
  final ParamsHonneur params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = distinction;
    final icone = switch (d.categorie) {
      'enseignant' => Icons.school_outlined,
      'personnel' => Icons.badge_outlined,
      _ => Icons.emoji_events_outlined,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        key: Key('distinction_${d.id}'),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFFFF1D6),
          child: Icon(icone, color: const Color(0xFF855004)),
        ),
        title: Text(d.titre, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([d.nom, if (d.motif != null) d.motif!].join('\n')),
        isThreeLine: d.motif != null,
        trailing: direction
            ? IconButton(
                tooltip: 'Retirer',
                icon: const Icon(Icons.close),
                onPressed: () async {
                  try {
                    await ref.read(tableauHonneurRepositoryProvider).retirer(d.id);
                    ref.invalidate(tableauHonneurProvider(params));
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Retrait impossible pour le moment.')));
                    }
                  }
                },
              )
            : null,
      ),
    );
  }
}

/// Décerner une distinction : à un enseignant, un membre du personnel ou un
/// élève (choisi dans sa classe).
class _FormulaireDistinction extends ConsumerStatefulWidget {
  const _FormulaireDistinction({required this.etablissementId, required this.anneeId, this.periodeId});

  final String etablissementId;
  final String anneeId;
  final String? periodeId;

  @override
  ConsumerState<_FormulaireDistinction> createState() => _FormulaireDistinctionState();
}

class _FormulaireDistinctionState extends ConsumerState<_FormulaireDistinction> {
  static const _titresEnseignant = ['Meilleur professeur', 'Professeur le plus assidu', 'Prix de l’innovation pédagogique'];
  static const _titresEleve = ['Prix d’excellence', 'Meilleure conduite', 'Prix d’assiduité', 'Meilleure progression'];
  static const _titresPersonnel = ['Membre du personnel à l’honneur', 'Prix du dévouement'];

  String _categorie = 'enseignant';
  String? _profileId;
  String? _classeId;
  String? _ficheId;
  final _titre = TextEditingController(text: _titresEnseignant.first);
  final _motif = TextEditingController();
  bool _toutePeriode = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _titre.dispose();
    _motif.dispose();
    super.dispose();
  }

  List<String> get _suggestions => switch (_categorie) {
        'eleve' => _titresEleve,
        'personnel' => _titresPersonnel,
        _ => _titresEnseignant,
      };

  Future<void> _valider() async {
    final eleve = _categorie == 'eleve';
    if ((eleve && _ficheId == null) || (!eleve && _profileId == null) || _titre.text.trim().isEmpty) {
      setState(() => _erreur = 'Choisissez la personne et le titre de la distinction.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await ref.read(tableauHonneurRepositoryProvider).decerner(
            etablissementId: widget.etablissementId,
            anneeId: widget.anneeId,
            periodeId: _toutePeriode ? null : widget.periodeId,
            categorie: _categorie,
            ficheEleveId: eleve ? _ficheId : null,
            profileId: eleve ? null : _profileId,
            titre: _titre.text,
            motif: _motif.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _erreur = 'Enregistrement impossible pour le moment. Vérifiez votre connexion.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final personnel = ref.watch(personnelProvider(widget.etablissementId)).valueOrNull ?? const <MembrePersonnel>[];
    final candidats = [
      for (final p in personnel)
        if (p.actif && (_categorie == 'enseignant' ? p.role == 'enseignant' : p.role != 'enseignant')) p,
    ]..sort((a, b) => a.nomComplet.compareTo(b.nomComplet));
    final classes = [
      for (final c in ref.watch(structureEtablissementProvider(widget.anneeId)).valueOrNull?.classes ?? const <Classe>[])
        if (c.actif) c,
    ]..sort((a, b) => a.nom.compareTo(b.nom));
    final eleves = _classeId == null
        ? const <Inscription>[]
        : ref.watch(inscriptionsDeClasseProvider(_classeId!)).valueOrNull ?? const <Inscription>[];
    final bas = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bas),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Décerner une distinction', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'enseignant', label: Text('Enseignant')),
              ButtonSegment(value: 'eleve', label: Text('Élève')),
              ButtonSegment(value: 'personnel', label: Text('Personnel')),
            ],
            selected: {_categorie},
            onSelectionChanged: (s) => setState(() {
              _categorie = s.first;
              _profileId = null;
              _ficheId = null;
              _titre.text = _suggestions.first;
            }),
          ),
          const SizedBox(height: 12),
          if (_categorie == 'eleve') ...[
            DropdownButtonFormField<String?>(
              initialValue: _classeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Classe', border: OutlineInputBorder()),
              items: [for (final c in classes) DropdownMenuItem<String?>(value: c.id, child: Text(c.nom))],
              onChanged: (v) => setState(() {
                _classeId = v;
                _ficheId = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('eleves_$_classeId'),
              initialValue: _ficheId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Élève', border: OutlineInputBorder()),
              items: [
                for (final i in eleves)
                  if (i.fiche != null) DropdownMenuItem<String?>(value: i.ficheEleveId, child: Text(i.fiche!.nomComplet)),
              ],
              onChanged: (v) => setState(() => _ficheId = v),
            ),
          ] else
            DropdownButtonFormField<String?>(
              key: ValueKey('personnes_$_categorie'),
              initialValue: _profileId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _categorie == 'enseignant' ? 'Enseignant' : 'Membre du personnel',
                border: const OutlineInputBorder(),
              ),
              items: [for (final p in candidats) DropdownMenuItem<String?>(value: p.profileId, child: Text(p.nomComplet))],
              onChanged: (v) => setState(() => _profileId = v),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final s in _suggestions)
              ActionChip(label: Text(s), onPressed: () => setState(() => _titre.text = s)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _titre,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Titre', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _motif,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Pourquoi (facultatif)', border: OutlineInputBorder()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pour toute l’année'),
            subtitle: const Text('Sinon, pour la période affichée'),
            value: _toutePeriode,
            onChanged: (v) => setState(() => _toutePeriode = v),
          ),
          if (_erreur != null) Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('valider_distinction'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _enCours ? null : _valider,
            child: const Text('Décerner'),
          ),
        ]),
      ),
    );
  }
}
