import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/sync/device_id_provider.dart';
import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../../scolarite/domain/inscription.dart';
import '../application/vie_scolaire_providers.dart';
import '../domain/enums_vie_scolaire.dart';
import '../domain/presence.dart';

/// Appel d'une classe (M7, mode enseignant/surveillant) — pointage
/// quotidien, fonctionne sans réseau (file `sync_queue`, même mécanisme que
/// la saisie de notes en M6).
class EcranAppelClasse extends ConsumerStatefulWidget {
  const EcranAppelClasse({super.key, required this.classe});

  final Classe classe;

  @override
  ConsumerState<EcranAppelClasse> createState() => _EcranAppelClasseState();
}

class _EcranAppelClasseState extends ConsumerState<EcranAppelClasse> {
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final inscriptions = ref.watch(inscriptionsDeClasseProvider(widget.classe.id));
    final presences = ref.watch(
      presencesDeClasseProvider((classeId: widget.classe.id, date: _date)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text("Appel — ${widget.classe.nom}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.event_outlined),
            tooltip: 'Changer de date',
            onPressed: _choisirDate,
          ),
        ],
      ),
      body: Column(
        children: [
          _BandeauDate(date: _date),
          const _BandeauHorsLigne(),
          Expanded(
            child: switch ((inscriptions, presences)) {
              (AsyncData(value: final eleves), AsyncData(value: final lignes)) => _Liste(
                  classe: widget.classe,
                  date: _date,
                  eleves: eleves,
                  presencesParFiche: {for (final p in lignes) p.ficheEleveId: p},
                ),
              (AsyncError(), _) || (_, AsyncError()) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Impossible de charger la classe ou le pointage.'),
                  ),
                ),
              _ => ListView(
                  padding: const EdgeInsets.all(16),
                  children: List.generate(6, (_) => const ShimmerCarteListe()),
                ),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _choisirDate() async {
    final choisie = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime.now(),
    );
    if (choisie != null) setState(() => _date = choisie);
  }
}

class _BandeauDate extends StatelessWidget {
  const _BandeauDate({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final couleur = context.palette.primaire;
    return Container(
      width: double.infinity,
      color: couleur.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined, size: 16, color: couleur),
          const SizedBox(width: 8),
          Text(
            '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
            style: TextStyle(color: couleur, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _BandeauHorsLigne extends ConsumerWidget {
  const _BandeauHorsLigne();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(estEnLigneProvider)) return const SizedBox.shrink();
    final couleur = context.palette.accent;
    return Container(
      width: double.infinity,
      color: couleur.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: couleur),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hors ligne — le pointage sera envoyé au retour du réseau.',
              style: TextStyle(color: couleur, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Liste extends StatelessWidget {
  const _Liste({
    required this.classe,
    required this.date,
    required this.eleves,
    required this.presencesParFiche,
  });

  final Classe classe;
  final DateTime date;
  final List<Inscription> eleves;
  final Map<String, Presence> presencesParFiche;

  @override
  Widget build(BuildContext context) {
    if (eleves.isEmpty) {
      return const Center(child: Text('Aucun élève inscrit dans cette classe.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: eleves.length,
      itemBuilder: (context, i) {
        final inscription = eleves[i];
        return _LigneAppel(
          classe: classe,
          date: date,
          inscription: inscription,
          presenceExistante: presencesParFiche[inscription.ficheEleveId],
        );
      },
    );
  }
}

enum _EtatLigne { repos, enCours, synchronise, enAttente, erreur }

class _LigneAppel extends ConsumerStatefulWidget {
  const _LigneAppel({
    required this.classe,
    required this.date,
    required this.inscription,
    this.presenceExistante,
  });

  final Classe classe;
  final DateTime date;
  final Inscription inscription;
  final Presence? presenceExistante;

  @override
  ConsumerState<_LigneAppel> createState() => _LigneAppelState();
}

class _LigneAppelState extends ConsumerState<_LigneAppel> {
  late StatutPresence _statut = widget.presenceExistante?.statut ?? StatutPresence.present;
  late bool _justifie = widget.presenceExistante?.justifie ?? false;
  late final TextEditingController _motifCtrl =
      TextEditingController(text: widget.presenceExistante?.motif ?? '');
  final _minutesCtrl = TextEditingController(text: '5');
  _EtatLigne _etat = _EtatLigne.repos;

  @override
  void dispose() {
    _motifCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final profil = ref.read(profilProvider).value;
    if (profil == null) return;

    setState(() => _etat = _EtatLigne.enCours);

    final deviceId = await ref.read(deviceIdProvider.future);
    final enLigne = ref.read(estEnLigneProvider);
    final repo = ref.read(vieScolaireRepositoryProvider);

    final presence = construirePresenceSaisie(
      etablissementId: widget.classe.etablissementId,
      anneeScolaireId: widget.classe.anneeScolaireId,
      classeId: widget.classe.id,
      ficheEleveId: widget.inscription.ficheEleveId,
      date: widget.date,
      saisiPar: profil.id,
      deviceId: deviceId,
      enLigne: enLigne,
      statut: _statut,
      justifie: _statut == StatutPresence.absent ? _justifie : false,
      motif: _statut == StatutPresence.absent ? _motifCtrl.text.trim() : null,
    );

    try {
      var synchronisee = await repo.saisirPresence(presence);

      if (_statut == StatutPresence.retard) {
        final minutes = int.tryParse(_minutesCtrl.text) ?? 0;
        if (minutes > 0) {
          final retard = construireRetardSaisie(
            etablissementId: widget.classe.etablissementId,
            ficheEleveId: widget.inscription.ficheEleveId,
            anneeScolaireId: widget.classe.anneeScolaireId,
            date: widget.date,
            minutesRetard: minutes,
            saisiPar: profil.id,
            deviceId: deviceId,
            enLigne: enLigne,
            justifie: _justifie,
            motif: _motifCtrl.text.trim().isEmpty ? null : _motifCtrl.text.trim(),
          );
          final retardSynchronise = await repo.saisirRetard(retard);
          synchronisee = synchronisee && retardSynchronise;
        }
      }

      if (!mounted) return;
      setState(() => _etat = synchronisee ? _EtatLigne.synchronise : _EtatLigne.enAttente);
    } catch (_) {
      if (!mounted) return;
      setState(() => _etat = _EtatLigne.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nom = widget.inscription.fiche?.nomComplet ?? 'Élève';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(nom, overflow: TextOverflow.ellipsis)),
                _BoutonEtat(etat: _etat, onAppui: _enregistrer),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final statut in StatutPresence.values)
                  ChoiceChip(
                    label: Text(statut.libelle),
                    selected: _statut == statut,
                    onSelected: (_) => setState(() => _statut = statut),
                  ),
              ],
            ),
            if (_statut == StatutPresence.absent) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(value: _justifie, onChanged: (v) => setState(() => _justifie = v ?? false)),
                  const Text('Justifiée', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _motifCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Motif (optionnel)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_statut == StatutPresence.retard) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: _minutesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: 'min',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Checkbox(value: _justifie, onChanged: (v) => setState(() => _justifie = v ?? false)),
                  const Text('Justifié', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _motifCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Motif (optionnel)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BoutonEtat extends StatelessWidget {
  const _BoutonEtat({required this.etat, required this.onAppui});

  final _EtatLigne etat;
  final VoidCallback onAppui;

  @override
  Widget build(BuildContext context) {
    return switch (etat) {
      _EtatLigne.enCours => const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      _EtatLigne.synchronise =>
        IconButton(icon: Icon(Icons.check_circle, color: context.palette.succes), onPressed: onAppui),
      _EtatLigne.enAttente =>
        IconButton(icon: Icon(Icons.cloud_off, color: context.palette.accent), onPressed: onAppui),
      _EtatLigne.erreur =>
        IconButton(icon: Icon(Icons.error_outline, color: context.palette.erreur), onPressed: onAppui),
      _EtatLigne.repos =>
        IconButton(icon: Icon(Icons.save_outlined, color: context.palette.primaire), onPressed: onAppui),
    };
  }
}
