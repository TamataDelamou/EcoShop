import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/coefficient.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../referentiel/application/referentiel_providers.dart';
import '../../referentiel/domain/niveau_educatif.dart';
import '../../referentiel/domain/programme_matiere.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../application/configuration_providers.dart';
import '../domain/configuration.dart';
import 'elements_configuration.dart';

/// Matières courantes, proposées en un geste (noms seulement : les
/// coefficients sont ceux de l'école ou de la grille officielle).
const _suggestions = [
  'Mathématiques', 'Physique-Chimie', 'Biologie', 'Français', 'Anglais', 'Philosophie',
  'Histoire', 'Géographie', 'Éducation civique et morale', 'Économie', 'Arabe',
  'Informatique', 'Éducation physique et sportive',
];

/// Mise en route (REG-33) : matières et coefficients, pour chaque niveau et
/// série des classes de l'année.
///
/// Comme Pronote, l'école tient ses matières et leurs coefficients ; elle part
/// du programme national quand il est publié (copie ajustable), ou les crée
/// elle-même tant qu'il ne l'est pas (Guinée : grille officielle des
/// coefficients non publiée en ligne).
class EcranProgrammesEcole extends ConsumerWidget {
  const EcranProgrammesEcole({super.key, required this.etablissement, required this.anneeId});

  final Etablissement etablissement;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final structure = ref.watch(structureEtablissementProvider(anneeId));
    final classes = (structure.valueOrNull?.classes ?? const <Classe>[]).where((c) => c.niveauId != null).toList();
    final pays = etablissement.paysCode;
    final niveaux = pays == null ? const <NiveauEducatif>[] : ref.watch(arborescencePaysProvider(pays)).valueOrNull?.niveaux ?? const [];
    final parNiveau = {for (final n in niveaux) n.id: n};
    final programmes = ref.watch(programmesEcoleProvider(etablissement.id)).valueOrNull ?? const <ProgrammeEcole>[];

    // Couples niveau-série, dans l'ordre des niveaux.
    final couples = <(String, String?)>{for (final c in classes) (c.niveauId!, c.filiereId)}.toList()
      ..sort((a, b) => (parNiveau[a.$1]?.ordre ?? 999).compareTo(parNiveau[b.$1]?.ordre ?? 999));

    return Scaffold(
      appBar: AppBar(title: const Text('Matières et coefficients')),
      body: structure.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErreurChargement(onReessayer: () => ref.invalidate(structureEtablissementProvider(anneeId))),
        data: (_) => couples.isEmpty
            ? const EtatVide(
                icone: Icons.class_outlined,
                titre: 'Aucune classe rattachée à un niveau',
                texte: 'Créez d’abord les classes et choisissez leur niveau (et leur série au lycée).',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const Explication(
                    'Chaque niveau (et chaque série au lycée) a ses matières et leurs coefficients. '
                    'Ils servent aux cours, à l’emploi du temps, aux moyennes et aux bulletins.',
                  ),
                  for (final (niveauId, filiereId) in couples)
                    _CarteNiveau(
                      etablissement: etablissement,
                      niveau: parNiveau[niveauId],
                      niveauId: niveauId,
                      filiereId: filiereId,
                      programme: programmeEcolePour(programmes, niveauId, filiereId),
                      classes: [for (final c in classes) if (c.niveauId == niveauId && c.filiereId == filiereId) c.nom],
                    ),
                ],
              ),
      ),
    );
  }
}

class _CarteNiveau extends ConsumerWidget {
  const _CarteNiveau({
    required this.etablissement,
    required this.niveau,
    required this.niveauId,
    required this.filiereId,
    required this.programme,
    required this.classes,
  });

  final Etablissement etablissement;
  final NiveauEducatif? niveau;
  final String niveauId;
  final String? filiereId;
  final ProgrammeEcole? programme;
  final List<String> classes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arbo = ref.watch(arborescenceNiveauProvider(niveauId)).valueOrNull;
    final serie = filiereId == null ? null : arbo?.filieres.where((f) => f.id == filiereId).firstOrNull;
    final national = arbo?.programmePrincipal(filiereId: filiereId) ?? arbo?.programmePrincipal();
    final titre = [niveau?.nom ?? 'Niveau', if (serie != null) serie.code].join(' · ');
    final p = programme;
    final etat = p != null && p.matieres.isNotEmpty
        ? '${p.matieres.length} matière${p.matieres.length > 1 ? 's' : ''} · coefficients : ${formaterCoefficient(p.totalCoefficients)}'
        : national != null
            ? 'Programme officiel publié : à reprendre'
            : 'Aucune matière : à créer';
    final aFaire = p == null || p.matieres.isEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(child: Icon(aFaire ? Icons.edit_note : Icons.check)),
        title: Text(titre, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$etat\n${classes.join(', ')}'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EcranMatieresProgramme(
            etablissement: etablissement,
            niveauId: niveauId,
            filiereId: filiereId,
            titre: titre,
          ),
        )),
      ),
    );
  }
}

