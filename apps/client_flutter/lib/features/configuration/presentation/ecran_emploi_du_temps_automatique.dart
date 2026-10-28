import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sync/device_id_provider.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../planification/application/planification_providers.dart';
import '../../planification/domain/emploi_du_temps.dart';
import '../../planification/domain/moteur_emploi_du_temps.dart';
import '../../planification/domain/salle.dart';
import '../../planification/presentation/widgets/grille_semaine.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../application/configuration_providers.dart';
import '../domain/configuration.dart';
import 'elements_configuration.dart';

/// Emploi du temps dynamique et automatisé (REG-24).
///
/// 1. **Grille** : jours, heures de cours, récréation, pause de midi,
///    demi-journées libérées.
/// 2. **Règles** : poids des critères de qualité (pas de trous pour les
///    élèves, matières réparties, matières principales le matin…).
/// 3. **Indisponibilités** des enseignants, classes et salles.
/// 4. **Calcul** sur l'appareil, sans réseau : proposition, qualité,
///    séances non placées et pourquoi, aperçu par classe et par enseignant,
///    autre proposition, puis enregistrement (les séances verrouillées sont
///    gardées).
class EcranEmploiDuTempsAutomatique extends ConsumerStatefulWidget {
  const EcranEmploiDuTempsAutomatique({super.key, required this.etablissement, required this.anneeId});

  final Etablissement etablissement;
  final String anneeId;

  @override
  ConsumerState<EcranEmploiDuTempsAutomatique> createState() => _EcranEmploiState();
}

class _EcranEmploiState extends ConsumerState<EcranEmploiDuTempsAutomatique> {
  GrilleHoraire? _grille;
  bool _grilleModifiee = false;

  String get _anneeId => widget.anneeId;

  GrilleHoraire _grilleCourante() {
    final g = _grille;
    if (g != null) return g;
    final lue = ref.read(grilleHoraireProvider(_anneeId)).valueOrNull;
    return lue ?? GrilleHoraire.parDefaut(widget.etablissement.id, _anneeId);
  }

  void _modifierGrille(GrilleHoraire g) => setState(() {
        _grille = g;
        _grilleModifiee = true;
      });

  Future<void> _enregistrerGrille() async {
    final g = _grilleCourante();
    final ok = await executer(context, () => ref.read(configurationRepositoryProvider).enregistrerGrille(g),
        succes: 'Grille horaire enregistrée.');
    if (ok && mounted) {
      setState(() => _grilleModifiee = false);
      rafraichirConfiguration(ref.invalidate, etablissementId: widget.etablissement.id, anneeId: _anneeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lue = ref.watch(grilleHoraireProvider(_anneeId));
    final grille = _grille ?? lue.valueOrNull ?? GrilleHoraire.parDefaut(widget.etablissement.id, _anneeId);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Emploi du temps automatique'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.auto_awesome), text: 'Calcul'),
              Tab(icon: Icon(Icons.view_week_outlined), text: 'Grille'),
              Tab(icon: Icon(Icons.tune), text: 'Règles'),
              Tab(icon: Icon(Icons.event_busy_outlined), text: 'Indisponibilités'),
            ],
          ),
        ),
        bottomNavigationBar: _grilleModifiee
            ? SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  key: const Key('enregistrer_grille'),
                  onPressed: _enregistrerGrille,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Enregistrer la grille et les règles'),
                ),
              )
            : null,
        body: TabBarView(
          children: [
            _OngletCalcul(etablissement: widget.etablissement, anneeId: _anneeId, grille: grille, grilleEnregistree: lue.valueOrNull != null && !_grilleModifiee),
            _OngletGrille(grille: grille, onChanged: _modifierGrille, aDefaut: lue.hasValue && lue.valueOrNull == null && _grille == null),
            _OngletRegles(grille: grille, onChanged: _modifierGrille),
            _OngletIndisponibilites(etablissement: widget.etablissement, anneeId: _anneeId, grille: grille),
          ],
        ),
      ),
    );
  }
}

