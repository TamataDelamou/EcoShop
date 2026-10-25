import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/providers.dart';
import '../../../core/sync/device_id_provider.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_palette.dart';
import '../application/pointage_providers.dart';
import '../domain/pointage.dart';

/// Le portail (REG-09) : le téléphone de l'école scanne les cartes à
/// l'arrivée et à la sortie. Caméra (Android, iOS) ou douchette USB /
/// Bluetooth (tout appareil, y compris un PC). Fonctionne sans réseau :
/// les scans partent au retour du réseau, avec leur heure exacte.
class EcranPortail extends ConsumerStatefulWidget {
  const EcranPortail({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranPortail> createState() => _EcranPortailState();
}

class _EcranPortailState extends ConsumerState<EcranPortail> {
  static bool get _cameraDisponible =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  DonneesPortail? _donnees;
  String? _erreurChargement;
  SensPointage? _sensChoisi;
  bool _camera = _cameraDisponible;
  ResultatScan? _dernier;
  int _scansSession = 0;
  bool _enCours = false;
  final _saisie = TextEditingController();
  final _focus = FocusNode();
  Timer? _pouls;
  Timer? _effacement;
  String? _derniereLectureCamera;
  DateTime _derniereLectureCameraLe = DateTime(2000);

  @override
  void initState() {
    super.initState();
    _charger();
    // Signal régulier : « ce portail n'a plus rien en attente » (condition
    // des alertes d'absence côté serveur).
    _pouls = Timer.periodic(const Duration(minutes: 2), (_) => _signaler());
  }

  @override
  void dispose() {
    _pouls?.cancel();
    _effacement?.cancel();
    _camera0?.dispose();
    _saisie.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final donnees = await ref.read(pointageRepositoryProvider).donneesPortail(widget.etablissementId);
      if (!mounted) return;
      setState(() {
        _donnees = donnees;
        _erreurChargement = null;
      });
      unawaited(_signaler());
    } on ErreurPointage catch (e) {
      if (!mounted) return;
      setState(() => _erreurChargement = e.messageUtilisateur);
    }
  }

  Future<void> _signaler() async {
    if (!ref.read(estEnLigneProvider)) return;
    try {
      final appareil = await ref.read(deviceIdProvider.future);
      await ref.read(pointageRepositoryProvider).signalerPortail(widget.etablissementId, appareil);
    } catch (_) {
      // Prochain essai dans 2 minutes.
    }
  }

  /// Sens proposé selon l'heure : arrivée le matin, sortie l'après-midi.
  SensPointage get _sens {
    final choisi = _sensChoisi;
    if (choisi != null) return choisi;
    final fin = _donnees?.parametres.minutesFinCours ?? 15 * 60;
    final maintenant = TimeOfDay.now();
    return maintenant.hour * 60 + maintenant.minute < fin - 90 ? SensPointage.arrivee : SensPointage.sortie;
  }

  Future<void> _scanner(String lecture) async {
    final texte = lecture.trim();
    if (texte.isEmpty || _enCours) return;
    setState(() => _enCours = true);
    try {
      final appareil = await ref.read(deviceIdProvider.future);
      final resultat = await ref.read(pointageRepositoryProvider).scanner(
            etablissementId: widget.etablissementId,
            lecture: texte,
            sens: _sens,
            appareilId: appareil,
          );
      if (!mounted) return;
      if (resultat.accepte) {
        unawaited(HapticFeedback.mediumImpact());
        unawaited(SystemSound.play(SystemSoundType.click));
      } else {
        unawaited(HapticFeedback.heavyImpact());
      }
      setState(() {
        _dernier = resultat;
        if (resultat.accepte) _scansSession++;
      });
      _effacement?.cancel();
      _effacement = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _dernier = null);
      });
    } on ErreurPointage catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    } finally {
      if (mounted) setState(() => _enCours = false);
      _saisie.clear();
      _focus.requestFocus();
    }
  }

  void _surDetection(BarcodeCapture capture) {
    final valeur = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (valeur == null) return;
    // La caméra voit la même carte plusieurs fois par seconde.
    final maintenant = DateTime.now();
    if (valeur == _derniereLectureCamera && maintenant.difference(_derniereLectureCameraLe) < const Duration(seconds: 4)) {
      return;
    }
    _derniereLectureCamera = valeur;
    _derniereLectureCameraLe = maintenant;
    _scanner(valeur);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enLigne = ref.watch(estEnLigneProvider);
    final suivi = ref.watch(suiviSyncProvider).valueOrNull;
    final sens = _sens;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portail'),
        actions: [
          IconButton(tooltip: 'Recharger les cartes', onPressed: _charger, icon: const Icon(Icons.sync)),
          if (_cameraDisponible)
            IconButton(
              tooltip: _camera ? 'Utiliser une douchette' : 'Utiliser la caméra',
              onPressed: () => setState(() => _camera = !_camera),
              icon: Icon(_camera ? Icons.keyboard_alt_outlined : Icons.photo_camera_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: enLigne ? palette.succes.withValues(alpha: 0.1) : palette.accent.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(enLigne ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      enLigne
                          ? 'En ligne — $_scansSession scan(s) depuis l\'ouverture'
                          : 'Sans réseau — les scans sont gardés (${suivi?.enAttente ?? 0} en attente d\'envoi)',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<SensPointage>(
              segments: const [
                ButtonSegment(value: SensPointage.arrivee, icon: Icon(Icons.login), label: Text('Arrivée')),
                ButtonSegment(value: SensPointage.sortie, icon: Icon(Icons.logout), label: Text('Sortie')),
              ],
              selected: {sens},
              onSelectionChanged: (s) => setState(() => _sensChoisi = s.first),
            ),
          ),
          if (_erreurChargement != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_erreurChargement!, style: TextStyle(color: palette.erreur)),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _camera
                    ? MobileScanner(
                        controller: _controleurCamera,
                        onDetect: _surDetection,
                      )
                    : Container(
                        color: palette.surface,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_scanner, size: 64, color: palette.primaire),
                            const SizedBox(height: 12),
                            const Text('Présentez la carte à la douchette', textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('saisie_portail'),
                              controller: _saisie,
                              focusNode: _focus,
                              autofocus: true,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                hintText: 'ou tapez le code de la carte',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: _scanner,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _dernier == null
                ? const SizedBox(height: 120, key: ValueKey('vide'))
                : _PanneauResultat(key: ValueKey(_dernier!.heure), resultat: _dernier!),
          ),
        ],
      ),
    );
  }

  MobileScannerController? _camera0;
  MobileScannerController get _controleurCamera => _camera0 ??= MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.normal,
      );
}

