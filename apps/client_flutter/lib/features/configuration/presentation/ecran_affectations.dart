import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../etablissement/domain/etablissement.dart';
import '../../planification/application/planification_providers.dart';
import '../../planification/domain/salle.dart';
import '../../referentiel/application/referentiel_providers.dart';
import '../../referentiel/domain/programme_matiere.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../application/configuration_providers.dart';
import '../domain/configuration.dart';
import 'ecran_matieres_programme.dart';
import 'elements_configuration.dart';
import '../../../core/format/coefficient.dart';

/// Nombre de semaines de cours retenu pour passer du volume annuel du
/// programme officiel à un volume par semaine.
const semainesDeCours = 32;

/// Cours et enseignants (REG-23/24) : pour chaque classe, les matières du
/// programme officiel, l'enseignant qui les donne, les heures par semaine
/// et la durée des séances. C'est la liste des « cours à placer » de
/// l'emploi du temps automatique.
class EcranAffectations extends ConsumerWidget {
  const EcranAffectations({super.key, required this.etablissement, required this.anneeId, this.classe});

  final Etablissement etablissement;
  final String anneeId;
  final Classe? classe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = classe;
    if (c == null) return _ListeClasses(etablissement: etablissement, anneeId: anneeId);
    return _CoursDeClasse(etablissement: etablissement, anneeId: anneeId, classe: c);
  }
}

class _ListeClasses extends ConsumerWidget {
  const _ListeClasses({required this.etablissement, required this.anneeId});

  final Etablissement etablissement;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = [...ref.watch(structureEtablissementProvider(anneeId)).valueOrNull?.classes ?? const <Classe>[]]
      ..retainWhere((c) => c.actif)
      ..sort((a, b) => a.nom.compareTo(b.nom));
    final affectations = ref.watch(affectationsAnneeProvider(anneeId));
    final liste = affectations.valueOrNull ?? const <AffectationCours>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Cours et enseignants')),
      body: affectations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErreurChargement(onReessayer: () => ref.invalidate(affectationsAnneeProvider(anneeId))),
        data: (_) => classes.isEmpty
            ? const EtatVide(
                icone: Icons.class_outlined,
                titre: 'Créez d’abord les classes',
                texte: 'Les cours se répartissent classe par classe.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const Explication(
                    'Pour chaque classe : qui enseigne quelle matière, combien d’heures par semaine. '
                    'Ces cours sont ceux que l’emploi du temps automatique place dans la semaine.',
                  ),
                  for (final c in classes)
                    () {
                      final cours = liste.where((a) => a.classeId == c.id).toList();
                      final heures = cours.where((a) => a.groupeId == null).fold<int>(0, (s, a) => s + (a.heuresParSemaine ?? 0));
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(cours.isEmpty ? Icons.radio_button_unchecked : Icons.check_circle,
                              color: cours.isEmpty ? null : Theme.of(context).colorScheme.primary),
                          title: Text(c.nom, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(cours.isEmpty ? 'Aucun cours attribué' : '${cours.length} cours · $heures h par semaine'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => EcranAffectations(etablissement: etablissement, anneeId: anneeId, classe: c),
                          )),
                        ),
                      );
                    }(),
                ],
              ),
      ),
    );
  }
}

class _CoursDeClasse extends ConsumerWidget {
  const _CoursDeClasse({required this.etablissement, required this.anneeId, required this.classe});