// =================================================================== calcul

class _OngletCalcul extends ConsumerStatefulWidget {
  const _OngletCalcul({required this.etablissement, required this.anneeId, required this.grille, required this.grilleEnregistree});

  final Etablissement etablissement;
  final String anneeId;
  final GrilleHoraire grille;
  final bool grilleEnregistree;

  @override
  ConsumerState<_OngletCalcul> createState() => _OngletCalculState();
}

class _OngletCalculState extends ConsumerState<_OngletCalcul> with AutomaticKeepAliveClientMixin {
  ResultatEmploi? _resultat;
  bool _enCalcul = false;
  bool _enEnregistrement = false;
  int _graine = 1;
  String _vue = 'classe';
  String? _cible;

  @override
  bool get wantKeepAlive => true;

  EntreesCalcul? _entrees() {
    final classes = ref.read(structureEtablissementProvider(widget.anneeId)).valueOrNull?.classes;
    final affectations = ref.read(affectationsAnneeProvider(widget.anneeId)).valueOrNull;
    if (classes == null || affectations == null) return null;
    return EntreesCalcul(
      grille: widget.grille,
      classes: classes.where((c) => c.actif).toList(),
      affectations: affectations,
      groupes: ref.read(groupesProvider(widget.anneeId)).valueOrNull ?? const [],
      indisponibilites: ref.read(indisponibilitesProvider(widget.anneeId)).valueOrNull ?? const [],
      seancesExistantes: ref.read(seancesAnneeProvider(widget.anneeId)).valueOrNull ?? const [],
    );
  }

