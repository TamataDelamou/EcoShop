import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/concours_providers.dart';
import '../data/concours_repository.dart';
import '../domain/concours.dart';

String _date(DateTime d) {
  final l = d.toLocal();
  String z(int n) => n.toString().padLeft(2, '0');
  return '${z(l.day)}/${z(l.month)}/${l.year} ${z(l.hour)}h${z(l.minute)}';
}

const _libellesStatut = {'brouillon': 'Brouillon', 'ouvert': 'Ouvert', 'termine': 'Terminé', 'annule': 'Annulé'};

Future<DateTime?> _choisirDateHeure(BuildContext context, DateTime initiale) async {
  final j = await showDatePicker(
    context: context,
    initialDate: initiale,
    firstDate: DateTime.now().subtract(const Duration(days: 1)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
  );
  if (j == null || !context.mounted) return null;
  final h = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initiale));
  if (h == null) return null;
  return DateTime(j.year, j.month, j.day, h.hour, h.minute);
}

void _signaler(BuildContext context, Object e) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e is ErreurConcours ? e.message : ConcoursRepository.traduire(e).message)),
    );

/// Concours organisés : par la direction (concours de l'école) ou par GSG
/// ([etablissementId] nul : inter-écoles, olympiades, sur un pays ou
/// international). REG-38 lot E2a.
class EcranConcoursOrganises extends ConsumerWidget {
  const EcranConcoursOrganises({super.key, this.etablissementId});

  final String? etablissementId;

