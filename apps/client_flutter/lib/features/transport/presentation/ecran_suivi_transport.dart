import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../application/transport_providers.dart';
import '../domain/transport.dart';

/// Suivi du bus par la famille (cahier 24.2, 24.3) : circuit, arrêt et
/// horaires de l'enfant ; pendant un trajet seulement, où en est le bus
/// (dernier arrêt passé, arrêts restants avant le sien, position sur la
/// carte) et si l'enfant est à bord. Rafraîchi toutes les 30 secondes
/// pendant un trajet. Sans réseau, la dernière situation connue reste
/// affichée avec son heure.
class EcranSuiviTransport extends ConsumerStatefulWidget {
  const EcranSuiviTransport({super.key, required this.ficheEleveId, required this.prenom});

  final String ficheEleveId;
  final String prenom;

  @override
  ConsumerState<EcranSuiviTransport> createState() => _EcranSuiviTransportState();
}

class _EcranSuiviTransportState extends ConsumerState<EcranSuiviTransport> {
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _minuteur = Timer.periodic(const Duration(seconds: 30), (_) {
      final enCours = ref.read(suiviTransportProvider(widget.ficheEleveId)).valueOrNull?.trajetEnCours ?? false;
      if (enCours) ref.invalidate(suiviTransportProvider(widget.ficheEleveId));
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  static String _heure(DateTime d) => '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final suivi = ref.watch(suiviTransportProvider(widget.ficheEleveId));
    return Scaffold(
      appBar: AppBar(title: Text('Bus de ${widget.prenom}')),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(suiviTransportProvider(widget.ficheEleveId)),
              child: suivi.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(e is ErreurTransport ? e.messageUtilisateur : 'Suivi indisponible pour le moment.'),
                  ),
                ]),
                data: (s) => !s.affecte
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text('${widget.prenom} n’est inscrit(e) sur aucun circuit de bus cette année.',
                              textAlign: TextAlign.center),
                        ),
                      ])
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _CarteTrajet(suivi: s, prenom: widget.prenom),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.circuit?.nom ?? '', style: Theme.of(context).textTheme.titleMedium),
                                  if (s.circuit?.vehicule != null) Text(s.circuit!.vehicule!),
                                  const SizedBox(height: 8),
                                  if (s.monArret != null)
                                    Text(
                                      'Arrêt de ${widget.prenom} : ${s.monArret!.nom}'
                                      '${s.monArret!.repere == null ? '' : ' (${s.monArret!.repere})'}',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  if (s.monArret?.heureMatin != null) Text('Passage le matin vers ${s.monArret!.heureMatin}'),
                                  if (s.monArret?.heureSoir != null) Text('Retour le soir vers ${s.monArret!.heureSoir}'),
                                  if (s.circuit?.telephoneChauffeur != null) ...[
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      onPressed: () => launchUrl(Uri.parse('tel:+${s.circuit!.telephoneChauffeur}')),
                                      icon: const Icon(Icons.call_outlined),
                                      label: const Text('Appeler le chauffeur'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (s.aujourdHui.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text('Aujourd’hui', style: Theme.of(context).textTheme.titleSmall),
                            for (final e in s.aujourdHui)
                              ListTile(
                                dense: true,
                                leading: Icon(e.evenement == EvenementBus.montee ? Icons.login : Icons.logout,
                                    color: palette.primaire),
                                title: Text('${e.evenement == EvenementBus.montee ? 'Montée' : 'Descente'} à ${_heure(e.heure)}'),
                                subtitle: e.arret == null ? null : Text(e.arret!),
                              ),
                          ],
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

class _CarteTrajet extends StatelessWidget {
  const _CarteTrajet({required this.suivi, required this.prenom});

  final SuiviTransport suivi;
  final String prenom;

  static String _heure(DateTime d) => '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (!suivi.trajetEnCours) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.directions_bus_outlined, color: palette.encreSecondaire),
          title: const Text('Pas de trajet en cours'),
          subtitle: const Text('Vous serez prévenu(e) quand le bus approche, et à la montée et à la descente.'),
        ),
      );
    }
    final restants = suivi.arretsAvantLeMien;
    final dernier = suivi.dernierArret;
    final lat = suivi.trajetLatitude;
    final lng = suivi.trajetLongitude;
    return Card(
      color: palette.primaire.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.directions_bus, color: palette.primaire, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    suivi.trajetSens == SensTrajet.aller ? 'Le bus est en route vers l’école' : 'Le bus ramène les élèves',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (suivi.aBord)
              Text('$prenom est à bord.', style: TextStyle(color: palette.succes, fontWeight: FontWeight.w600)),
            if (dernier != null)
              Text('Dernier arrêt passé : ${dernier.nom}'
                  '${suivi.dernierArretLe == null ? '' : ' à ${_heure(suivi.dernierArretLe!)}'}'),
            if (restants != null)
              Text(restants == 0 ? 'Prochain arrêt : celui de $prenom.' : '$restants arrêt(s) avant celui de $prenom.',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            if (lat != null && lng != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.map_outlined),
                label: Text('Voir le bus sur la carte'
                    '${suivi.positionLe == null ? '' : ' (position de ${_heure(suivi.positionLe!)})'}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