  Future<void> _calculer() async {
    final entrees = _entrees();
    if (entrees == null) {
      signaler(context, 'Données pas encore chargées : réessayez dans un instant.');
      return;
    }
    setState(() => _enCalcul = true);
    try {
      final resultat = await calculerEmploiDuTemps(entrees.versDonnees(graine: _graine));
      if (!mounted) return;
      setState(() {
        _resultat = resultat;
        _cible ??= entrees.classes.isEmpty ? null : entrees.classes.first.id;
      });
      // Proposition gardée sur l'appareil (enregistrement possible plus tard).
      try {
        await ref.read(storePropositionProvider).ecrireDocument('proposition_emploi', widget.anneeId, {
          'seances': [for (final s in resultat.seances) s.versJsonServeur()],
          'calculee_le': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    } catch (e) {
      if (mounted) signaler(context, 'Le calcul a échoué : $e');
    } finally {
      if (mounted) setState(() => _enCalcul = false);
    }
  }

  Future<void> _enregistrer() async {
    final r = _resultat;
    if (r == null) return;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publier cet emploi du temps ?'),
        content: Text(
          '${r.seances.length} séances remplaceront l’emploi du temps actuel de l’année '
          '(les séances verrouillées sont gardées). Élèves, parents et enseignants le verront aussitôt.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publier')),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    setState(() => _enEnregistrement = true);
    final device = ref.read(deviceIdProvider).valueOrNull;
    final ok = await executer(
      context,
      () => ref.read(configurationRepositoryProvider).enregistrerEmploiGenere(
            etablissementId: widget.etablissement.id,
            anneeId: widget.anneeId,
            seances: [for (final s in r.seances) s.versJsonServeur()],
            deviceId: device,
          ),
      succes: 'Emploi du temps publié.',
    );
    if (!mounted) return;
    setState(() => _enEnregistrement = false);
    if (ok) {
      setState(() => _resultat = null);
      rafraichirConfiguration(ref.invalidate, etablissementId: widget.etablissement.id, anneeId: widget.anneeId);
      ref.invalidate(emploisDeClasseProvider);
      ref.invalidate(emploisDeEnseignantProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final structure = ref.watch(structureEtablissementProvider(widget.anneeId));
    final affectations = ref.watch(affectationsAnneeProvider(widget.anneeId));
    ref.watch(groupesProvider(widget.anneeId));
    ref.watch(indisponibilitesProvider(widget.anneeId));
    final seances = ref.watch(seancesAnneeProvider(widget.anneeId)).valueOrNull ?? const <EmploiDuTemps>[];
    final classes = (structure.valueOrNull?.classes ?? const <Classe>[]).where((c) => c.actif).toList()
      ..sort((a, b) => a.nom.compareTo(b.nom));
    final entrees = _entrees();
    final donnees = entrees?.versDonnees();
    final alertes = donnees == null ? const <String>[] : MoteurEmploiDuTemps.diagnostiquer(donnees);
    final nbSeances = donnees?.cours.fold<int>(0, (s, c) => s + c.seances().length) ?? 0;
    final heures = donnees?.cours.fold<int>(0, (s, c) => s + c.minutesParSemaine) ?? 0;
    final verrouillees = seances.where((s) => s.verrouille).length;
    final r = _resultat;
    final theme = Theme.of(context);

    if ((structure.isLoading && !structure.hasValue) || (affectations.isLoading && !affectations.hasValue)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (affectations.hasError && affectations.valueOrNull == null) {
      return ErreurChargement(onReessayer: () => ref.invalidate(affectationsAnneeProvider(widget.anneeId)));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('À placer', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _Chiffre(valeur: '${classes.length}', libelle: 'classes'),
                    _Chiffre(valeur: '${donnees?.cours.length ?? 0}', libelle: 'cours'),
                    _Chiffre(valeur: '$nbSeances', libelle: 'séances'),
                    _Chiffre(valeur: '${heures ~/ 60} h', libelle: 'par semaine'),
                    _Chiffre(valeur: '${widget.grille.heuresDeCoursParSemaine} h', libelle: 'de grille / classe'),
                  ],
                ),
                if (!widget.grilleEnregistree) ...[
                  const SizedBox(height: 10),
                  const Text('Grille horaire par défaut (lundi → samedi matin) : vérifiez-la dans l’onglet « Grille ».'),
                ],
                if (verrouillees > 0) ...[
                  const SizedBox(height: 6),
                  Text('$verrouillees séance(s) verrouillée(s) resteront à leur place.'),
                ],
              ],
            ),
          ),
        ),
        if ((donnees?.cours ?? const []).isEmpty)
          const Explication(
            'Aucun cours à placer : renseignez d’abord « Cours et enseignants » (qui enseigne quoi, combien d’heures).',
            icone: Icons.warning_amber_rounded,
          ),
        for (final a in alertes) Explication(a, icone: Icons.warning_amber_rounded),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('bouton_calculer_emploi'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _enCalcul || (donnees?.cours ?? const []).isEmpty ? null : _calculer,
          icon: _enCalcul
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome),
          label: Text(_enCalcul ? 'Calcul en cours (quelques secondes)…' : (r == null ? 'Calculer l’emploi du temps' : 'Recalculer')),
        ),
        if (r != null) ...[
          const SizedBox(height: 16),
          _Bilan(resultat: r),
          if (r.nonPlacees.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Séances non placées', style: theme.textTheme.titleMedium),
            for (final n in r.nonPlacees)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
                title: Text(n.cours.libelle),
                subtitle: Text(n.raison),
              ),
            const Text(
              'Pistes : ajouter un créneau à la grille, alléger une indisponibilité, découper en séances plus courtes, '
              'ou confier une partie des heures à un autre enseignant.',
            ),
          ],
          const SizedBox(height: 16),
          _Apercu(
            resultat: r,
            grille: widget.grille,
            classes: classes,
            vue: _vue,
            cible: _cible,
            fixes: seances.where((s) => s.verrouille).toList(),
            onVue: (v, c) => setState(() {
              _vue = v;
              _cible = c;
            }),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _enCalcul
                      ? null
                      : () {
                          setState(() => _graine++);
                          _calculer();
                        },
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Autre proposition'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('bouton_publier_emploi'),
                  onPressed: _enEnregistrement ? null : _enregistrer,
                  icon: const Icon(Icons.publish),
                  label: const Text('Publier'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        _SeancesEnregistrees(etablissement: widget.etablissement, anneeId: widget.anneeId, grille: widget.grille, classes: classes),
      ],
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.valeur, required this.libelle});

