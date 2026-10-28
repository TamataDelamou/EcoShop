import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../etablissement/domain/etablissement.dart';
import '../../referentiel/application/referentiel_providers.dart';
import '../../referentiel/domain/filiere_educative.dart';
import '../../referentiel/domain/niveau_educatif.dart';
import '../../referentiel/presentation/ecran_programme_niveau.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../../scolarite/presentation/ecran_detail_classe.dart';
import '../application/configuration_providers.dart';
import '../domain/configuration.dart';
import 'elements_configuration.dart';
import 'ecran_affectations.dart';
import 'ecran_groupes.dart';

/// Étape 2 de la mise en route (REG-23) : les classes de l'année, rangées
/// par niveau du programme officiel du pays.
class EcranClassesConfiguration extends ConsumerWidget {
  const EcranClassesConfiguration({super.key, required this.etablissement, required this.anneeId});

  final Etablissement etablissement;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final structure = ref.watch(structureEtablissementProvider(anneeId));
    final classes = [...structure.valueOrNull?.classes ?? const <Classe>[]]..retainWhere((c) => c.actif);
    final pays = etablissement.paysCode;
    final niveaux = pays == null ? const <NiveauEducatif>[] : ref.watch(arborescencePaysProvider(pays)).valueOrNull?.niveaux ?? const [];
    final parId = {for (final n in niveaux) n.id: n};
    classes.sort((a, b) {
      final na = parId[a.niveauId]?.ordre ?? 999;
      final nb = parId[b.niveauId]?.ordre ?? 999;
      return na != nb ? na.compareTo(nb) : a.nom.compareTo(b.nom);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Classes')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bouton_ajouter_classes'),
        onPressed: () => _ajouter(context, ref, niveaux, classes),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter des classes'),
      ),
      body: structure.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ErreurChargement(onReessayer: () => ref.invalidate(structureEtablissementProvider(anneeId))),
        data: (_) => classes.isEmpty
            ? EtatVide(
                icone: Icons.class_outlined,
                titre: 'Aucune classe pour cette année',
                texte: 'Choisissez un niveau du programme officiel (6e, 10e année…) et le nombre de classes : '
                    'EcoShop les crée d’un coup (6e A, 6e B…).',
                action: FilledButton.icon(
                  onPressed: () => _ajouter(context, ref, niveaux, classes),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter des classes'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  if (pays == null)
                    const Explication(
                      'Le pays de l’établissement n’est pas renseigné : les niveaux du programme officiel ne peuvent pas être proposés.',
                      icone: Icons.warning_amber_rounded,
                    ),
                  if (classes.any((c) => c.niveauId == null))
                    const Explication(
                      'Rattachez chaque classe à son niveau : il donne les matières, les coefficients et les volumes horaires du programme officiel.',
                      icone: Icons.warning_amber_rounded,
                    ),
                  for (final c in classes)
                    _CarteClasse(
                      classe: c,
                      niveau: parId[c.niveauId],
                      etablissement: etablissement,
                      anneeId: anneeId,
                      onModifier: () => _modifier(context, ref, niveaux, c),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _ajouter(BuildContext context, WidgetRef ref, List<NiveauEducatif> niveaux, List<Classe> existantes) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormulaireClasses(
        etablissement: etablissement,
        anneeId: anneeId,
        niveaux: niveaux,
        existantes: existantes,
      ),
    );
    if (ok == true) {
      ref.invalidate(structureEtablissementProvider);
      rafraichirConfiguration(ref.invalidate, etablissementId: etablissement.id, anneeId: anneeId);
    }
  }

  Future<void> _modifier(BuildContext context, WidgetRef ref, List<NiveauEducatif> niveaux, Classe c) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormulaireClasses(
        etablissement: etablissement,
        anneeId: anneeId,
        niveaux: niveaux,
        existantes: const [],
        classe: c,
      ),
    );
    if (ok == true) {
      ref.invalidate(structureEtablissementProvider);
      rafraichirConfiguration(ref.invalidate, etablissementId: etablissement.id, anneeId: anneeId);
    }
  }
}