  final Etablissement etablissement;
  final String anneeId;
  final Classe classe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final affectations = ref.watch(affectationsAnneeProvider(anneeId));
    final cours = (affectations.valueOrNull ?? const <AffectationCours>[]).where((a) => a.classeId == classe.id).toList();
    final niveauId = classe.niveauId;
    final arbo = niveauId == null ? null : ref.watch(arborescenceNiveauProvider(niveauId)).valueOrNull;
    // REG-33 : programme de l'école d'abord (ajusté, ou créé tant que le
    // programme national n'est pas publié), sinon programme national.
    final programmesEcole = ref.watch(programmesEcoleProvider(etablissement.id)).valueOrNull ?? const <ProgrammeEcole>[];
    final programmeEcole = programmeEcolePour(programmesEcole, niveauId, classe.filiereId);
    final programme = arbo?.programmePrincipal(filiereId: classe.filiereId) ?? arbo?.programmePrincipal();
    final matieres = programmeEcole != null
        ? programmeEcole.matieres
        : programme == null
            ? const <ProgrammeMatiere>[]
            : arbo!.matieresDuProgramme(programme.id);
    final nomProgramme = programmeEcole != null ? 'Programme de l’école' : programme == null ? null : 'Programme officiel : ${programme.nom}';
    final groupes = (ref.watch(groupesProvider(anneeId)).valueOrNull ?? const <GroupePedagogique>[])
        .where((g) => g.classeId == classe.id)
        .toList();
    final heures = cours.where((a) => a.groupeId == null).fold<int>(0, (s, a) => s + (a.heuresParSemaine ?? 0));
    final nomsGroupes = {for (final g in groupes) g.id: g.nom};

    // Matières du programme, puis cours hors programme.
    final idsProgramme = matieres.map((m) => m.id).toSet();
    final horsProgramme = cours.where((a) => !idsProgramme.contains(a.matiereId)).toList();

    return Scaffold(
      appBar: AppBar(title: Text('Cours — ${classe.nom}')),
      body: affectations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErreurChargement(onReessayer: () => ref.invalidate(affectationsAnneeProvider(anneeId))),
        data: (_) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: Text('$heures h de cours par semaine'),
                subtitle: Text(niveauId == null
                    ? 'Rattachez la classe à un niveau pour voir ses matières.'
                    : nomProgramme ?? 'Aucune matière pour ce niveau'),
                trailing: niveauId == null
                    ? null
                    : TextButton(
                        key: const Key('cours_matieres_coefficients'),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => EcranMatieresProgramme(
                            etablissement: etablissement,
                            niveauId: niveauId,
                            filiereId: classe.filiereId,
                            titre: classe.nom,
                          ),
                        )),
                        child: const Text('Matières'),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            if (matieres.isEmpty && cours.isEmpty && niveauId != null)
              EtatVide(
                icone: Icons.menu_book_outlined,
                titre: 'Aucune matière pour ce niveau',
                texte: 'Le programme officiel n’est pas encore publié pour le pays. '
                    'Créez les matières de l’école et leurs coefficients : vous pourrez ensuite attribuer les cours.',
                action: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EcranMatieresProgramme(
                      etablissement: etablissement,
                      niveauId: niveauId,
                      filiereId: classe.filiereId,
                      titre: classe.nom,
                    ),
                  )),
                  icon: const Icon(Icons.add),
                  label: const Text('Créer les matières'),
                ),
              ),
            for (final m in matieres) ...[
              _LigneMatiere(
                matiere: m,
                cours: cours.where((a) => a.matiereId == m.id).toList(),
                nomsGroupes: nomsGroupes,
                onAttribuer: (existant) => _editer(context, ref, m, existant, groupes),
              ),
            ],
            for (final a in horsProgramme)
              ListTile(
                title: Text(a.nomMatiere ?? 'Cours'),
                subtitle: Text('${a.nomEnseignant ?? '—'} · ${a.heuresParSemaine ?? 0} h'),
                onTap: () => _editer(context, ref, null, a, groupes),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editer(
    BuildContext context,
    WidgetRef ref,
    ProgrammeMatiere? matiere,
    AffectationCours? existant,
    List<GroupePedagogique> groupes,
  ) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormulaireCours(
        etablissement: etablissement,
        anneeId: anneeId,
        classe: classe,
        matiere: matiere,
        existant: existant,
        groupes: groupes,
      ),
    );
    if (ok == true) rafraichirConfiguration(ref.invalidate, etablissementId: etablissement.id, anneeId: anneeId);
  }
}

class _LigneMatiere extends StatelessWidget {
  const _LigneMatiere({required this.matiere, required this.cours, required this.nomsGroupes, required this.onAttribuer});