  final String valeur;
  final String libelle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valeur, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(libelle, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _Bilan extends StatelessWidget {
  const _Bilan({required this.resultat});

  final ResultatEmploi resultat;

  @override
  Widget build(BuildContext context) {
    final b = resultat.bilan;
    final theme = Theme.of(context);
    final complet = b.seancesPlacees == b.seancesTotal;
    return Card(
      color: complet ? theme.colorScheme.primaryContainer : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(value: b.qualite / 100, strokeWidth: 6),
                      Text('${b.qualite.round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    complet
                        ? 'Toutes les séances sont placées (${b.seancesTotal}).'
                        : '${b.seancesPlacees} séances placées sur ${b.seancesTotal}.',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('• Trous dans les journées des élèves : ${b.trousEleves}'),
            Text('• Heures creuses des enseignants : ${b.trousEnseignants}'),
            Text('• Même matière deux fois le même jour : ${b.matieresMemeJour}'),
            Text('• Matières principales l’après-midi : ${b.principalesApresMidi}'),
          ],
        ),
      ),
    );
  }
}

class _Apercu extends StatelessWidget {
  const _Apercu({
    required this.resultat,
    required this.grille,
    required this.classes,
    required this.vue,
    required this.cible,
    required this.fixes,
    required this.onVue,
  });

  final ResultatEmploi resultat;
  final GrilleHoraire grille;
  final List<Classe> classes;
  final String vue;
  final String? cible;
  final List<EmploiDuTemps> fixes;
  final void Function(String vue, String? cible) onVue;

  @override
  Widget build(BuildContext context) {
    final enseignants = <String, String>{
      for (final s in resultat.seances)
        if (s.cours.enseignantId != null) s.cours.enseignantId!: s.cours.nomEnseignant ?? 'Enseignant',
    };
    final options = vue == 'classe'
        ? {for (final c in classes) c.id: c.nom}
        : (enseignants.entries.toList()..sort((a, b) => a.value.compareTo(b.value))).fold<Map<String, String>>(
            {}, (m, e) => m..[e.key] = e.value);
    final choisi = options.containsKey(cible) ? cible : (options.isEmpty ? null : options.keys.first);
    final cases = <CaseSemaine>[
      for (final s in resultat.seances)
        if (vue == 'classe' ? s.cours.classeId == choisi : s.cours.enseignantId == choisi)
          CaseSemaine(
            jour: s.jour,
            debut: s.debut,
            fin: s.fin,
            titre: s.cours.nomMatiere ?? 'Cours',
            detail: vue == 'classe'
                ? [s.cours.nomEnseignant, s.cours.nomGroupe].whereType<String>().join(' · ')
                : [s.cours.nomClasse, s.cours.nomGroupe].whereType<String>().join(' · '),
            cleCouleur: s.cours.matiereId ?? s.cours.nomMatiere,
          ),
      for (final f in fixes)
        if (vue == 'classe' ? f.classeId == choisi : f.enseignantProfileId == choisi)
          CaseSemaine(
            jour: f.jourSemaine,
            debut: f.heureDebut,
            fin: f.heureFin,
            titre: f.nomMatiere ?? 'Cours',
            detail: vue == 'classe' ? f.nomEnseignant : f.nomClasse,
            cleCouleur: f.programmeMatiereId ?? f.nomMatiere,
            verrouillee: true,
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Aperçu', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'classe', icon: Icon(Icons.class_outlined), label: Text('Par classe')),
            ButtonSegment(value: 'enseignant', icon: Icon(Icons.person_outline), label: Text('Par enseignant')),
          ],
          selected: {vue},
          onSelectionChanged: (s) => onVue(s.first, null),
        ),
        const SizedBox(height: 8),
        if (options.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey('apercu_$vue'),
            initialValue: choisi,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => onVue(vue, v),
          ),
        const SizedBox(height: 8),
        GrilleSemaine(
          jours: [...grille.jours]..sort(),
          creneaux: [...grille.creneaux]..sort((a, b) => a.debutMinutes.compareTo(b.debutMinutes)),
          cases: cases,
          joursLibres: grille.demiJourneesLibres,
        ),
      ],
    );
  }
}