class _CarteClasse extends ConsumerWidget {
  const _CarteClasse({
    required this.classe,
    required this.niveau,
    required this.etablissement,
    required this.anneeId,
    required this.onModifier,
  });

  final Classe classe;
  final NiveauEducatif? niveau;
  final Etablissement etablissement;
  final String anneeId;
  final VoidCallback onModifier;

  void _aller(BuildContext context, Widget ecran) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = [
      niveau?.nom ?? 'Niveau à choisir',
      if (classe.capacite != null) '${classe.capacite} places',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(child: Text(classe.code.length > 3 ? classe.code.substring(0, 3) : classe.code)),
            title: Text(classe.nom, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(details),
            onTap: () => _aller(context, EcranDetailClasse(classe: classe)),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'modifier') onModifier();
                if (v == 'retirer') {
                  final confirme = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Retirer ${classe.nom} ?'),
                      content: const Text('La classe n’apparaîtra plus. Ses élèves inscrits gardent leur historique.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retirer')),
                      ],
                    ),
                  );
                  if (confirme == true && context.mounted) {
                    final ok = await executer(context, () => ref.read(configurationRepositoryProvider).retirerClasse(classe.id),
                        succes: 'Classe retirée.');
                    if (ok) {
                      ref.invalidate(structureEtablissementProvider);
                      rafraichirConfiguration(ref.invalidate, etablissementId: etablissement.id, anneeId: anneeId);
                    }
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                PopupMenuItem(value: 'retirer', child: Text('Retirer')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Wrap(
              spacing: 4,
              children: [
                if (niveau != null)
                  TextButton.icon(
                    onPressed: () => _aller(context, EcranProgrammeNiveau(niveau: niveau!, paysNom: etablissement.paysCode ?? '')),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Programme officiel'),
                  ),
                TextButton.icon(
                  onPressed: () => _aller(context, EcranAffectations(etablissement: etablissement, anneeId: anneeId, classe: classe)),
                  icon: const Icon(Icons.co_present_outlined, size: 18),
                  label: const Text('Cours et enseignants'),
                ),
                TextButton.icon(
                  onPressed: () => _aller(context, EcranGroupes(etablissement: etablissement, anneeId: anneeId, classe: classe)),
                  icon: const Icon(Icons.groups_2_outlined, size: 18),
                  label: const Text('Groupes'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ajout de plusieurs classes d'un niveau, ou modification d'une classe.
class _FormulaireClasses extends ConsumerStatefulWidget {
  const _FormulaireClasses({
    required this.etablissement,
    required this.anneeId,
    required this.niveaux,
    required this.existantes,
    this.classe,
  });

  final Etablissement etablissement;
  final String anneeId;
  final List<NiveauEducatif> niveaux;
  final List<Classe> existantes;
  final Classe? classe;

  @override
  ConsumerState<_FormulaireClasses> createState() => _FormulaireClassesState();
}

class _FormulaireClassesState extends ConsumerState<_FormulaireClasses> {
  late String? _niveauId = widget.classe?.niveauId;
  late String? _filiereId = widget.classe?.filiereId;
  late String? _principalId = widget.classe?.enseignantPrincipalId;
  late final _nom = TextEditingController(text: widget.classe?.nom ?? '');
  late final _capacite = TextEditingController(text: widget.classe?.capacite?.toString() ?? '');
  int _nombre = 1;
  bool _enCours = false;

  bool get _modification => widget.classe != null;

  @override
  void dispose() {
    _nom.dispose();
    _capacite.dispose();
    super.dispose();
  }

  NiveauEducatif? get _niveau => widget.niveaux.where((n) => n.id == _niveauId).firstOrNull;

  /// Noms proposés : « 6e A », « 6e B »… à la suite des classes existantes.
  List<String> _noms() {
    final base = _nom.text.trim().isNotEmpty ? _nom.text.trim() : (_niveau?.nom ?? 'Classe');
    if (_nombre == 1 && !widget.existantes.any((c) => c.nom == base)) return [base];
    final noms = <String>[];
    var lettre = 0;
    while (noms.length < _nombre && lettre < 26) {
      final nom = '$base ${String.fromCharCode(65 + lettre)}';
      if (!widget.existantes.any((c) => c.nom == nom)) noms.add(nom);
      lettre++;
    }
    return noms;
  }

  static String _code(String nom) {
    final c = nom.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return c.isEmpty ? 'CL' : (c.length > 12 ? c.substring(0, 12) : c);
  }

  Future<void> _valider() async {
    final depot = ref.read(configurationRepositoryProvider);
    final capacite = int.tryParse(_capacite.text.trim());
    setState(() => _enCours = true);
    final ok = await executer(context, () async {
      if (_modification) {
        final c = widget.classe!;
        await depot.enregistrerClasse(
          id: c.id,
          etablissementId: widget.etablissement.id,
          anneeId: widget.anneeId,
          code: c.code,
          nom: _nom.text.trim().isEmpty ? c.nom : _nom.text.trim(),
          niveauId: _niveauId,
          filiereId: _filiereId,
          capacite: capacite,
          enseignantPrincipalId: _principalId,
        );
      } else {
        final codes = widget.existantes.map((c) => c.code).toSet();
        await depot.creerClasses([
          for (final nom in _noms())
            {
              'etablissement_id': widget.etablissement.id,
              'annee_scolaire_id': widget.anneeId,
              'code': () {
                var code = _code(nom);
                var i = 2;
                while (codes.contains(code)) {
                  code = '${_code(nom)}$i';
                  i++;
                }
                codes.add(code);
                return code;
              }(),
              'nom': nom,
              'niveau_id': _niveauId,
              'filiere_id': _filiereId,
              'capacite': capacite,
            },
        ]);
      }
    }, succes: _modification ? 'Classe modifiée.' : 'Classes créées.');
    if (!mounted) return;
    setState(() => _enCours = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bas = MediaQuery.viewInsetsOf(context).bottom;
    final niveau = _niveau;
    final filieres = niveau == null
        ? const <FiliereEducative>[]
        : ref.watch(arborescenceNiveauProvider(niveau.id)).valueOrNull?.filieres ?? const <FiliereEducative>[];
    final personnel = ref.watch(personnelProvider(widget.etablissement.id)).valueOrNull ?? const <MembrePersonnel>[];
    final enseignants = personnel.where((p) => p.peutEnseigner).toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bas),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_modification ? 'Modifier ${widget.classe!.nom}' : 'Ajouter des classes',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              key: const Key('choix_niveau'),
              initialValue: _niveauId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Niveau (programme officiel)', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Sans niveau')),
                for (final n in [...widget.niveaux]..sort((a, b) => a.ordre.compareTo(b.ordre)))
                  DropdownMenuItem<String?>(value: n.id, child: Text(n.nom)),
              ],
              onChanged: (v) => setState(() {
                _niveauId = v;
                _filiereId = null;
              }),
            ),
            if (filieres.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey('filiere_$_niveauId'),
                initialValue: _filiereId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Série / filière', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Tronc commun')),
                  for (final f in filieres) DropdownMenuItem<String?>(value: f.id, child: Text(f.nom)),
                ],
                onChanged: (v) => setState(() => _filiereId = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _nom,
              decoration: InputDecoration(
                labelText: _modification ? 'Nom de la classe' : 'Nom de base (facultatif)',
                hintText: niveau?.nom ?? '6e',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacite,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Places par classe (facultatif)', border: OutlineInputBorder()),
            ),
            if (!_modification) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Text('Nombre de classes', style: TextStyle(fontWeight: FontWeight.w600))),
                  IconButton(
                    onPressed: _nombre > 1 ? () => setState(() => _nombre--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_nombre', style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    onPressed: _nombre < 12 ? () => setState(() => _nombre++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              Text('Seront créées : ${_noms().join(', ')}', key: const Key('apercu_noms_classes')),
            ] else ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: enseignants.any((e) => e.profileId == _principalId) ? _principalId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Professeur principal', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
                  for (final e in enseignants) DropdownMenuItem<String?>(value: e.profileId, child: Text(e.nomComplet)),
                ],
                onChanged: (v) => setState(() => _principalId = v),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('valider_classes'),
              onPressed: _enCours ? null : _valider,
              icon: _enCours
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_modification ? 'Enregistrer' : 'Créer'),
            ),
          ],
        ),
      ),
    );
  }
}
