import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/barre_actions.dart';
import '../../../core/widgets/dialogue_masquage.dart';
import '../application/groupes_classe_providers.dart';
import '../domain/groupe_classe.dart';

String _heure(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Fil du groupe d'une classe.
///
/// - Tout membre : lit, écrit (élève : si le groupe est ouvert aux élèves et
///   pendant les heures de l'école), signale un message (appui long).
/// - Modération (enseignant de la classe, direction) : retire un message
///   avec un motif — l'élève voit « message retiré », les adultes gardent le
///   texte —, traite les signalements, réserve le groupe aux annonces ou le
///   suspend.
/// Écrit sans réseau, un message part au retour de la connexion.
class EcranFilGroupe extends ConsumerStatefulWidget {
  const EcranFilGroupe({super.key, required this.groupe, required this.etablissementId});

  final GroupeClasse groupe;
  final String etablissementId;

  @override
  ConsumerState<EcranFilGroupe> createState() => _EcranFilGroupeState();
}

class _EcranFilGroupeState extends ConsumerState<EcranFilGroupe> {
  final _texte = TextEditingController();
  late GroupeClasse _groupe = widget.groupe;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(groupesClasseRepositoryProvider).marquerLu(_groupe.id);
    });
  }

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  void _rafraichir() => ref.invalidate(filGroupeProvider(_groupe.id));

  void _dire(String texte) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  Future<void> _action(Future<void> Function() action, {String? succes}) async {
    setState(() => _enCours = true);
    try {
      await action();
      if (succes != null) _dire(succes);
      _rafraichir();
    } on ErreurGroupe catch (e) {
      _dire(e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _envoyer() async {
    final texte = _texte.text.trim();
    if (texte.isEmpty) return;
    await _action(() async {
      final recu = await ref.read(groupesClasseRepositoryProvider).envoyer(_groupe.id, texte);
      _texte.clear();
      if (!recu) _dire('Sans réseau : votre message partira dès le retour de la connexion.');
    });
  }

  Future<void> _menuMessage(MessageGroupe m) async {
    if (m.enAttenteEnvoi || m.masque || (m.deMoi && !_groupe.moderateur)) return;
    final choix = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!m.deMoi && !m.masque)
            ListTile(
              key: const Key('action_signaler'),
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Signaler ce message'),
              subtitle: const Text('Un enseignant ou la direction le verra.'),
              onTap: () => Navigator.of(context).pop('signaler'),
            ),
          if (_groupe.moderateur && !m.masque)
            ListTile(
              key: const Key('action_retirer'),
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Retirer ce message'),
              subtitle: const Text('Les élèves verront « message retiré ».'),
              onTap: () => Navigator.of(context).pop('retirer'),
            ),
        ]),
      ),
    );
    if (!mounted || choix == null) return;
    final depot = ref.read(groupesClasseRepositoryProvider);
    if (choix == 'signaler') {
      final motif = await showDialog<String>(context: context, builder: (_) => const _DialogueSignalement());
      if (motif == null) return;
      await _action(() => depot.signaler(m.id, motif), succes: 'Merci, le message a été signalé.');
    } else {
      final motif = await showDialog<String>(
        context: context,
        builder: (_) => const DialogueMasquage(
          texte: 'Les élèves verront « message retiré ». Le texte reste visible pour les adultes de l’école, '
              'et l’action est inscrite au journal (vous, la date, la raison).',
        ),
      );
      if (motif == null) return;
      await _action(() => depot.masquer(m.id, motif));
      ref.invalidate(signalementsGroupeProvider(_groupe.id));
    }
  }

  Future<void> _reglages() async {
    final resultat = await showModalBottomSheet<GroupeClasse>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ReglagesGroupe(groupe: _groupe),
    );
    if (resultat != null && mounted) setState(() => _groupe = resultat);
  }

  Future<void> _voirSignalements() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _Signalements(groupeId: _groupe.id),
    );
    _rafraichir();
  }

  @override
  Widget build(BuildContext context) {
    final fil = ref.watch(filGroupeProvider(_groupe.id));
    final signalements = _groupe.moderateur ? ref.watch(signalementsGroupeProvider(_groupe.id)).valueOrNull : null;
    final schema = Theme.of(context).colorScheme;
    final peutEcrire = _groupe.moderateur || (_groupe.actif && _groupe.elevesPeuventEcrire);
    return Scaffold(
      appBar: AppBar(
        title: Text(_groupe.nom),
        // REG-28 : actions visibles, avec leur libellé, sous le titre.
        bottom: _groupe.moderateur
            ? BarreActions(actions: [
                if ((signalements?.length ?? 0) > 0)
                  ActionEcran(
                    cle: const Key('voir_signalements'),
                    icone: Icons.flag_outlined,
                    libelle: 'Signalements (${signalements!.length})',
                    principale: true,
                    onPressed: _voirSignalements,
                  ),
                ActionEcran(
                  cle: const Key('reglages_groupe'),
                  icone: Icons.tune,
                  libelle: 'Réglages du groupe',
                  onPressed: _reglages,
                ),
              ])
            : null,
      ),
      body: Column(
        children: [
          if (!_groupe.actif || !_groupe.elevesPeuventEcrire)
            MaterialBanner(
              key: const Key('bandeau_groupe'),
              content: Text(!_groupe.actif
                  ? 'Groupe suspendu : seuls les enseignants peuvent y écrire.'
                  : 'Annonces de la classe : seuls les enseignants y écrivent.'),
              leading: Icon(!_groupe.actif ? Icons.pause_circle_outline : Icons.campaign_outlined),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _rafraichir(),
              child: fil.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
                  Text(e is ErreurGroupe ? e.message : 'Fil indisponible. Tirez pour réessayer.', textAlign: TextAlign.center),
                ]),
                data: (messages) => messages.isEmpty
                    ? ListView(padding: const EdgeInsets.all(24), children: const [
                        Text('Aucun message pour le moment.', textAlign: TextAlign.center),
                      ])
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final m = messages[messages.length - 1 - i];
                          return _Bulle(message: m, moderateur: _groupe.moderateur, surAppuiLong: () => _menuMessage(m));
                        },
                      ),
              ),
            ),
          ),
          if (peutEcrire)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      key: const Key('champ_message_groupe'),
                      controller: _texte,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Écrire à la classe…', counterText: ''),
                    ),
                  ),
                  IconButton(
                    key: const Key('bouton_envoyer_groupe'),
                    tooltip: 'Envoyer',
                    onPressed: _enCours ? null : _envoyer,
                    icon: Icon(Icons.send, color: schema.primary),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.message, required this.moderateur, required this.surAppuiLong});

  final MessageGroupe message;
  final bool moderateur;
  final VoidCallback surAppuiLong;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final theme = Theme.of(context);
    final schema = theme.colorScheme;
    final petit = theme.textTheme.bodySmall;
    final fond = m.deMoi
        ? schema.primaryContainer
        : (m.adulte ? schema.tertiaryContainer : schema.surfaceContainerHighest);
    return Align(
      alignment: m.deMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        key: ValueKey('message_${m.id}'),
        onLongPress: surAppuiLong,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  if (!m.deMoi) '${m.auteur ?? ''}${m.adulte ? ' · enseignant' : ''}',
                  _heure(m.creeLe),
                  if (m.enAttenteEnvoi) 'en attente d’envoi',
                ].join(' · '),
                style: petit,
              ),
              if (m.masque && m.corps == null)
                Text('Message retiré', style: TextStyle(fontStyle: FontStyle.italic, color: schema.outline))
              else
                Text(m.corps ?? '', style: TextStyle(decoration: m.masque ? TextDecoration.lineThrough : null)),
              if (m.masque && moderateur)
                Text('Retiré${m.motif == null ? '' : ' : ${m.motif}'}', style: petit?.copyWith(color: schema.error)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReglagesGroupe extends ConsumerStatefulWidget {
  const _ReglagesGroupe({required this.groupe});

  final GroupeClasse groupe;

  @override
  ConsumerState<_ReglagesGroupe> createState() => _ReglagesGroupeState();
}

class _ReglagesGroupeState extends ConsumerState<_ReglagesGroupe> {
  late bool _eleves = widget.groupe.elevesPeuventEcrire;
  late bool _actif = widget.groupe.actif;
  bool _enCours = false;
  String? _erreur;

  Future<void> _enregistrer() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await ref.read(groupesClasseRepositoryProvider).regler(widget.groupe.id, elevesPeuventEcrire: _eleves, actif: _actif);
      final g = widget.groupe;
      if (mounted) {
        Navigator.of(context).pop(GroupeClasse(
          id: g.id,
          nom: g.nom,
          classeId: g.classeId,
          classe: g.classe,
          actif: _actif,
          elevesPeuventEcrire: _eleves,
          moderateur: g.moderateur,
        ));
      }
    } on ErreurGroupe catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(
            key: const Key('reglage_eleves_ecrivent'),
            title: const Text('Les élèves peuvent écrire'),
            subtitle: const Text('Désactivé : le groupe ne sert qu’aux annonces des enseignants.'),
            value: _eleves,
            onChanged: (v) => setState(() => _eleves = v),
          ),
          SwitchListTile(
            key: const Key('reglage_actif'),
            title: const Text('Groupe actif'),
            subtitle: const Text('Désactivé : groupe suspendu, les élèves lisent sans écrire.'),
            value: _actif,
            onChanged: (v) => setState(() => _actif = v),
          ),
          if (_erreur != null)
            Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('enregistrer_reglages'),
            onPressed: _enCours ? null : _enregistrer,
            child: const Text('Enregistrer'),
          ),
        ]),
      ),
    );
  }
}