/// Emploi du temps enregistré : consultation par classe, verrou d'une
/// séance (gardée telle quelle au prochain calcul).
class _SeancesEnregistrees extends ConsumerStatefulWidget {
  const _SeancesEnregistrees({required this.etablissement, required this.anneeId, required this.grille, required this.classes});

  final Etablissement etablissement;
  final String anneeId;
  final GrilleHoraire grille;
  final List<Classe> classes;

  @override
  ConsumerState<_SeancesEnregistrees> createState() => _SeancesEnregistreesState();
}

class _SeancesEnregistreesState extends ConsumerState<_SeancesEnregistrees> {
  String? _classeId;

  @override
  Widget build(BuildContext context) {
    final seances = ref.watch(seancesAnneeProvider(widget.anneeId)).valueOrNull ?? const <EmploiDuTemps>[];
    if (seances.isEmpty || widget.classes.isEmpty) return const SizedBox.shrink();
    final classeId = widget.classes.any((c) => c.id == _classeId) ? _classeId! : widget.classes.first.id;
    final deLaClasse = seances.where((s) => s.classeId == classeId).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Emploi du temps publié (${seances.length} séances)', style: Theme.of(context).textTheme.titleMedium),
        const Text('Touchez une séance pour la verrouiller : elle restera à sa place au prochain calcul.'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: classeId,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: [for (final c in widget.classes) DropdownMenuItem(value: c.id, child: Text(c.nom))],
          onChanged: (v) => setState(() => _classeId = v),
        ),
        const SizedBox(height: 8),
        GrilleSemaine(
          jours: [...widget.grille.jours]..sort(),
          creneaux: [...widget.grille.creneaux]..sort((a, b) => a.debutMinutes.compareTo(b.debutMinutes)),
          joursLibres: widget.grille.demiJourneesLibres,
          cases: [
            for (final s in deLaClasse)
              CaseSemaine(
                jour: s.jourSemaine,
                debut: s.heureDebut,
                fin: s.heureFin,
                titre: s.nomMatiere ?? 'Cours',
                detail: [s.nomEnseignant, s.libelleSalle].whereType<String>().join(' · '),
                cleCouleur: s.programmeMatiereId ?? s.nomMatiere,
                verrouillee: s.verrouille,
                onTap: () async {
                  final ok = await executer(
                    context,
                    () => ref.read(configurationRepositoryProvider).verrouillerSeance(s.id, !s.verrouille),
                    succes: s.verrouille ? 'Séance déverrouillée.' : 'Séance verrouillée.',
                  );
                  if (ok) ref.invalidate(seancesAnneeProvider(widget.anneeId));
                },
              ),
          ],
        ),
      ],
    );
  }
}

// =================================================================== grille

class _OngletGrille extends StatelessWidget {
  const _OngletGrille({required this.grille, required this.onChanged, required this.aDefaut});

  final GrilleHoraire grille;
  final ValueChanged<GrilleHoraire> onChanged;
  final bool aDefaut;