  bool get _plateforme => etablissementId == null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(concoursOrganisesProvider(etablissementId));
    return Scaffold(
      appBar: AppBar(title: Text(_plateforme ? 'Concours et olympiades GSG' : 'Concours de l’école')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('concours_nouveau'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EcranFicheConcours(etablissementId: etablissementId),
        )),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau concours'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(concoursOrganisesProvider(etablissementId)),
        child: liste.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(ConcoursRepository.traduire(e).message, textAlign: TextAlign.center),
          ]),
          data: (l) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            Text(
              _plateforme
                  ? 'Questions tirées de la banque publiée, 3 à 4 variantes par question contre la triche, '
                      'correction par le serveur, certificats vérifiables sans compte.'
                  : 'Un concours de l’école ouvert à vos élèves, corrigé automatiquement. '
                      'Il ne compte jamais dans les notes.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (l.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Aucun concours pour le moment.')),
            for (final c in l)
              Card(
                child: ListTile(
                  key: ValueKey('organise_${c['id']}'),
                  title: Text('${c['titre']}'),
                  subtitle: Text([
                    TypeConcours.depuisCode(c['type'] as String?).libelle,
                    _libellesStatut[c['statut']] ?? '${c['statut']}',
                    if (_plateforme) c['pays_code'] == null ? 'International' : '${c['pays_code']}',
                    '${((c['manches_concours'] as List?) ?? const []).length} manche(s)',
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => EcranConcoursOrganise(etablissementId: etablissementId, concoursId: c['id'] as String),
                  )),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Création ou modification d'un concours (tant qu'il est en brouillon).
class EcranFicheConcours extends ConsumerStatefulWidget {
  const EcranFicheConcours({super.key, this.etablissementId, this.existant});

  final String? etablissementId;
  final Map<String, dynamic>? existant;

  @override
  ConsumerState<EcranFicheConcours> createState() => _EcranFicheConcoursState();
}

class _EcranFicheConcoursState extends ConsumerState<EcranFicheConcours> {
  Map<String, dynamic> get _x => widget.existant ?? const {};
  late final _titre = TextEditingController(text: '${_x['titre'] ?? ''}');
  late final _description = TextEditingController(text: '${_x['description'] ?? ''}');
  late final _recompenses = TextEditingController(text: '${_x['recompenses'] ?? ''}');
  late final _pays = TextEditingController(text: '${_x['pays_code'] ?? ''}');
  late TypeConcours _type = widget.etablissementId != null
      ? TypeConcours.concoursInterne
      : TypeConcours.depuisCode(_x['type'] as String? ?? TypeConcours.olympiade.code);
  late int _gradeMin = (_x['grade_min'] as num?)?.toInt() ?? 1;
  late int _gradeMax = (_x['grade_max'] as num?)?.toInt() ?? 13;
  late int _seuil = (_x['seuil_certificat'] as num?)?.toInt() ?? 50;
  late DateTime? _limite = _x['inscription_jusquau'] == null ? null : DateTime.tryParse('${_x['inscription_jusquau']}');
  bool _envoi = false;

  @override
  void dispose() {
    for (final c in [_titre, _description, _recompenses, _pays]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _enregistrer() async {
    setState(() => _envoi = true);
    final id = (_x['id'] as String?) ?? const Uuid().v4();
    String? vide(String s) => s.trim().isEmpty ? null : s.trim();
    try {
      await ref.read(concoursRepositoryProvider).enregistrerConcours(
            id: id,
            titre: _titre.text.trim(),
            type: _type,
            etablissementId: widget.etablissementId,
            paysCode: widget.etablissementId != null ? null : vide(_pays.text.toUpperCase()),
            gradeMin: _gradeMin,
            gradeMax: _gradeMax,
            description: vide(_description.text),
            recompenses: vide(_recompenses.text),
            inscriptionJusquau: _limite,
            seuilCertificat: _seuil,
          );
      ref.invalidate(concoursOrganisesProvider(widget.etablissementId));
      if (!mounted) return;
      if (widget.existant == null) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => EcranConcoursOrganise(etablissementId: widget.etablissementId, concoursId: id),
        ));
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) _signaler(context, e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plateforme = widget.etablissementId == null;
    final grades = [for (var g = 1; g <= 13; g++) DropdownMenuItem(value: g, child: Text('$g'))];
    return Scaffold(
      appBar: AppBar(title: Text(widget.existant == null ? 'Nouveau concours' : 'Modifier le concours')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(key: const Key('fiche_concours_titre'), controller: _titre, decoration: const InputDecoration(labelText: 'Titre')),
        const SizedBox(height: 12),
        if (plateforme) ...[
          DropdownButtonFormField<TypeConcours>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final t in TypeConcours.values)
                if (t != TypeConcours.concoursInterne) DropdownMenuItem(value: t, child: Text(t.libelle)),
            ],
            onChanged: (t) => setState(() => _type = t ?? _type),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('fiche_concours_pays'),
            controller: _pays,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Pays (code : GN, SN, CI…)',
              helperText: 'Vide : ouvert à tous les pays (international)',
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _gradeMin,
              decoration: const InputDecoration(labelText: 'Du niveau', helperText: '1 = CP1 … 13 = Terminale'),
              items: grades,
              onChanged: (g) => setState(() => _gradeMin = g ?? _gradeMin),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _gradeMax,
              decoration: const InputDecoration(labelText: 'Au niveau'),
              items: grades,
              onChanged: (g) => setState(() => _gradeMax = g ?? _gradeMax),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Présentation')),
        const SizedBox(height: 12),
        TextField(controller: _recompenses, maxLines: 2, decoration: const InputDecoration(labelText: 'Récompenses (facultatif)')),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Fin des inscriptions'),
          subtitle: Text(_limite == null ? 'Jusqu’à la fermeture du concours' : _date(_limite!)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_limite != null) IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _limite = null)),
            IconButton(
              icon: const Icon(Icons.event),
              onPressed: () async {
                final d = await _choisirDateHeure(context, _limite ?? DateTime.now().add(const Duration(days: 7)));
                if (d != null) setState(() => _limite = d);
              },
            ),
          ]),
        ),
        Text('Certificat à partir de $_seuil % de réussite'),
        Slider(
          value: _seuil.toDouble(),
          max: 100,
          divisions: 20,
          label: '$_seuil %',
          onChanged: (v) => setState(() => _seuil = v.round()),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('fiche_concours_enregistrer'),
          onPressed: _envoi ? null : _enregistrer,
          child: const Text('Enregistrer'),
        ),
      ]),
    );
  }
}

