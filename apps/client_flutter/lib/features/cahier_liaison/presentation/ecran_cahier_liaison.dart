import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/dialogue_masquage.dart';
import '../application/cahier_liaison_providers.dart';
import '../domain/cahier_liaison.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Cahier de liaison d'un élève : mots du personnel et réponses.
///
/// - Parent : confirme la lecture (« J'ai lu ») et répond.
/// - Personnel autorisé : écrit un nouveau mot, répond, voit qui a lu.
/// - Direction : masque un message (raison, journal d'audit).
/// Tout ce qui est écrit sans réseau part au retour de la connexion.
class EcranCahierLiaison extends ConsumerStatefulWidget {
  const EcranCahierLiaison({
    super.key,
    required this.ficheEleveId,
    required this.nomEleve,
    required this.personnel,
    this.direction = false,
  });

  final String ficheEleveId;
  final String nomEleve;
  final bool personnel;
  final bool direction;

  @override
  ConsumerState<EcranCahierLiaison> createState() => _EcranCahierLiaisonState();
}

class _EcranCahierLiaisonState extends ConsumerState<EcranCahierLiaison> {
  final _nouveau = TextEditingController();
  bool _enCours = false;

  @override
  void dispose() {
    _nouveau.dispose();
    super.dispose();
  }

  void _rafraichir() => ref.invalidate(cahierLiaisonProvider(widget.ficheEleveId));