  static String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<String?> _heure(BuildContext context, String actuelle) async {
    final m = minutesDe(actuelle);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      builder: (ctx, enfant) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: enfant!,
      ),
    );
    return t == null ? null : _hhmm(t);
  }

  List<CreneauEmploi> get _tries => [...grille.creneaux]..sort((a, b) => a.debutMinutes.compareTo(b.debutMinutes));

  @override
  Widget build(BuildContext context) {
    final creneaux = _tries;
    final jours = [...grille.jours]..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (aDefaut)
          const Explication('Grille proposée par défaut : modifiez-la puis enregistrez-la.'),
        Text('Jours de cours', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (var j = 1; j <= 7; j++)
              FilterChip(
                label: Text(nomsJoursCourts[j]!),
                selected: jours.contains(j),
                onSelected: (v) => onChanged(grille.copier(jours: v ? [...jours, j] : (jours..remove(j)))),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Demi-journées libérées', style: Theme.of(context).textTheme.titleMedium),
        for (final j in jours)
          Row(
            children: [
              SizedBox(width: 90, child: Text(nomsJours[j]!)),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: grille.demiJourneesLibres[j] ?? 'aucune',
                  items: const [
                    DropdownMenuItem(value: 'aucune', child: Text('Cours toute la journée')),
                    DropdownMenuItem(value: 'matin', child: Text('Matin libre')),
                    DropdownMenuItem(value: 'apres_midi', child: Text('Après-midi libre')),
                    DropdownMenuItem(value: 'journee', child: Text('Journée libre')),
                  ],
                  onChanged: (v) {
                    final libres = {...grille.demiJourneesLibres};
                    if (v == null || v == 'aucune') {
                      libres.remove(j);
                    } else {
                      libres[j] = v;
                    }
                    onChanged(grille.copier(demiJourneesLibres: libres));
                  },
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        Text('Journée-type', style: Theme.of(context).textTheme.titleMedium),
        const Text('Heures de cours, récréation et pause de midi : une séance de 2 h ne coupe jamais une pause.'),
        const SizedBox(height: 8),
        for (var i = 0; i < creneaux.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            color: creneaux[i].cours ? null : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              dense: true,
              leading: Icon(creneaux[i].cours ? Icons.menu_book_outlined : Icons.free_breakfast_outlined),
              title: Text('${creneaux[i].debut} → ${creneaux[i].fin}'),
              subtitle: Text(creneaux[i].cours ? 'Cours (${creneaux[i].minutes} min)' : (creneaux[i].libelle ?? 'Pause')),
              onTap: () async {
                final debut = await _heure(context, creneaux[i].debut);
                if (debut == null || !context.mounted) return;
                final fin = await _heure(context, creneaux[i].fin);
                if (fin == null) return;
                if (minutesDe(fin) <= minutesDe(debut)) {
                  if (context.mounted) signaler(context, 'La fin doit suivre le début.');
                  return;
                }
                final liste = [...creneaux];
                liste[i] = CreneauEmploi(debut: debut, fin: fin, cours: creneaux[i].cours, libelle: creneaux[i].libelle);
                onChanged(grille.copier(creneaux: liste));
              },
              trailing: IconButton(
                tooltip: 'Retirer',
                icon: const Icon(Icons.close),
                onPressed: () => onChanged(grille.copier(creneaux: [...creneaux]..removeAt(i))),
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => onChanged(grille.copier(creneaux: [...creneaux, _suivant(creneaux, 60, true)])),
              icon: const Icon(Icons.add),
              label: const Text('Heure de cours'),
            ),
            OutlinedButton.icon(
              onPressed: () => onChanged(grille.copier(creneaux: [...creneaux, _suivant(creneaux, 15, false)])),
              icon: const Icon(Icons.free_breakfast_outlined),
              label: const Text('Pause'),
            ),
          ],
        ),
      ],
    );
  }

  static CreneauEmploi _suivant(List<CreneauEmploi> creneaux, int minutes, bool cours) {
    final debut = creneaux.isEmpty ? 8 * 60 : creneaux.last.finMinutes;
    return CreneauEmploi(
      debut: hhmmDe(debut),
      fin: hhmmDe(debut + minutes),
      cours: cours,
      libelle: cours ? null : 'Pause',
    );
  }
}

// =================================================================== règles

class _OngletRegles extends StatelessWidget {
  const _OngletRegles({required this.grille, required this.onChanged});

  final GrilleHoraire grille;
  final ValueChanged<GrilleHoraire> onChanged;