/// Un concours côté organisateur : manches, ouverture, classement, copies à
/// vérifier, certificats.
class EcranConcoursOrganise extends ConsumerWidget {
  const EcranConcoursOrganise({super.key, this.etablissementId, required this.concoursId});

  final String? etablissementId;
  final String concoursId;

  Future<void> _statut(BuildContext context, WidgetRef ref, String statut, String question) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(question),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Annuler')),
          FilledButton(key: const Key('concours_statut_confirmer'), onPressed: () => Navigator.of(d).pop(true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(concoursRepositoryProvider).changerStatut(concoursId, statut);
      ref.invalidate(concoursOrganisesProvider(etablissementId));
    } catch (e) {
      if (context.mounted) _signaler(context, e);
    }
  }

  Future<void> _certificats(BuildContext context, WidgetRef ref) async {
    try {
      final n = await ref.read(concoursRepositoryProvider).delivrerCertificats(concoursId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n certificat${n > 1 ? 's' : ''} délivré${n > 1 ? 's' : ''}.')));
      }
    } catch (e) {
      if (context.mounted) _signaler(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(concoursOrganisesProvider(etablissementId)).valueOrNull;
    final c = liste?.where((x) => x['id'] == concoursId).firstOrNull;
    if (c == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final statut = '${c['statut']}';
    final brouillon = statut == 'brouillon';
    final manches = [
      for (final m in (c['manches_concours'] as List?) ?? const []) (m as Map).cast<String, dynamic>(),
    ]..sort((a, b) => ((a['ordre'] as num?) ?? 0).compareTo((b['ordre'] as num?) ?? 0));
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('${c['titre']}'),
        actions: [
          if (brouillon)
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => EcranFicheConcours(etablissementId: etablissementId, existant: c),
              )),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text('${_libellesStatut[statut] ?? statut} · niveaux ${c['grade_min']} à ${c['grade_max']}'
            ' · certificat dès ${c['seuil_certificat']} %'),
        const SizedBox(height: 12),
        Text('Manches', style: Theme.of(context).textTheme.titleSmall),
        for (final m in manches)
          Card(
            child: ListTile(
              key: ValueKey('organise_manche_${m['id']}'),
              title: Text('${m['ordre']}. ${m['titre']} · ${m['duree_min']} min'),
              subtitle: Text('Du ${_date(DateTime.parse('${m['ouverture']}'))} au ${_date(DateTime.parse('${m['fermeture']}'))}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => EcranEditeurManche(etablissementId: etablissementId, concoursId: concoursId, existante: m),
              )),
            ),
          ),
        if (statut != 'termine' && statut != 'annule')
          OutlinedButton.icon(
            key: const Key('concours_ajouter_manche'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => EcranEditeurManche(etablissementId: etablissementId, concoursId: concoursId, ordre: manches.length + 1),
            )),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter une manche'),
          ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (brouillon)
            FilledButton.icon(
              key: const Key('concours_ouvrir'),
              onPressed: () => _statut(context, ref, 'ouvert', 'Ouvrir le concours ? Les élèves concernés le verront et pourront s’inscrire.'),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Ouvrir'),
            ),
          if (statut == 'ouvert')
            FilledButton.icon(
              key: const Key('concours_terminer'),
              onPressed: () => _statut(context, ref, 'termine', 'Terminer le concours ? Le classement devient définitif.'),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Terminer'),
            ),
          if (statut == 'termine')
            FilledButton.icon(
              key: const Key('concours_certificats'),
              onPressed: () => _certificats(context, ref),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('Délivrer les certificats'),
            ),
          if (statut != 'brouillon')
            OutlinedButton.icon(
              key: const Key('concours_classement_organisateur'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => EcranClassementOrganisateur(concoursId: concoursId, titre: '${c['titre']}'),
              )),
              icon: const Icon(Icons.leaderboard_outlined),
              label: const Text('Classement et vérifications'),
            ),
          if (statut == 'brouillon' || statut == 'ouvert')
            TextButton(
              onPressed: () => _statut(context, ref, 'annule', 'Annuler ce concours ?'),
              style: TextButton.styleFrom(foregroundColor: schema.error),
              child: const Text('Annuler le concours'),
            ),
        ]),
      ]),
    );
  }
}