/// Matières et coefficients d'un niveau (et d'une série) pour l'école.
class EcranMatieresProgramme extends ConsumerStatefulWidget {
  const EcranMatieresProgramme({
    super.key,
    required this.etablissement,
    required this.niveauId,
    this.filiereId,
    required this.titre,
  });

  final Etablissement etablissement;
  final String niveauId;
  final String? filiereId;
  final String titre;

  @override
  ConsumerState<EcranMatieresProgramme> createState() => _EcranMatieresProgrammeState();
}

class _EcranMatieresProgrammeState extends ConsumerState<EcranMatieresProgramme> {
  bool _enCours = false;

  void _rafraichir() =>
      rafraichirConfiguration(ref.invalidate, etablissementId: widget.etablissement.id);

  /// Programme de l'école pour ce niveau : créé si besoin (copie du national).
  Future<String?> _programme() async {
    final existant = (ref.read(programmesEcoleProvider(widget.etablissement.id)).valueOrNull ?? const <ProgrammeEcole>[])
        .where((p) => p.niveauId == widget.niveauId && p.filiereId == widget.filiereId)
        .firstOrNull;
    if (existant != null) return existant.id;
    String? id;
    final ok = await executer(context, () async {
      id = await ref.read(configurationRepositoryProvider).adopterProgramme(
            etablissementId: widget.etablissement.id,
            niveauId: widget.niveauId,
            filiereId: widget.filiereId,
          );
    });
    if (ok) _rafraichir();
    return id;
  }

  Future<void> _reprendre() async {
    setState(() => _enCours = true);
    await _programme();
    if (mounted) setState(() => _enCours = false);
  }

