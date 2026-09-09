import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/comm_providers.dart';
import '../domain/enums_comm.dart';
import '../domain/preference_canal.dart';
import 'widgets/badge_signal_ia.dart';

/// Préférences de canaux du compte connecté (M9) — strictement personnelles,
/// écriture tolérante hors-ligne (file `sync_queue`).
class EcranPreferencesCanaux extends ConsumerWidget {
  const EcranPreferencesCanaux({super.key, required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(mesPreferencesProvider(profileId));
    final canalRecommande = ref.watch(choisirCanalProvider((profileId: profileId, type: 'general')));
    final heureRecommandee = ref.watch(suggereHeureEnvoiProvider(profileId));

    return Scaffold(
      appBar: AppBar(title: const Text('Préférences de notification')),
      body: preferences.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(4, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Préférences indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) {
          final parCanal = {for (final p in liste) p.canal: p};
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: context.palette.premium.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BadgeSignalIa(texte: 'Signal IA — recommandations, pas des réglages imposés'),
                      const SizedBox(height: 8),
                      canalRecommande.when(
                        loading: () => const SizedBox.shrink(),
                        error: (erreur, _) => const SizedBox.shrink(),
                        data: (canal) => Text('Canal recommandé pour vous : ${_libelleCanal(canal)}'),
                      ),
                      heureRecommandee.when(
                        loading: () => const SizedBox.shrink(),
                        error: (erreur, _) => const SizedBox.shrink(),
                        data: (heure) => Text('Créneau d\'envoi suggéré : $heure'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (final canal in CanalNotification.values)
                _CarteCanal(
                  profileId: profileId,
                  canal: canal,
                  preference: parCanal[canal],
                ),
            ],
          );
        },
      ),
    );
  }

  static String _libelleCanal(String code) => CanalNotification.depuisCode(code).libelle;
}

class _CarteCanal extends ConsumerStatefulWidget {
  const _CarteCanal({required this.profileId, required this.canal, this.preference});

  final String profileId;
  final CanalNotification canal;
  final PreferenceCanal? preference;

  @override
  ConsumerState<_CarteCanal> createState() => _CarteCanalState();
}

class _CarteCanalState extends ConsumerState<_CarteCanal> {
  late bool _actif = widget.preference?.actif ?? true;
  late String _horaireDebut = widget.preference?.horaireDebut ?? '08:00';
  late String _horaireFin = widget.preference?.horaireFin ?? '19:00';
  late FrequenceNotification _frequence = widget.preference?.frequence ?? FrequenceNotification.immediat;

  Future<void> _enregistrer() async {
    final preference = construirePreference(
      profileId: widget.profileId,
      canal: widget.canal,
      actif: _actif,
      horaireDebut: _horaireDebut,
      horaireFin: _horaireFin,
      frequence: _frequence,
    );
    await ref.read(commRepositoryProvider).definirPreference(preference);
    ref.invalidate(mesPreferencesProvider(widget.profileId));
  }

  Future<void> _choisirHeure({required bool debut}) async {
    final actuelle = debut ? _horaireDebut : _horaireFin;
    final parties = actuelle.split(':');
    final heureInitiale = TimeOfDay(
      hour: int.tryParse(parties.elementAt(0)) ?? 8,
      minute: int.tryParse(parties.elementAt(1)) ?? 0,
    );
    final choisie = await showTimePicker(context: context, initialTime: heureInitiale);
    if (choisie == null) return;
    final formatee = '${choisie.hour.toString().padLeft(2, '0')}:${choisie.minute.toString().padLeft(2, '0')}';
    setState(() => debut ? _horaireDebut = formatee : _horaireFin = formatee);
    await _enregistrer();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.canal.libelle, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: _actif,
                  onChanged: (v) async {
                    setState(() => _actif = v);
                    await _enregistrer();
                  },
                ),
              ],
            ),
            if (_actif) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _choisirHeure(debut: true),
                      icon: const Icon(Icons.schedule_outlined, size: 16),
                      label: Text('Dès $_horaireDebut'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _choisirHeure(debut: false),
                      icon: const Icon(Icons.schedule_outlined, size: 16),
                      label: Text('Jusqu\'à $_horaireFin'),
                    ),
                  ),
                ],
              ),
              DropdownButtonFormField<FrequenceNotification>(
                initialValue: _frequence,
                decoration: const InputDecoration(labelText: 'Fréquence', isDense: true),
                items: [
                  for (final f in FrequenceNotification.values)
                    DropdownMenuItem(value: f, child: Text(f.libelle)),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _frequence = v);
                  await _enregistrer();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