/// Composition d'une manche : fenêtre, durée et questions de la banque,
/// regroupées en variantes équivalentes (tirage différent par élève).
class EcranEditeurManche extends ConsumerStatefulWidget {
  const EcranEditeurManche({super.key, this.etablissementId, required this.concoursId, this.existante, this.ordre = 1});

  final String? etablissementId;
  final String concoursId;
  final Map<String, dynamic>? existante;
  final int ordre;

  @override
  ConsumerState<EcranEditeurManche> createState() => _EcranEditeurMancheState();
}

class _EcranEditeurMancheState extends ConsumerState<EcranEditeurManche> {
  Map<String, dynamic> get _x => widget.existante ?? const {};
  late final _titre = TextEditingController(text: '${_x['titre'] ?? 'Manche ${widget.ordre}'}');
  late DateTime _ouverture = _x['ouverture'] == null
      ? DateTime.now().add(const Duration(days: 1))
      : DateTime.parse('${_x['ouverture']}').toLocal();
  late DateTime _fermeture =
      _x['fermeture'] == null ? _ouverture.add(const Duration(days: 2)) : DateTime.parse('${_x['fermeture']}').toLocal();
  late int _duree = (_x['duree_min'] as num?)?.toInt() ?? 30;
  int _variantes = 3;
  final List<String> _choisies = [];
  String? _filtre;
  bool _envoi = false;

