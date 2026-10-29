import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/barre_actions.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../application/transport_providers.dart';
import '../domain/transport.dart';

String _montant(double m, String devise) => '${NumberFormat.decimalPattern('fr').format(m)} $devise';
String _message(Object e) => e is ErreurTransport ? e.messageUtilisateur : 'Opération impossible pour le moment.';

/// Transport scolaire côté direction (cahier 24.1, 24.2, 24.4) : circuits
/// (véhicule, capacité, chauffeur, tarif), arrêts ordonnés et localisés,
/// élèves affectés, paiements du transport, état du trajet du jour.
class EcranTransportDirection extends ConsumerWidget {
  const EcranTransportDirection({super.key, required this.etablissementId, required this.devise});

  final String etablissementId;
  final String devise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circuits = ref.watch(circuitsTransportProvider(etablissementId));
    return Scaffold(
      appBar: AppBar(title: const Text('Transport scolaire')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bouton_nouveau_circuit'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _FormulaireCircuit(etablissementId: etablissementId),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau circuit'),
      ),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(circuitsTransportProvider(etablissementId)),
              child: circuits.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_message(e)))]),
                data: (liste) => liste.isEmpty
                    ? ListView(children: const [
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Aucun circuit.\nCréez un circuit, ajoutez ses arrêts, puis affectez les élèves. '
                            'Les familles suivront le bus et seront prévenues à la montée, à la descente et à l’approche de leur arrêt.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ])
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        children: [
                          for (final c in liste)
                            _CarteCircuitDirection(circuit: c, etablissementId: etablissementId, devise: devise),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteCircuitDirection extends StatelessWidget {
  const _CarteCircuitDirection({required this.circuit, required this.etablissementId, required this.devise});

  final CircuitTransport circuit;
  final String etablissementId;
  final String devise;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final paye = circuit.eleves.fold<double>(0, (s, e) => s + (e.montantPaye ?? 0));
    final du = circuit.eleves.fold<double>(0, (s, e) => s + (e.montantDu ?? 0));
    final enCours = circuit.trajetEnCours;
    final dernier = circuit.dernierTrajet;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _EcranCircuit(circuitId: circuit.id, etablissementId: etablissementId, devise: devise),
        )),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.directions_bus_outlined, color: circuit.actif ? palette.primaire : palette.encreSecondaire),
                  const SizedBox(width: 8),
                  Expanded(child: Text(circuit.nom, style: Theme.of(context).textTheme.titleMedium)),
                  if (!circuit.actif) const Chip(label: Text('Inactif')),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (circuit.vehicule != null) circuit.vehicule!,
                  '${circuit.eleves.length}${circuit.capacite == null ? '' : '/${circuit.capacite}'} élèves',
                  '${circuit.arrets.length} arrêts',
                  circuit.chauffeur ?? 'Chauffeur non désigné',
                ].join(' · '),
                style: TextStyle(color: palette.encreSecondaire),
              ),
              if (du > 0)
                Text('Transport payé : ${_montant(paye, devise)} sur ${_montant(du, devise)}',
                    style: TextStyle(color: palette.encreSecondaire)),
              if (enCours != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'En route (${enCours.sens == SensTrajet.aller ? 'aller' : 'retour'}) · ${enCours.aBord ?? 0} élève(s) à bord',
                    style: TextStyle(color: palette.succes, fontWeight: FontWeight.w600),
                  ),
                )
              else if (dernier != null && (dernier.restesABord ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Dernier trajet terminé avec ${dernier.restesABord} élève(s) non scanné(s) à la descente',
                    style: TextStyle(color: palette.erreur, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormulaireCircuit extends ConsumerStatefulWidget {
  const _FormulaireCircuit({required this.etablissementId, this.circuit});

  final String etablissementId;
  final CircuitTransport? circuit;

  @override
  ConsumerState<_FormulaireCircuit> createState() => _FormulaireCircuitState();
}

class _FormulaireCircuitState extends ConsumerState<_FormulaireCircuit> {
  late final _nom = TextEditingController(text: widget.circuit?.nom);
  late final _vehicule = TextEditingController(text: widget.circuit?.vehicule);
  late final _capacite = TextEditingController(text: widget.circuit?.capacite?.toString());
  late final _tarif = TextEditingController(text: widget.circuit == null ? '' : widget.circuit!.tarifAnnuel.toStringAsFixed(0));
  late final _chauffeur = TextEditingController(text: widget.circuit?.telephoneChauffeur);
  late bool _actif = widget.circuit?.actif ?? true;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    for (final c in [_nom, _vehicule, _capacite, _tarif, _chauffeur]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (_nom.text.trim().length < 2) {
      setState(() => _erreur = 'Nom du circuit requis.');
      return;
    }
    setState(() => _enCours = true);
    try {
      await ref.read(transportRepositoryProvider).enregistrerCircuit(
            etablissementId: widget.etablissementId,
            id: widget.circuit?.id,
            nom: _nom.text.trim(),
            vehicule: _vehicule.text.trim().isEmpty ? null : _vehicule.text.trim(),
            capacite: int.tryParse(_capacite.text.trim()),
            tarifAnnuel: double.tryParse(_tarif.text.trim()) ?? 0,
            chauffeur: _chauffeur.text.trim().isEmpty ? null : _chauffeur.text.trim(),
            actif: _actif,
          );
      ref.invalidate(circuitsTransportProvider(widget.etablissementId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _erreur = _message(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String l, [String? aide]) =>
        InputDecoration(labelText: l, helperText: aide, border: const OutlineInputBorder());
    return AlertDialog(
      title: Text(widget.circuit == null ? 'Nouveau circuit' : 'Modifier le circuit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nom, decoration: deco('Nom *', 'Ex. Circuit Ratoma')),
            const SizedBox(height: 10),
            TextField(controller: _vehicule, decoration: deco('Véhicule', 'Immatriculation, modèle')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _capacite,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: deco('Places'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _tarif,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: deco('Tarif annuel'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _chauffeur,
              decoration: deco('Chauffeur', 'Téléphone ou courriel de son compte EcoShop'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _actif,
              onChanged: (v) => setState(() => _actif = v),
              title: const Text('Circuit en service'),
            ),
            const Text(
              'Le chauffeur ne voit que ses circuits : arrêts, et nom, classe et carte des élèves transportés.',
              style: TextStyle(fontSize: 12),
            ),
            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erreur!, style: TextStyle(color: context.palette.erreur)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _enCours ? null : () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _enCours ? null : _enregistrer, child: const Text('Enregistrer')),
      ],
    );
  }
}

/// Détail d'un circuit : arrêts (ordre, heures, position) et élèves.
class _EcranCircuit extends ConsumerWidget {
  const _EcranCircuit({required this.circuitId, required this.etablissementId, required this.devise});

  final String circuitId;
  final String etablissementId;
  final String devise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circuit = ref.watch(circuitsTransportProvider(etablissementId)).valueOrNull?.where((c) => c.id == circuitId).firstOrNull;
    if (circuit == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final palette = context.palette;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(circuit.nom),
          // Action visible, avec son libellé, sous le titre (REG-28).
          bottom: BarreActions(
            actions: [
              ActionEcran(
                cle: const Key('circuit_modifier'),
                icone: Icons.edit_outlined,
                libelle: 'Modifier le circuit',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _FormulaireCircuit(etablissementId: etablissementId, circuit: circuit),
                ),
              ),
            ],
            sousBarre: TabBar(tabs: [
              Tab(text: 'Arrêts (${circuit.arrets.length})'),
              Tab(text: 'Élèves (${circuit.eleves.length})'),
            ]),
          ),
        ),
        body: TabBarView(
          children: [
            _EditeurArrets(circuit: circuit, etablissementId: etablissementId),
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton.icon(
                  onPressed: circuit.arrets.isEmpty
                      ? null
                      : () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => _AffectationEleve(circuit: circuit, etablissementId: etablissementId),
                          ),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(circuit.arrets.isEmpty ? 'Ajoutez d’abord les arrêts' : 'Affecter un élève'),
                ),
                const SizedBox(height: 12),
                for (final e in circuit.eleves)
                  Card(
                    child: ListTile(
                      title: Text(e.nomComplet),
                      subtitle: Text([
                        'Arrêt : ${circuit.arret(e.arretId)?.nom ?? '—'}',
                        if ((e.montantDu ?? 0) > 0)
                          (e.resteAPayer ?? 0) <= 0
                              ? 'transport payé'
                              : 'reste ${_montant(e.resteAPayer!, devise)}',
                      ].join(' · ')),
                      trailing: IconButton(
                        tooltip: 'Retirer du circuit',
                        icon: Icon(Icons.person_remove_outlined, color: palette.erreur),
                        onPressed: () async {
                          try {
                            await ref.read(transportRepositoryProvider).retirerAffectation(e.ficheEleveId);
                            ref.invalidate(circuitsTransportProvider(etablissementId));
                          } catch (err) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(err))));
                            }
                          }
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Le transport se paie comme la scolarité (encaissement « transport » au guichet ou Orange Money).',
                  style: TextStyle(color: palette.encreSecondaire, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditeurArrets extends ConsumerStatefulWidget {
  const _EditeurArrets({required this.circuit, required this.etablissementId});

  final CircuitTransport circuit;
  final String etablissementId;

  @override
  ConsumerState<_EditeurArrets> createState() => _EditeurArretsState();
}

class _EditeurArretsState extends ConsumerState<_EditeurArrets> {
  late final List<ArretTransport> _arrets = [...widget.circuit.arrets]..sort((a, b) => a.ordre.compareTo(b.ordre));
  bool _modifie = false;
  bool _enCours = false;

  Future<void> _editer([ArretTransport? arret]) async {
    final resultat = await showDialog<ArretTransport>(
      context: context,
      builder: (_) => _DialogueArret(arret: arret, ordre: arret?.ordre ?? _arrets.length + 1),
    );
    if (resultat == null) return;
    setState(() {
      final i = _arrets.indexWhere((a) => a.id == resultat.id);
      if (i >= 0) {
        _arrets[i] = resultat;
      } else {
        _arrets.add(resultat);
      }
      _modifie = true;
    });
  }

  Future<void> _enregistrer() async {
    setState(() => _enCours = true);
    try {
      await ref.read(transportRepositoryProvider).enregistrerArrets(widget.circuit.id, _arrets);
      ref.invalidate(circuitsTransportProvider(widget.etablissementId));
      if (mounted) {
        setState(() => _modifie = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Arrêts enregistrés.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Ordre de l’aller (le retour suit l’ordre inverse). Glissez pour réordonner. '
            'Enregistrez la position de chaque arrêt sur place : le bus le marquera passé tout seul.',
            style: TextStyle(color: palette.encreSecondaire, fontSize: 13),
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.all(16),
            onReorderItem: (ancien, nouveau) => setState(() {
              final a = _arrets.removeAt(ancien);
              _arrets.insert(nouveau, a);
              _modifie = true;
            }),
            children: [
              for (final (i, a) in _arrets.indexed)
                Card(
                  key: ValueKey(a.id),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(a.nom),
                    subtitle: Text([
                      if (a.heureMatin != null) 'matin ${a.heureMatin}',
                      if (a.heureSoir != null) 'soir ${a.heureSoir}',
                      a.localise ? 'position enregistrée' : 'sans position',
                      if (a.eleves > 0) '${a.eleves} élève(s)',
                    ].join(' · ')),
                    trailing: IconButton(
                      tooltip: 'Retirer',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: a.eleves > 0
                          ? null
                          : () => setState(() {
                                _arrets.removeAt(i);
                                _modifie = true;
                              }),
                    ),
                    onTap: () => _editer(a),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(onPressed: () => _editer(), icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Ajouter un arrêt')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(onPressed: _modifie && !_enCours ? _enregistrer : null, child: const Text('Enregistrer')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DialogueArret extends StatefulWidget {
  const _DialogueArret({required this.ordre, this.arret});

  final ArretTransport? arret;
  final int ordre;

  @override
  State<_DialogueArret> createState() => _DialogueArretState();
}

class _DialogueArretState extends State<_DialogueArret> {
  late final _nom = TextEditingController(text: widget.arret?.nom);
  late final _repere = TextEditingController(text: widget.arret?.repere);
  late final _matin = TextEditingController(text: widget.arret?.heureMatin);
  late final _soir = TextEditingController(text: widget.arret?.heureSoir);
  late double? _latitude = widget.arret?.latitude;
  late double? _longitude = widget.arret?.longitude;
  String? _info;

  @override
  void dispose() {
    for (final c in [_nom, _repere, _matin, _soir]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _ici() async {
    if (!(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      setState(() => _info = 'Position disponible sur téléphone seulement.');
      return;
    }
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _info = 'Position non autorisée.');
        return;
      }
      if (mounted) setState(() => _info = 'Recherche de la position…');
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (mounted) {
        setState(() {
          _latitude = p.latitude;
          _longitude = p.longitude;
          _info = 'Position enregistrée (précision ${p.accuracy.toStringAsFixed(0)} m).';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _info = 'Position indisponible. Réessayez à l’extérieur.');
    }
  }

  static String? _heure(String t) {
    final v = t.trim();
    return RegExp(r'^([01]?\d|2[0-3])[:h]([0-5]\d)$').hasMatch(v) ? v.replaceAll('h', ':').padLeft(5, '0') : null;
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder());
    return AlertDialog(
      title: Text(widget.arret == null ? 'Nouvel arrêt' : 'Arrêt'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nom, decoration: deco('Nom *')),
            const SizedBox(height: 10),
            TextField(controller: _repere, decoration: deco('Repère (ex. devant la pharmacie)')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: TextField(controller: _matin, decoration: deco('Heure matin (07:10)'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _soir, decoration: deco('Heure soir (16:20)'))),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _ici,
              icon: const Icon(Icons.my_location),
              label: Text(_latitude == null ? 'Je suis à l’arrêt : enregistrer la position' : 'Mettre à jour la position'),
            ),
            if (_info != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_info!, style: const TextStyle(fontSize: 12))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (_nom.text.trim().length < 2) return;
            Navigator.of(context).pop(ArretTransport(
              id: widget.arret?.id ?? const Uuid().v4(),
              ordre: widget.ordre,
              nom: _nom.text.trim(),
              repere: _repere.text.trim().isEmpty ? null : _repere.text.trim(),
              latitude: _latitude,
              longitude: _longitude,
              heureMatin: _heure(_matin.text),
              heureSoir: _heure(_soir.text),
              eleves: widget.arret?.eleves ?? 0,
            ));
          },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}

class _AffectationEleve extends ConsumerStatefulWidget {
  const _AffectationEleve({required this.circuit, required this.etablissementId});

  final CircuitTransport circuit;
  final String etablissementId;

  @override
  ConsumerState<_AffectationEleve> createState() => _AffectationEleveState();
}

class _AffectationEleveState extends ConsumerState<_AffectationEleve> {
  final _texte = TextEditingController();
  Timer? _attente;
  List<EleveTransporte> _resultats = const [];
  late String _arretId = widget.circuit.arrets.first.id;
  String? _erreur;

  @override
  void dispose() {
    _attente?.cancel();
    _texte.dispose();
    super.dispose();
  }

  void _chercher(String v) {
    _attente?.cancel();
    _attente = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await ref.read(transportRepositoryProvider).rechercherEleves(widget.etablissementId, v.trim());
        if (mounted) setState(() => _resultats = r);
      } catch (e) {
        if (mounted) setState(() => _erreur = _message(e));
      }
    });
  }

  Future<void> _affecter(EleveTransporte e) async {
    try {
      await ref.read(transportRepositoryProvider).affecter(
            ficheEleveId: e.ficheEleveId,
            circuitId: widget.circuit.id,
            arretId: _arretId,
          );
      ref.invalidate(circuitsTransportProvider(widget.etablissementId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${e.nomComplet} affecté(e) au circuit.')));
      _chercher(_texte.text);
    } catch (err) {
      if (mounted) setState(() => _erreur = _message(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _arretId,
                decoration: const InputDecoration(labelText: 'Arrêt de l’élève', border: OutlineInputBorder()),
                items: [for (final a in widget.circuit.arrets) DropdownMenuItem(value: a.id, child: Text('${a.ordre}. ${a.nom}'))],
                onChanged: (v) => setState(() => _arretId = v ?? _arretId),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _texte,
                autofocus: true,
                onChanged: _chercher,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Nom, prénom ou matricule',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_erreur != null) Text(_erreur!, style: TextStyle(color: context.palette.erreur)),
              Expanded(
                child: ListView(
                  children: [
                    for (final e in _resultats)
                      ListTile(
                        title: Text(e.nomComplet),
                        subtitle: Text([
                          if (e.classe != null) e.classe!,
                          if (e.circuitId == widget.circuit.id) 'déjà sur ce circuit' else if (e.circuitId != null) 'sur un autre circuit',
                        ].join(' · ')),
                        trailing: TextButton(
                          onPressed: () => _affecter(e),
                          child: Text(e.circuitId == null ? 'Affecter' : 'Changer'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