  final ProgrammeMatiere matiere;
  final List<AffectationCours> cours;
  final Map<String, String> nomsGroupes;
  final void Function(AffectationCours? existant) onAttribuer;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    final officiel = matiere.volumeHoraireAnnuel == null
        ? null
        : '${(matiere.volumeHoraireAnnuel! / semainesDeCours).toStringAsFixed(1).replaceAll('.0', '')} h/sem. au programme';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(matiere.nom, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                if (matiere.coefficient != null)
                  Chip(label: Text('coef. ${formaterCoefficient(matiere.coefficient!)}'), visualDensity: VisualDensity.compact),
              ],
            ),
            if (officiel != null) Text(officiel, style: TextStyle(color: schema.onSurfaceVariant, fontSize: 12)),
            for (final a in cours)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(a.nomEnseignant ?? 'Enseignant'),
                subtitle: Text([
                  '${a.heuresParSemaine ?? 0} h/sem.',
                  'séances de ${a.dureeSeance >= 60 ? '${a.dureeSeance ~/ 60} h${a.dureeSeance % 60 == 0 ? '' : ' ${a.dureeSeance % 60}'}' : '${a.dureeSeance} min'}',
                  if (a.groupeId != null) nomsGroupes[a.groupeId] ?? 'groupe',
                ].join(' · ')),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => onAttribuer(a),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onAttribuer(null),
                icon: Icon(cours.isEmpty ? Icons.person_add_alt_1_outlined : Icons.add, size: 18),
                label: Text(cours.isEmpty ? 'Attribuer' : 'Ajouter (autre groupe)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormulaireCours extends ConsumerStatefulWidget {
  const _FormulaireCours({
    required this.etablissement,
    required this.anneeId,
    required this.classe,
    required this.matiere,
    required this.existant,
    required this.groupes,
  });

  final Etablissement etablissement;
  final String anneeId;
  final Classe classe;
  final ProgrammeMatiere? matiere;
  final AffectationCours? existant;
  final List<GroupePedagogique> groupes;

  @override
  ConsumerState<_FormulaireCours> createState() => _FormulaireCoursState();
}

class _FormulaireCoursState extends ConsumerState<_FormulaireCours> {
  late String? _enseignantId = widget.existant?.enseignantId;
  late String? _groupeId = widget.existant?.groupeId;
  late String? _salleId = widget.existant?.salleId;
  late int _heures = widget.existant?.heuresParSemaine ?? _heuresProgramme();
  late int _duree = widget.existant?.dureeSeance ?? 60;
  late String? _alternance = widget.existant?.alternance;
  bool _enCours = false;

  int _heuresProgramme() {
    final annuel = widget.matiere?.volumeHoraireAnnuel;
    if (annuel == null) return 2;
    return (annuel / semainesDeCours).round().clamp(1, 12);
  }

  Future<void> _valider() async {
    if (_enseignantId == null) {
      signaler(context, 'Choisissez l’enseignant.');
      return;
    }
    final e = widget.existant;
    final a = AffectationCours(
      id: e?.id ?? const Uuid().v4(),
      etablissementId: widget.etablissement.id,
      anneeScolaireId: widget.anneeId,
      enseignantId: _enseignantId!,
      classeId: widget.classe.id,
      matiereId: widget.matiere?.id ?? e?.matiereId,
      groupeId: _groupeId,
      heuresParSemaine: _heures,
      dureeSeance: _duree,
      salleId: _salleId,
      alternance: _alternance,
    );
    setState(() => _enCours = true);
    final ok = await executer(context, () => ref.read(configurationRepositoryProvider).enregistrerAffectation(a),
        succes: 'Cours enregistré.');
    if (!mounted) return;
    setState(() => _enCours = false);
    if (ok) Navigator.of(context).pop(true);
  }