class _Signalements extends ConsumerWidget {
  const _Signalements({required this.groupeId});

  final String groupeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(signalementsGroupeProvider(groupeId));
    final depot = ref.read(groupesClasseRepositoryProvider);
    Future<void> agir(Future<void> Function() action) async {
      try {
        await action();
      } on ErreurGroupe catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      ref.invalidate(signalementsGroupeProvider(groupeId));
    }

    return SafeArea(
      child: liste.when(
        loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(e is ErreurGroupe ? e.message : 'Signalements indisponibles.'),
        ),
        data: (signalements) => signalements.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('Aucun signalement en attente.'))
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  for (final s in signalements)
                    Card(
                      key: ValueKey('signalement_${s.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('« ${s.extrait ?? ''} »  — ${s.auteur ?? ''}'),
                          const SizedBox(height: 4),
                          Text('Signalé par ${s.par ?? 'un membre'} : ${s.motif}', style: Theme.of(context).textTheme.bodySmall),
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            TextButton(
                              key: Key('ecarter_${s.id}'),
                              onPressed: () => agir(() => depot.ecarter(s.id)),
                              child: const Text('Laisser'),
                            ),
                            FilledButton.tonal(
                              key: Key('retirer_${s.id}'),
                              onPressed: () => agir(() => depot.masquer(s.messageId, 'Signalé : ${s.motif}')),
                              child: const Text('Retirer'),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _DialogueSignalement extends StatefulWidget {
  const _DialogueSignalement();

  @override
  State<_DialogueSignalement> createState() => _DialogueSignalementState();
}

class _DialogueSignalementState extends State<_DialogueSignalement> {
  final _motif = TextEditingController();

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Signaler ?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Le message reste en place. Un enseignant ou la direction le regarde et décide.'),
        const SizedBox(height: 12),
        TextField(
          key: const Key('champ_motif_signalement'),
          controller: _motif,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Pourquoi ?'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_motif.text), child: const Text('Signaler')),
      ],
    );
  }
}