class _PanneauResultat extends StatelessWidget {
  const _PanneauResultat({super.key, required this.resultat});

  final ResultatScan resultat;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final r = resultat;
    final heure = '${r.heure.hour.toString().padLeft(2, '0')}:${r.heure.minute.toString().padLeft(2, '0')}';
    final (couleur, icone, titre, detail) = switch (r.statut) {
      StatutScan.enregistre || StatutScan.enAttenteEnvoi => (
          r.enRetard ? palette.accent : palette.succes,
          r.statut == StatutScan.enAttenteEnvoi ? Icons.schedule_send : Icons.check_circle,
          r.nomAffiche.isEmpty ? 'Carte enregistrée' : r.nomAffiche,
          [
            if ((r.classe ?? r.carte?.classe) != null) (r.classe ?? r.carte?.classe)!,
            '${r.sens.libelle} $heure',
            if (r.enRetard) 'en retard',
            if (r.statut == StatutScan.enAttenteEnvoi) 'envoi au retour du réseau',
          ].join(' · '),
        ),
      StatutScan.doublon => (
          palette.encreSecondaire,
          Icons.repeat,
          r.nomAffiche.isEmpty ? 'Déjà scannée' : r.nomAffiche,
          'Déjà scannée à l\'instant — rien à faire',
        ),
      StatutScan.carteInconnue => (
          palette.erreur,
          Icons.block,
          'Carte inconnue',
          "Carte d'une autre école, remplacée ou abîmée : orientez l'élève vers le bureau.",
        ),
    };
    return Container(
      height: 120,
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: couleur.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(icone, color: couleur, size: 48),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: palette.encre)),
                const SizedBox(height: 4),
                Text(detail, style: TextStyle(color: palette.encre)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