  Future<void> _editer({ProgrammeMatiere? matiere, String? nomPropose}) async {
    final resultat = await showModalBottomSheet<_SaisieMatiere>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormulaireMatiere(matiere: matiere, nomPropose: nomPropose),
    );
    if (resultat == null || !mounted) return;
    final programmeId = await _programme();
    if (programmeId == null || !mounted) return;
    // Matière du programme officiel modifiée avant la reprise : c'est sa
    // copie dans le programme de l'école qu'on modifie, pas un doublon.
    var matiereId = matiere?.programmeId == programmeId ? matiere?.id : null;
    if (matiere != null && matiereId == null) {
      try {
        final liste = await ref.read(configurationRepositoryProvider).programmesEcole(widget.etablissement.id);
        matiereId = liste
            .where((p) => p.id == programmeId)
            .firstOrNull
            ?.matieres
            .where((m) => m.code == matiere.code)
            .firstOrNull
            ?.id;
      } catch (_) {}
    }
    if (!mounted) return;
    final ok = await executer(
      context,
      () => ref.read(configurationRepositoryProvider).enregistrerMatiere(
            programmeId: programmeId,
            nom: resultat.nom,
            coefficient: resultat.coefficient,
            volumeAnnuel: resultat.heuresSemaine == null ? null : (resultat.heuresSemaine! * semainesDeCoursMatieres).round(),
            nature: resultat.nature,
            matiereId: matiereId,
          ),
      succes: matiere == null ? 'Matière ajoutée.' : 'Matière enregistrée.',
    );
    if (ok) _rafraichir();
  }

  Future<void> _retirer(ProgrammeMatiere m) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Retirer « ${m.nom} » ?'),
        content: const Text('Les notes et les cours déjà saisis gardent cette matière. Elle ne sera plus proposée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    final ok = await executer(context, () => ref.read(configurationRepositoryProvider).retirerMatiere(m.id),
        succes: 'Matière retirée.');
    if (ok) _rafraichir();
  }

  @override
  Widget build(BuildContext context) {
    final programmes = ref.watch(programmesEcoleProvider(widget.etablissement.id));
    // Programme de l'école pour ce niveau et cette série exactement.
    final propre = (programmes.valueOrNull ?? const <ProgrammeEcole>[])
        .where((p) => p.niveauId == widget.niveauId && p.filiereId == widget.filiereId)
        .firstOrNull;
    final arbo = ref.watch(arborescenceNiveauProvider(widget.niveauId)).valueOrNull;
    final national = arbo?.programmePrincipal(filiereId: widget.filiereId) ?? arbo?.programmePrincipal();
    final matieresNationales = national == null ? const <ProgrammeMatiere>[] : arbo!.matieresDuProgramme(national.id);
    final matieres = propre?.matieres ?? matieresNationales;
    final source = propre != null
        ? 'Programme de l’école'
        : national != null
            ? 'Programme officiel, pas encore repris par l’école : modifier une matière le reprend.'
            : null;

    return Scaffold(
      appBar: AppBar(title: Text('Matières — ${widget.titre}')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bouton_ajouter_matiere'),
        onPressed: () => _editer(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une matière'),
      ),
      body: programmes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErreurChargement(onReessayer: () => ref.invalidate(programmesEcoleProvider(widget.etablissement.id))),
        data: (_) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (source != null) Explication(source),
            if (propre == null && national != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  key: const Key('bouton_reprendre_programme'),
                  onPressed: _enCours ? null : _reprendre,
                  icon: const Icon(Icons.content_copy_outlined),
                  label: const Text('Reprendre le programme officiel pour l’école'),
                ),
              ),
            if (matieres.isEmpty) ...[
              const Explication(
                'Aucune matière pour ce niveau : le programme officiel n’est pas encore publié pour le pays. '
                'Ajoutez les matières de l’école avec les coefficients de la grille officielle.',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final nom in _suggestions)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(nom),
                      onPressed: () => _editer(nomPropose: nom),
                    ),
                ],
              ),
            ],
            for (final m in matieres)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  key: Key('matiere_${m.id}'),
                  title: Text(m.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    ProgrammeMatiere.natures[m.nature] ?? 'Tronc commun',
                    if (m.volumeHoraireAnnuel != null) '${m.volumeHoraireAnnuel} h / an',
                  ].join(' · ')),
                  leading: CircleAvatar(
                    child: Text(m.coefficient == null ? '—' : formaterCoefficient(m.coefficient!),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  trailing: propre == null
                      ? null
                      : IconButton(
                          tooltip: 'Retirer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _retirer(m),
                        ),
                  onTap: () => _editer(matiere: m),
                ),
              ),
            if (matieres.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Total des coefficients : ${formaterCoefficient(matieres.fold<double>(0, (s, m) => s + (m.coefficient ?? 1)))}'
                  ' — une matière sans coefficient compte pour 1.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Semaines de cours retenues pour convertir les heures par semaine en
/// volume annuel (même valeur que l'emploi du temps, REG-24).
const semainesDeCoursMatieres = 32;

class _SaisieMatiere {
  const _SaisieMatiere({required this.nom, this.coefficient, this.heuresSemaine, required this.nature});
  final String nom;
  final double? coefficient;
  final double? heuresSemaine;
  final String nature;
}

class _FormulaireMatiere extends StatefulWidget {
  const _FormulaireMatiere({this.matiere, this.nomPropose});

  final ProgrammeMatiere? matiere;
  final String? nomPropose;

  @override
  State<_FormulaireMatiere> createState() => _FormulaireMatiereState();
}

class _FormulaireMatiereState extends State<_FormulaireMatiere> {
  late final _nom = TextEditingController(text: widget.matiere?.nom ?? widget.nomPropose ?? '');
  late final _coefficient = TextEditingController(
      text: widget.matiere?.coefficient == null ? '' : formaterCoefficient(widget.matiere!.coefficient!));
  late final _heures = TextEditingController(
      text: widget.matiere?.volumeHoraireAnnuel == null
          ? ''
          : formaterCoefficient(widget.matiere!.volumeHoraireAnnuel! / semainesDeCoursMatieres));
  late String _nature = widget.matiere?.nature ?? 'tronc_commun';
  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    _coefficient.dispose();
    _heures.dispose();
    super.dispose();
  }

  void _valider() {
    final nom = _nom.text.trim();
    final coef = _coefficient.text.trim().isEmpty ? null : lireCoefficient(_coefficient.text.trim());
    final heures = _heures.text.trim().isEmpty ? null : lireCoefficient(_heures.text.trim());
    if (nom.isEmpty) return setState(() => _erreur = 'Donnez un nom à la matière.');
    if (_coefficient.text.trim().isNotEmpty && (coef == null || coef <= 0)) {
      return setState(() => _erreur = 'Coefficient : un nombre supérieur à 0 (1 ; 2 ; 2,5…).');
    }
    if (_heures.text.trim().isNotEmpty && (heures == null || heures <= 0)) {
      return setState(() => _erreur = 'Heures par semaine : un nombre supérieur à 0.');
    }
    Navigator.of(context).pop(_SaisieMatiere(nom: nom, coefficient: coef, heuresSemaine: heures, nature: _nature));
  }

  @override
  Widget build(BuildContext context) {
    final bas = MediaQuery.viewInsetsOf(context).bottom;
    final nombre = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bas),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.matiere == null ? 'Nouvelle matière' : 'Modifier la matière',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              key: const Key('champ_nom_matiere'),
              controller: _nom,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Matière', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('champ_coefficient_matiere'),
                    controller: _coefficient,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: nombre,
                    decoration: const InputDecoration(labelText: 'Coefficient', hintText: '2 ; 2,5', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('champ_heures_matiere'),
                    controller: _heures,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: nombre,
                    decoration: const InputDecoration(labelText: 'Heures / semaine', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _nature,
              decoration: const InputDecoration(labelText: 'Nature', border: OutlineInputBorder()),
              items: [
                for (final e in ProgrammeMatiere.natures.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _nature = v ?? _nature),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('valider_matiere'),
              onPressed: _valider,
              icon: const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
