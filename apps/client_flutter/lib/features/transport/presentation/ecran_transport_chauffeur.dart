import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../application/transport_providers.dart';
import '../domain/transport.dart';

/// Espace du chauffeur (cahier 24.3) : ses circuits seulement. Démarrer un
/// trajet, marquer les arrêts (automatiquement à l'approche si le GPS est
/// actif), scanner la carte des élèves à la montée et à la descente,
/// terminer en vérifiant qu'aucun enfant n'est resté à bord. Tout
/// fonctionne sans réseau.
class EcranTransportChauffeur extends ConsumerWidget {
  const EcranTransportChauffeur({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circuits = ref.watch(mesCircuitsChauffeurProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes circuits')),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: circuits.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(e is ErreurTransport ? e.messageUtilisateur : 'Circuits indisponibles.', textAlign: TextAlign.center),
                ),
              ),
              data: (liste) => liste.isEmpty
                  ? const Center(child: Text('Aucun circuit ne vous est confié.'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [for (final c in liste) _CarteCircuit(circuit: c)],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteCircuit extends ConsumerWidget {
  const _CarteCircuit({required this.circuit});

  final CircuitTransport circuit;

  Future<void> _ouvrir(BuildContext context, WidgetRef ref, {SensTrajet? demarrer}) async {
    final depot = ref.read(transportRepositoryProvider);
    var trajet = await depot.trajetLocal(circuit.id);
    if (trajet == null && demarrer != null) trajet = await depot.demarrer(circuit, demarrer);
    if (trajet == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EcranTrajetEnCours(circuit: circuit, trajetInitial: trajet!),
    ));
    ref.invalidate(mesCircuitsChauffeurProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<TrajetLocal?>(
          future: ref.read(transportRepositoryProvider).trajetLocal(circuit.id),
          builder: (context, snap) {
            final enCours = snap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(circuit.nom, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  [
                    if (circuit.etablissement != null) circuit.etablissement!,
                    if (circuit.vehicule != null) circuit.vehicule!,
                    '${circuit.arrets.length} arrêts · ${circuit.eleves.length} élèves',
                  ].join(' · '),
                  style: TextStyle(color: palette.encreSecondaire),
                ),
                const SizedBox(height: 12),
                if (enCours != null)
                  FilledButton.icon(
                    onPressed: () => _ouvrir(context, ref),
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text('Reprendre le trajet (${enCours.sens == SensTrajet.aller ? 'aller' : 'retour'})'),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          key: Key('demarrer_aller_${circuit.id}'),
                          onPressed: () => _ouvrir(context, ref, demarrer: SensTrajet.aller),
                          child: const Text('Démarrer l’aller'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _ouvrir(context, ref, demarrer: SensTrajet.retour),
                          child: const Text('Démarrer le retour'),
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class EcranTrajetEnCours extends ConsumerStatefulWidget {
  const EcranTrajetEnCours({super.key, required this.circuit, required this.trajetInitial});

  final CircuitTransport circuit;
  final TrajetLocal trajetInitial;

  @override
  ConsumerState<EcranTrajetEnCours> createState() => _EcranTrajetEnCoursState();
}

class _EcranTrajetEnCoursState extends ConsumerState<EcranTrajetEnCours> {
  late TrajetLocal _trajet = widget.trajetInitial;
  late EvenementBus _evenement =
      widget.trajetInitial.sens == SensTrajet.aller ? EvenementBus.montee : EvenementBus.descente;
  bool _camera = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  ResultatScanBus? _dernier;
  String? _gps;
  StreamSubscription<Position>? _positions;
  DateTime? _dernierEnvoiPosition;
  DateTime? _dernierScan;
  String? _derniereLecture;
  bool _occupe = false;
  final _saisie = TextEditingController();
  final _focus = FocusNode();
  MobileScannerController? _controleur;

  @override
  void initState() {
    super.initState();
    unawaited(_demarrerGps());
  }

  @override
  void dispose() {
    _positions?.cancel();
    _controleur?.dispose();
    _saisie.dispose();
    _focus.dispose();
    super.dispose();
  }

  // GPS : seulement pendant le trajet, écran ouvert (jamais en continu).
  Future<void> _demarrerGps() async {
    if (!(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _gps = 'GPS désactivé : marquez les arrêts à la main.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gps = 'Position non autorisée : marquez les arrêts à la main.');
        return;
      }
      _positions = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 40),
      ).listen(_surPosition, onError: (Object _) {
        if (mounted) setState(() => _gps = 'Position indisponible : marquez les arrêts à la main.');
      });
      if (mounted) setState(() => _gps = 'Position partagée pendant le trajet seulement.');
    } catch (_) {
      if (mounted) setState(() => _gps = 'Position indisponible : marquez les arrêts à la main.');
    }
  }

  Future<void> _surPosition(Position p) async {
    final depot = ref.read(transportRepositoryProvider);
    final maintenant = DateTime.now();
    if (_dernierEnvoiPosition == null || maintenant.difference(_dernierEnvoiPosition!) > const Duration(seconds: 30)) {
      _dernierEnvoiPosition = maintenant;
      unawaited(depot.signalerPosition(_trajet, p.latitude, p.longitude).catchError((Object _) {}));
    }
    // Arrêt suivant atteint : marqué automatiquement (les familles de l'arrêt
    // d'après sont prévenues).
    final prochain = _trajet.prochainArret(widget.circuit.arrets);
    if (prochain != null && prochain.localise &&
        distanceMetres(p.latitude, p.longitude, prochain.latitude!, prochain.longitude!) < rayonArretMetres) {
      await _passer(prochain);
    }
  }

  Future<void> _passer(ArretTransport arret) async {
    try {
      final t = await ref.read(transportRepositoryProvider).passerArret(_trajet, arret);
      if (mounted) setState(() => _trajet = t);
    } catch (e) {
      _signaler(e is ErreurTransport ? e.messageUtilisateur : 'Arrêt non enregistré.');
    }
  }

  void _signaler(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte), duration: const Duration(seconds: 2)));
  }

  Future<void> _lire(String lecture) async {
    final propre = lecture.trim();
    if (propre.isEmpty || _occupe) return;
    // La caméra lit la même carte plusieurs fois par seconde.
    final maintenant = DateTime.now();
    if (propre == _derniereLecture && _dernierScan != null && maintenant.difference(_dernierScan!) < const Duration(seconds: 4)) {
      return;
    }
    _derniereLecture = propre;
    _dernierScan = maintenant;
    _occupe = true;
    try {
      final (resultat, trajet) = await ref.read(transportRepositoryProvider).scanner(
            trajet: _trajet,
            circuit: widget.circuit,
            lecture: propre,
            evenement: _evenement,
          );
      if (mounted) {
        setState(() {
          _trajet = trajet;
          _dernier = resultat;
        });
      }
    } catch (e) {
      _signaler(e is ErreurTransport ? e.messageUtilisateur : 'Scan non enregistré.');
    } finally {
      _occupe = false;
      _saisie.clear();
      if (!_camera) _focus.requestFocus();
    }
  }

  Future<void> _terminer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Terminer le trajet ?'),
        content: Text('${_trajet.aBord.length} élève(s) encore enregistré(s) à bord.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Continuer')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Terminer')),
        ],
      ),
    );
    if (ok != true) return;
    final restes = await ref.read(transportRepositoryProvider).terminer(_trajet, widget.circuit);
    await _positions?.cancel();
    if (!mounted) return;
    if (restes.isNotEmpty) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: c.palette.erreur, size: 40),
          title: const Text('Vérifiez le véhicule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ces élèves n’ont pas été scannés à la descente :'),
              const SizedBox(height: 8),
              for (final e in restes) Text('• ${e.nomComplet.trim()}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('La direction est prévenue. Vérifiez qu’aucun enfant n’est resté dans le véhicule.'),
            ],
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Véhicule vérifié'))],
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final arrets = _trajet.arretsDansLOrdre(widget.circuit.arrets);
    final prochain = _trajet.prochainArret(widget.circuit.arrets);
    final aBord = [for (final id in _trajet.aBord) widget.circuit.eleves.where((e) => e.ficheEleveId == id).firstOrNull];

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.circuit.nom} — ${_trajet.sens == SensTrajet.aller ? 'aller' : 'retour'}'),
        actions: [
          IconButton(
            tooltip: _camera ? 'Douchette ou saisie' : 'Caméra',
            icon: Icon(_camera ? Icons.keyboard_alt_outlined : Icons.photo_camera_outlined),
            onPressed: () => setState(() => _camera = !_camera),
          ),
        ],
      ),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<EvenementBus>(
                    segments: const [
                      ButtonSegment(value: EvenementBus.montee, icon: Icon(Icons.login), label: Text('Montée')),
                      ButtonSegment(value: EvenementBus.descente, icon: Icon(Icons.logout), label: Text('Descente')),
                    ],
                    selected: {_evenement},
                    onSelectionChanged: (s) => setState(() => _evenement = s.first),
                  ),
                ),
                const SizedBox(width: 12),
                Chip(avatar: const Icon(Icons.airline_seat_recline_normal, size: 18), label: Text('${aBord.length} à bord')),
              ],
            ),
          ),
          if (_gps != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_gps!, style: TextStyle(color: palette.encreSecondaire, fontSize: 12)),
            ),
          SizedBox(
            height: 200,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _camera
                    ? MobileScanner(
                        controller: _controleur ??= MobileScannerController(
                          formats: const [BarcodeFormat.qrCode],
                          detectionSpeed: DetectionSpeed.normal,
                        ),
                        onDetect: (capture) {
                          final valeur = capture.barcodes.firstOrNull?.rawValue;
                          if (valeur != null) unawaited(_lire(valeur));
                        },
                      )
                    : Container(
                        color: palette.surface,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _saisie,
                          focusNode: _focus,
                          autofocus: true,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(hintText: 'Carte à la douchette, ou code', border: OutlineInputBorder()),
                          onSubmitted: _lire,
                        ),
                      ),
              ),
            ),
          ),
          if (_dernier != null) _ResultatScan(resultat: _dernier!),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final a in arrets)
                  Card(
                    color: a.id == prochain?.id ? palette.primaire.withValues(alpha: 0.08) : null,
                    child: ListTile(
                      leading: Icon(
                        _trajet.arretsPasses.contains(a.id) ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: _trajet.arretsPasses.contains(a.id) ? palette.succes : palette.encreSecondaire,
                      ),
                      title: Text(a.nom),
                      subtitle: Text([
                        (_trajet.sens == SensTrajet.aller ? a.heureMatin : a.heureSoir) ?? '',
                        '${widget.circuit.eleves.where((e) => e.arretId == a.id).length} élève(s)',
                        if (a.repere != null) a.repere!,
                      ].where((s) => s.isNotEmpty).join(' · ')),
                      trailing: a.id == prochain?.id
                          ? FilledButton.tonal(onPressed: () => _passer(a), child: const Text('Arrêt passé'))
                          : null,
                    ),
                  ),
                if (aBord.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('À bord', style: Theme.of(context).textTheme.titleSmall),
                  for (final e in aBord)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(e?.nomComplet ?? 'Élève hors liste du téléphone'),
                      subtitle: e?.classe == null ? null : Text(e!.classe!),
                    ),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: palette.erreur),
            onPressed: _terminer,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Terminer le trajet'),
          ),
        ),
      ),
    );
  }
}

class _ResultatScan extends StatelessWidget {
  const _ResultatScan({required this.resultat});

  final ResultatScanBus resultat;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final nom = resultat.eleve?.nomComplet ?? resultat.nom;
    final (couleur, icone, texte) = switch (resultat.statut) {
      StatutScanBus.enregistre => (palette.succes, Icons.check_circle, '${nom ?? 'Élève'} : ${resultat.evenement.libelle.toLowerCase()} enregistrée'),
      StatutScanBus.enAttenteEnvoi => (
          palette.succes,
          Icons.cloud_upload_outlined,
          '${nom ?? 'Carte lue'} : ${resultat.evenement.libelle.toLowerCase()} gardée, envoi au retour du réseau',
        ),
      StatutScanBus.horsCircuit => (palette.accent, Icons.info_outline, '${nom ?? 'Élève'} n’est pas inscrit sur ce circuit (enregistré quand même)'),
      StatutScanBus.dejaFait => (palette.accent, Icons.replay, '${nom ?? 'Élève'} : déjà enregistré'),
      StatutScanBus.carteInconnue => (palette.erreur, Icons.block, 'Carte inconnue'),
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icone, color: couleur),
          const SizedBox(width: 10),
          Expanded(child: Text(texte, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