  void _informer(bool recu) {
    if (!recu && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sans réseau : votre message partira dès le retour de la connexion.')),
      );
    }
  }

  Future<void> _ecrire() async {
    final texte = _nouveau.text.trim();
    if (texte.isEmpty) return;
    setState(() => _enCours = true);
    try {
      final recu = await ref.read(cahierLiaisonRepositoryProvider).ecrireMot(widget.ficheEleveId, texte);
      _nouveau.clear();
      _informer(recu);
      _rafraichir();
    } on ErreurCahier catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fil = ref.watch(cahierLiaisonProvider(widget.ficheEleveId));
    return Scaffold(
      appBar: AppBar(title: Text('Cahier de ${widget.nomEleve}')),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _rafraichir(),
              child: fil.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
                  Text(e is ErreurCahier ? e.message : 'Cahier indisponible. Tirez pour réessayer.', textAlign: TextAlign.center),
                ]),
                data: (mots) => mots.isEmpty
                    ? ListView(padding: const EdgeInsets.all(24), children: [
                        Text(
                          widget.personnel
                              ? 'Écrivez le premier mot : les parents de ${widget.nomEleve} seront prévenus.'
                              : 'Aucun mot pour le moment. Vous serez prévenu(e) dès que l’école écrira.',
                          textAlign: TextAlign.center,
                        ),
                      ])
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          for (final m in mots)
                            _CarteMot(
                              mot: m,
                              ficheEleveId: widget.ficheEleveId,
                              personnel: widget.personnel,
                              direction: widget.direction,
                              surChangement: _rafraichir,
                              surEnvoi: _informer,
                            ),
                        ],
                      ),
              ),
            ),
          ),
          if (widget.personnel)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('champ_nouveau_mot'),
                        controller: _nouveau,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        decoration: const InputDecoration(labelText: 'Nouveau mot aux parents', counterText: ''),
                      ),
                    ),
                    IconButton(
                      key: const Key('bouton_envoyer_mot'),
                      tooltip: 'Envoyer',
                      onPressed: _enCours ? null : _ecrire,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CarteMot extends ConsumerStatefulWidget {
  const _CarteMot({
    required this.mot,
    required this.ficheEleveId,
    required this.personnel,
    required this.direction,
    required this.surChangement,
    required this.surEnvoi,
  });

  final MotLiaison mot;
  final String ficheEleveId;
  final bool personnel;
  final bool direction;
  final VoidCallback surChangement;
  final void Function(bool recu) surEnvoi;

  @override
  ConsumerState<_CarteMot> createState() => _CarteMotState();
}

class _CarteMotState extends ConsumerState<_CarteMot> {
  final _reponse = TextEditingController();
  bool _enCours = false;

  @override
  void dispose() {
    _reponse.dispose();
    super.dispose();
  }

  Future<void> _action(Future<void> Function() action) async {
    setState(() => _enCours = true);
    try {
      await action();
      widget.surChangement();
    } on ErreurCahier catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _repondre() async {
    final texte = _reponse.text.trim();
    if (texte.isEmpty) return;
    await _action(() async {
      final recu = await ref
          .read(cahierLiaisonRepositoryProvider)
          .repondre(ficheEleveId: widget.ficheEleveId, motId: widget.mot.id, corps: texte);
      _reponse.clear();
      widget.surEnvoi(recu);
    });
  }

  Future<void> _masquer(String messageId) async {
    final motif = await showDialog<String>(
      context: context,
      builder: (_) => const DialogueMasquage(
        texte: 'Les parents ne verront plus ce message. Il reste visible pour le personnel, et l’action est '
            'inscrite au journal (vous, la date, la raison).',
      ),
    );
    if (motif == null || !mounted) return;
    await _action(() => ref.read(cahierLiaisonRepositoryProvider).masquer(messageId, motif));
  }

  Widget _boutonMasquer(String messageId, bool masque) => widget.direction && !masque
      ? IconButton(
          key: Key('masquer_$messageId'),
          tooltip: 'Masquer',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.visibility_off_outlined, size: 20),
          onPressed: _enCours ? null : () => _masquer(messageId),
        )
      : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final m = widget.mot;
    final theme = Theme.of(context);
    final schema = theme.colorScheme;
    final petit = theme.textTheme.bodySmall;

    String entete(String? auteur, DateTime le, bool enAttente, bool masque) => [
          auteur ?? 'Vous',
          _date(le),
          if (enAttente) 'en attente d’envoi',
          if (masque) 'masqué',
        ].join(' · ');

    return Card(
      key: ValueKey('mot_${m.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(entete(m.auteur, m.creeLe, m.enAttenteEnvoi, m.masque), style: petit)),
                _boutonMasquer(m.id, m.masque),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                m.corps,
                style: TextStyle(decoration: m.masque ? TextDecoration.lineThrough : null),
              ),
            ),
            if (m.masque && m.motifMasquage != null)
              Text('Masqué : ${m.motifMasquage}', style: petit?.copyWith(color: schema.error)),
            const SizedBox(height: 6),
            if (widget.personnel && m.parents != null)
              Text('Lu par ${m.lectures ?? 0}/${m.parents} parent(s)', key: Key('lectures_${m.id}'), style: petit)
            else if (!widget.personnel)
              Align(
                alignment: Alignment.centerLeft,
                child: m.lu
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle, size: 18, color: schema.primary),
                        const SizedBox(width: 6),
                        Text('Lecture confirmée', style: petit),
                      ])
                    : OutlinedButton.icon(
                        key: Key('confirmer_${m.id}'),
                        onPressed: _enCours || m.enAttenteEnvoi
                            ? null
                            : () => _action(() => ref.read(cahierLiaisonRepositoryProvider).confirmerLecture(m.id)),
                        icon: const Icon(Icons.done),
                        label: const Text('J’ai lu'),
                      ),
              ),
            for (final r in m.reponses)
              Container(
                key: ValueKey('reponse_${r.id}'),
                margin: const EdgeInsets.only(top: 8, left: 16),
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                decoration: BoxDecoration(
                  color: schema.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entete(r.deMoi ? 'Vous' : r.auteur, r.creeLe, r.enAttenteEnvoi, r.masque), style: petit),
                          Text(r.corps, style: TextStyle(decoration: r.masque ? TextDecoration.lineThrough : null)),
                          if (r.masque && r.motifMasquage != null)
                            Text('Masqué : ${r.motifMasquage}', style: petit?.copyWith(color: schema.error)),
                        ],
                      ),
                    ),
                    _boutonMasquer(r.id, r.masque),
                  ],
                ),
              ),
            if (!m.masque && !m.enAttenteEnvoi)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: Key('champ_reponse_${m.id}'),
                        controller: _reponse,
                        minLines: 1,
                        maxLines: 3,
                        maxLength: 2000,
                        decoration: const InputDecoration(isDense: true, hintText: 'Répondre…', counterText: ''),
                      ),
                    ),
                    IconButton(
                      key: Key('envoyer_reponse_${m.id}'),
                      tooltip: 'Répondre',
                      onPressed: _enCours ? null : _repondre,
                      icon: const Icon(Icons.reply),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