  @override
  Widget build(BuildContext context) {
    final r = grille.regles;
    Widget curseur(String titre, String aide, int valeur, ReglesEmploi Function(int v) nouveau) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(titre, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(valeur == 0 ? 'ignoré' : '$valeur / 10'),
                ],
              ),
              Text(aide, style: Theme.of(context).textTheme.bodySmall),
              Slider(
                value: valeur.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                label: '$valeur',
                onChanged: (v) => onChanged(grille.copier(regles: nouveau(v.round()))),
              ),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Explication(
          'Les règles impératives sont toujours respectées (personne n’est à deux endroits à la fois, indisponibilités, '
          'séances verrouillées). Les critères ci-dessous départagent les propositions : plus le poids est fort, plus le calcul y tient.',
        ),
        curseur('Pas de trous pour les élèves', 'Pas d’heure vide entre deux cours d’une classe.', r.trousEleves,
            (v) => r.copier(trousEleves: v)),
        curseur('Peu d’heures creuses pour les enseignants', 'Cours groupés dans la journée de chaque enseignant.',
            r.trousEnseignants, (v) => r.copier(trousEnseignants: v)),
        curseur('Matières réparties sur la semaine', 'Pas deux fois la même matière le même jour, ni deux jours de suite.',
            r.repartition, (v) => r.copier(repartition: v)),
        curseur('Matières principales le matin', 'Mathématiques, français… quand l’attention est meilleure.',
            r.principalesLeMatin, (v) => r.copier(principalesLeMatin: v)),
        curseur('Journées équilibrées', 'Même nombre d’heures chaque jour pour une classe.', r.equilibreJournees,
            (v) => r.copier(equilibreJournees: v)),
        curseur('Enseignants présents moins de jours', 'Regroupe les cours d’un enseignant (vacataires, trajets).',
            r.regrouperEnseignants, (v) => r.copier(regrouperEnseignants: v)),
        curseur('Éviter la dernière heure', 'Dernier créneau de la journée laissé libre quand c’est possible.',
            r.eviterDerniereHeure, (v) => r.copier(eviterDerniereHeure: v)),
        const Divider(height: 32),
        Row(
          children: [
            const Expanded(child: Text('Une matière est « principale » à partir du coefficient')),
            DropdownButton<int>(
              value: r.seuilMatierePrincipale,
              items: [for (var c = 2; c <= 6; c++) DropdownMenuItem(value: c, child: Text('$c'))],
              onChanged: (v) => onChanged(grille.copier(regles: r.copier(seuilMatierePrincipale: v))),
            ),
          ],
        ),
      ],
    );
  }
}

// ========================================================= indisponibilités

class _OngletIndisponibilites extends ConsumerWidget {
  const _OngletIndisponibilites({required this.etablissement, required this.anneeId, required this.grille});