  @override
  void dispose() {
    _titre.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    setState(() => _envoi = true);
    try {
      await ref.read(concoursRepositoryProvider).enregistrerManche(
            id: (_x['id'] as String?) ?? const Uuid().v4(),
            concoursId: widget.concoursId,
            ordre: (_x['ordre'] as num?)?.toInt() ?? widget.ordre,
            titre: _titre.text.trim(),
            ouverture: _ouverture,
            fermeture: _fermeture,
            dureeMin: _duree,
            questions: emplacementsDepuis(_choisies, variantes: _variantes),
          );
      ref.invalidate(concoursOrganisesProvider(widget.etablissementId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _signaler(context, e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final proposees = ref.watch(questionsProposeesProvider(widget.concoursId));
    final emplacements = (_choisies.length / _variantes).ceil();
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.existante == null ? 'Nouvelle manche' : 'Modifier la manche')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            key: const Key('manche_enregistrer'),
            onPressed: _envoi || _choisies.isEmpty ? null : _enregistrer,
            child: Text('Enregistrer · $emplacements question${emplacements > 1 ? 's' : ''} par élève'),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _titre, decoration: const InputDecoration(labelText: 'Titre de la manche')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ouverture'),
          subtitle: Text(_date(_ouverture)),
          trailing: const Icon(Icons.event),
          onTap: () async {
            final d = await _choisirDateHeure(context, _ouverture);
            if (d != null) setState(() => _ouverture = d);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Fermeture'),
          subtitle: Text(_date(_fermeture)),
          trailing: const Icon(Icons.event),
          onTap: () async {
            final d = await _choisirDateHeure(context, _fermeture);
            if (d != null) setState(() => _fermeture = d);
          },
        ),
        Text('Durée pour chaque élève : $_duree min'),
        Slider(value: _duree.toDouble(), min: 5, max: 240, divisions: 47, label: '$_duree min',
            onChanged: (v) => setState(() => _duree = v.round())),
        const SizedBox(height: 8),
        Text('Variantes par question', style: Theme.of(context).textTheme.titleSmall),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1')),
            ButtonSegment(value: 2, label: Text('2')),
            ButtonSegment(value: 3, label: Text('3')),
            ButtonSegment(value: 4, label: Text('4')),
          ],
          selected: {_variantes},
          onSelectionChanged: (s) => setState(() => _variantes = s.first),
        ),
        if (widget.existante != null)
          Text('Pour protéger le sujet, il n’est jamais réaffiché : cochez à nouveau les questions de la manche.',
              style: TextStyle(color: schema.tertiary)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Cochez les questions dans l’ordre : chaque groupe de $_variantes question(s) équivalente(s) '
            '(même difficulté, même compétence) forme une question du sujet ; chaque élève en reçoit une au hasard. '
            'Trois ou quatre variantes rendent inutile un sujet qui circule.',
            style: TextStyle(color: schema.onSurfaceVariant),
          ),
        ),
        proposees.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(ConcoursRepository.traduire(e).message),
          data: (l) {
            final groupes = {for (final q in l) q.groupe};
            final visibles = [for (final q in l) if (_filtre == null || q.groupe == _filtre) q];
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (l.isEmpty)
                const Text('Aucune question publiée pour ces niveaux : l’administrateur de contenu doit d’abord en publier.'),
              if (groupes.length > 1)
                DropdownButton<String?>(
                  isExpanded: true,
                  value: _filtre,
                  hint: const Text('Toutes les matières'),
                  items: [
                    const DropdownMenuItem<String?>(child: Text('Toutes les matières')),
                    for (final g in groupes) DropdownMenuItem<String?>(value: g, child: Text(g)),
                  ],
                  onChanged: (g) => setState(() => _filtre = g),
                ),
              for (final q in visibles)
                CheckboxListTile(
                  key: ValueKey('proposee_${q.id}'),
                  value: _choisies.contains(q.id),
                  title: Text(q.enonce, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    if (_filtre == null) q.groupe,
                    q.difficulte,
                    if (_choisies.indexOf(q.id) case final i when i >= 0) 'Question ${i ~/ _variantes + 1}',
                  ].join(' · ')),
                  onChanged: (v) => setState(() => v == true ? _choisies.add(q.id) : _choisies.remove(q.id)),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

/// Classement complet pour l'organisateur, avec les copies écartées à
/// vérifier (temps anormal, cahier 23.4) et leur réhabilitation.
class EcranClassementOrganisateur extends ConsumerWidget {
  const EcranClassementOrganisateur({super.key, required this.concoursId, required this.titre});

  final String concoursId;
  final String titre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cle = (concours: concoursId, fiche: null, pays: null, etablissement: null);
    final classement = ref.watch(classementConcoursProvider(cle));
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: classement.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(ConcoursRepository.traduire(e).message)),
        data: (c) => ListView(padding: const EdgeInsets.all(16), children: [
          Text('${c.participants} au classement · ${c.enVerification ?? 0} copie(s) à vérifier'),
          if (c.aVerifier.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('À vérifier', style: Theme.of(context).textTheme.titleSmall),
            for (final a in c.aVerifier)
              Card(
                child: ListTile(
                  key: ValueKey('a_verifier_${a.ficheId}'),
                  title: Text(a.nom),
                  subtitle: Text('Score ${a.score} en ${a.dureeS} s : temps anormalement court'),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        await ref.read(concoursRepositoryProvider).rehabiliter(concoursId, a.ficheId);
                        ref.invalidate(classementConcoursProvider(cle));
                      } catch (e) {
                        if (context.mounted) _signaler(context, e);
                      }
                    },
                    child: const Text('Réhabiliter'),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          for (final l in c.lignes)
            ListTile(
              leading: CircleAvatar(child: Text('${l.rang}')),
              title: Text(l.nom),
              subtitle: Text([if (l.ecole != null) l.ecole!, if (l.pays != null) l.pays!].join(' · ')),
              trailing: Text('${l.score}'),
            ),
        ]),
      ),
    );
  }
}