  Future<void> _retirer() async {
    final ok = await executer(context, () => ref.read(configurationRepositoryProvider).retirerAffectation(widget.existant!.id),
        succes: 'Cours retiré.');
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final personnel = ref.watch(personnelProvider(widget.etablissement.id));
    final enseignants = (personnel.valueOrNull ?? const <MembrePersonnel>[]).where((p) => p.peutEnseigner).toList()
      ..sort((a, b) => a.nomComplet.compareTo(b.nomComplet));
    // Enseignants rattachés mais pas encore actifs : visibles, grisés, pour
    // qu'on sache pourquoi on ne peut pas encore les choisir.
    final enAttente = (personnel.valueOrNull ?? const <MembrePersonnel>[])
        .where((p) => !p.actif && p.role == 'enseignant')
        .toList();
    final salles = ref.watch(sallesEtablissementProvider(widget.etablissement.id)).valueOrNull ?? const <Salle>[];
    final bas = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bas),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.matiere?.nom ?? widget.existant?.nomMatiere ?? 'Cours'} — ${widget.classe.nom}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (personnel.isLoading && enseignants.isEmpty) const LinearProgressIndicator(),
            if (!personnel.isLoading && enseignants.isEmpty)
              const Explication(
                'Aucun enseignant dans l’école : invitez d’abord vos enseignants (étape « Personnel »).',
                icone: Icons.warning_amber_rounded,
              ),
            DropdownButtonFormField<String?>(
              key: const Key('choix_enseignant'),
              initialValue: enseignants.any((e) => e.profileId == _enseignantId) ? _enseignantId : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Enseignant',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  key: const Key('actualiser_enseignants'),
                  tooltip: 'Actualiser la liste',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(personnelProvider(widget.etablissement.id)),
                ),
              ),
              items: [
                for (final e in enseignants) DropdownMenuItem<String?>(value: e.profileId, child: Text(e.nomComplet)),
                for (final e in enAttente)
                  DropdownMenuItem<String?>(
                    value: 'attente_${e.profileId}',
                    enabled: false,
                    child: Text('${e.nomComplet} (compte inactif)'),
                  ),
              ],
              onChanged: (v) => setState(() => _enseignantId = v),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Un enseignant manque ? Il doit avoir accepté son invitation ; touchez ↻ pour actualiser.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Text('Heures par semaine', style: TextStyle(fontWeight: FontWeight.w600))),
                IconButton(
                  onPressed: _heures > 1 ? () => setState(() => _heures--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_heures h', style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  onPressed: _heures < 20 ? () => setState(() => _heures++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Semaines A et B (REG-41) : travaux pratiques, demi-groupes.
            const Text('Fréquence', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              key: const Key('choix_alternance'),
              segments: const [
                ButtonSegment(value: '', label: Text('Chaque semaine')),
                ButtonSegment(value: 'A', label: Text('Semaine A')),
                ButtonSegment(value: 'B', label: Text('Semaine B')),
              ],
              selected: {_alternance ?? ''},
              onSelectionChanged: (v) => setState(() => _alternance = v.first.isEmpty ? null : v.first),
            ),
            const SizedBox(height: 12),
            const Text('Durée d’une séance', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 60, label: Text('1 h')),
                ButtonSegment(value: 90, label: Text('1 h 30')),
                ButtonSegment(value: 120, label: Text('2 h')),
              ],
              selected: {_duree},
              onSelectionChanged: (s) => setState(() => _duree = s.first),
            ),
            if (widget.groupes.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _groupeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Pour', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Toute la classe')),
                  for (final g in widget.groupes) DropdownMenuItem<String?>(value: g.id, child: Text(g.nom)),
                ],
                onChanged: (v) => setState(() => _groupeId = v),
              ),
            ],
            if (salles.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: salles.any((s) => s.id == _salleId) ? _salleId : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Salle imposée (laboratoire, salle info…)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Salle de la classe')),
                  for (final s in salles) DropdownMenuItem<String?>(value: s.id, child: Text(s.libelle)),
                ],
                onChanged: (v) => setState(() => _salleId = v),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('valider_cours'),
              onPressed: _enCours ? null : _valider,
              icon: _enCours
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
            if (widget.existant != null)
              TextButton.icon(
                onPressed: _enCours ? null : _retirer,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Retirer ce cours'),
              ),
          ],
        ),
      ),
    );
  }
}