  final Etablissement etablissement;
  final String anneeId;
  final GrilleHoraire grille;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(indisponibilitesProvider(anneeId));
    final personnel = ref.watch(personnelProvider(etablissement.id)).valueOrNull ?? const <MembrePersonnel>[];
    final classes = ref.watch(structureEtablissementProvider(anneeId)).valueOrNull?.classes ?? const <Classe>[];
    final salles = ref.watch(sallesEtablissementProvider(etablissement.id)).valueOrNull ?? const <Salle>[];
    final noms = {
      for (final p in personnel) p.profileId: p.nomComplet,
      for (final c in classes) c.id: c.nom,
      for (final s in salles) s.id: s.libelle,
    };
    final items = liste.valueOrNull ?? const <Indisponibilite>[];
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ajout_indispo',
        onPressed: () => _ajouter(context, ref, personnel, classes, salles),
        icon: const Icon(Icons.add),
        label: const Text('Indisponibilité'),
      ),
      body: liste.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErreurChargement(onReessayer: () => ref.invalidate(indisponibilitesProvider(anneeId))),
        data: (_) => items.isEmpty
            ? const EtatVide(
                icone: Icons.event_busy_outlined,
                titre: 'Aucune indisponibilité',
                texte: 'Un enseignant vacataire libre seulement le mardi ? Une salle réservée le vendredi ? Indiquez-le ici : '
                    'le calcul n’y placera aucun cours.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  for (final i in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(i.enseignantId != null
                            ? Icons.person_off_outlined
                            : i.salleId != null
                                ? Icons.meeting_room_outlined
                                : Icons.class_outlined),
                        title: Text(noms[i.enseignantId ?? i.salleId ?? i.classeId] ?? '—'),
                        subtitle: Text([
                          i.jour == null ? 'Toute la semaine' : nomsJours[i.jour]!,
                          i.debut == null ? 'toute la journée' : '${i.debut} → ${i.fin}',
                          if ((i.raison ?? '').isNotEmpty) i.raison!,
                        ].join(' · ')),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await executer(
                                context, () => ref.read(configurationRepositoryProvider).retirerIndisponibilite(i.id),
                                succes: 'Indisponibilité retirée.');
                            if (ok) ref.invalidate(indisponibilitesProvider(anneeId));
                          },
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _ajouter(
    BuildContext context,
    WidgetRef ref,
    List<MembrePersonnel> personnel,
    List<Classe> classes,
    List<Salle> salles,
  ) async {
    var qui = 'enseignant';
    String? cible;
    int? jour = grille.jours.isEmpty ? null : grille.jours.first;
    var moment = 'journee';
    final raison = TextEditingController();
    final enseignants = personnel.where((p) => p.peutEnseigner).toList();
    final valide = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final options = switch (qui) {
            'enseignant' => {for (final p in enseignants) p.profileId: p.nomComplet},
            'classe' => {for (final c in classes) c.id: c.nom},
            _ => {for (final s in salles) s.id: s.libelle},
          };
          return AlertDialog(
            title: const Text('Indisponibilité'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'enseignant', label: Text('Enseignant')),
                      ButtonSegment(value: 'classe', label: Text('Classe')),
                      ButtonSegment(value: 'salle', label: Text('Salle')),
                    ],
                    selected: {qui},
                    onSelectionChanged: (s) => setState(() {
                      qui = s.first;
                      cible = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('cible_$qui'),
                    initialValue: cible,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Qui'),
                    items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => cible = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: jour,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Jour'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Toute la semaine')),
                      for (final j in [...grille.jours]..sort()) DropdownMenuItem<int?>(value: j, child: Text(nomsJours[j]!)),
                    ],
                    onChanged: (v) => setState(() => jour = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: moment,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Quand'),
                    items: const [
                      DropdownMenuItem(value: 'journee', child: Text('Toute la journée')),
                      DropdownMenuItem(value: 'matin', child: Text('Le matin')),
                      DropdownMenuItem(value: 'apres_midi', child: Text('L’après-midi')),
                    ],
                    onChanged: (v) => setState(() => moment = v ?? moment),
                  ),
                  TextField(controller: raison, decoration: const InputDecoration(labelText: 'Motif (facultatif)')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton(onPressed: cible == null ? null : () => Navigator.pop(ctx, true), child: const Text('Ajouter')),
            ],
          );
        },
      ),
    );
    if (valide != true || cible == null || !context.mounted) return;
    final i = Indisponibilite(
      id: const Uuid().v4(),
      etablissementId: etablissement.id,
      anneeScolaireId: anneeId,
      enseignantId: qui == 'enseignant' ? cible : null,
      classeId: qui == 'classe' ? cible : null,
      salleId: qui == 'salle' ? cible : null,
      jour: jour,
      debut: switch (moment) { 'matin' => '00:00', 'apres_midi' => '12:30', _ => null },
      fin: switch (moment) { 'matin' => '12:30', 'apres_midi' => '23:59', _ => null },
      raison: raison.text.trim().isEmpty ? null : raison.text.trim(),
    );
    final ok = await executer(context, () => ref.read(configurationRepositoryProvider).enregistrerIndisponibilite(i),
        succes: 'Indisponibilité ajoutée.');
    if (ok) ref.invalidate(indisponibilitesProvider(anneeId));
  }
}
