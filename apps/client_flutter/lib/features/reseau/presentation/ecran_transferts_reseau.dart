import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../application/transferts_providers.dart';
import '../domain/regles_transferts.dart';
import 'elements_reseau.dart';

/// Transferts d'élèves entre écoles d'un réseau (REG-17).
///
/// - Vu d'une école ([etablissementId]) : élèves à accueillir (accepter en
///   choisissant la classe, ou refuser), départs en cours (annuler),
///   historique ; bouton « Faire partir un élève ».
/// - Vu du réseau ([reseauId]) : tous les transferts ; la Direction
///   Générale valide ou refuse ceux qui l'attendent.
///
/// Demander, valider, accepter, refuser : possible sans réseau, envoyé au
/// retour.
class EcranTransfertsReseau extends ConsumerWidget {
  const EcranTransfertsReseau({
    super.key,
    this.reseauId,
    this.etablissementId,
    required this.titre,
    this.peutValider = false,
    this.devise = 'GNF',
  }) : assert(reseauId != null || etablissementId != null);

  final String? reseauId;
  final String? etablissementId;
  final String titre;
  final bool peutValider;
  final String devise;

  ({String? reseauId, String? etablissementId}) get _cle => (reseauId: reseauId, etablissementId: etablissementId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(transfertsReseauProvider(_cle));
    final ecole = etablissementId;
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      floatingActionButton: ecole == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('demander_transfert'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EcranDemandeTransfert(etablissementId: ecole, devise: devise),
              )),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Faire partir un élève'),
            ),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(transfertsReseauProvider(_cle)),
              child: liste.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  ErreurChargementReseau(erreur: e, reessayer: () => ref.invalidate(transfertsReseauProvider(_cle))),
                ]),
                data: (transferts) {
                  if (transferts.isEmpty) {
                    return ListView(children: const [
                      EtatVideReseau(icone: Icons.swap_horiz, texte: 'Aucun transfert pour le moment.'),
                    ]);
                  }
                  final aTraiter = [
                    for (final t in transferts)
                      if (!t.enAttenteEnvoi &&
                          ((t.statut == 'en_attente_accueil' && t.sens == 'arrivee') ||
                              (t.statut == 'a_valider_reseau' && peutValider && ecole == null)))
                        t,
                  ];
                  final enCours = [
                    for (final t in transferts)
                      if ((t.enCours || t.enAttenteEnvoi) && !aTraiter.contains(t)) t,
                  ];
                  final passes = [
                    for (final t in transferts)
                      if (!t.enCours && !t.enAttenteEnvoi) t,
                  ];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      if (aTraiter.isNotEmpty) ...[
                        _Titre(ecole == null ? 'À valider' : 'Élèves à accueillir', aTraiter.length),
                        for (final t in aTraiter) _CarteTransfert(transfert: t, cle: _cle, devise: devise, aTraiter: true),
                      ],
                      if (enCours.isNotEmpty) ...[
                        _Titre('En cours', enCours.length),
                        for (final t in enCours) _CarteTransfert(transfert: t, cle: _cle, devise: devise),
                      ],
                      if (passes.isNotEmpty) ...[
                        _Titre('Historique', passes.length),
                        for (final t in passes) _CarteTransfert(transfert: t, cle: _cle, devise: devise),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte, this.nombre);

  final String texte;
  final int nombre;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text('$texte ($nombre)', style: Theme.of(context).textTheme.titleMedium),
      );
}

void _signaler(BuildContext context, String texte) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));

Future<String?> _demanderMotif(BuildContext context, String titre) async {
  final champ = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(titre),
        content: TextField(
          controller: champ,
          autofocus: true,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Motif (communiqué à l’école de départ)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: champ.text.trim().length >= 3 ? () => Navigator.pop(c, champ.text.trim()) : null,
            child: const Text('Refuser'),
          ),
        ],
      ),
    ),
  );
  return r;
}

class _CarteTransfert extends ConsumerStatefulWidget {
  const _CarteTransfert({required this.transfert, required this.cle, required this.devise, this.aTraiter = false});

  final TransfertReseau transfert;
  final ({String? reseauId, String? etablissementId}) cle;
  final String devise;
  final bool aTraiter;

  @override
  ConsumerState<_CarteTransfert> createState() => _CarteTransfertState();
}

class _CarteTransfertState extends ConsumerState<_CarteTransfert> {
  bool _enCours = false;

  TransfertReseau get t => widget.transfert;

  Future<void> _agir(Future<bool> Function() action, String reussi) async {
    setState(() => _enCours = true);
    try {
      final recu = await action();
      ref.invalidate(transfertsReseauProvider(widget.cle));
      if (mounted) _signaler(context, recu ? reussi : 'Gardé sur le téléphone : envoyé au retour du réseau.');
    } catch (e) {
      if (mounted) _signaler(context, messageErreurReseau(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _accueillir() async {
    final classe = await showModalBottomSheet<ClasseAccueil>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ChoixClasse(transfertId: t.id),
    );
    if (classe == null) return;
    final repo = ref.read(transfertsReseauRepositoryProvider);
    await _agir(
      () => repo.repondre(transfertId: t.id, accepter: true, classeId: classe.classeId),
      '${t.eleve} est inscrit(e) en ${classe.nom}.',
    );
  }

  Future<void> _refuserAccueil() async {
    final motif = await _demanderMotif(context, 'Refuser ${t.eleve} ?');
    if (motif == null) return;
    final repo = ref.read(transfertsReseauRepositoryProvider);
    await _agir(() => repo.repondre(transfertId: t.id, accepter: false, motif: motif), 'Transfert refusé.');
  }

  Future<void> _valider(bool accorder) async {
    String? motif;
    if (!accorder) {
      motif = await _demanderMotif(context, 'Refuser le transfert de ${t.eleve} ?');
      if (motif == null) return;
    }
    final repo = ref.read(transfertsReseauRepositoryProvider);
    await _agir(
      () => repo.valider(transfertId: t.id, accorder: accorder, motif: motif),
      accorder ? 'Transfert validé : l’école d’accueil est prévenue.' : 'Transfert refusé.',
    );
  }

  Future<void> _annuler() async {
    final repo = ref.read(transfertsReseauRepositoryProvider);
    await _agir(() async {
      await repo.annuler(t.id);
      return true;
    }, 'Transfert annulé.');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dossier = t.dossier;
    final couleur = switch (t.statut) {
      'transfere' => palette.succes,
      'refuse' || 'annule' => palette.erreur,
      _ => palette.accent,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(t.eleve, style: Theme.of(context).textTheme.titleSmall)),
                if (t.enAttenteEnvoi) const PastilleEnAttente() else Text(t.libelleStatut, style: TextStyle(color: couleur)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${t.origine.isEmpty ? 'Votre école' : t.origine} → ${t.destination}'
                '${t.niveau == null ? '' : ' · ${t.niveau}'}'),
            if (t.demandeLe != null)
              Text('Demandé le ${dateCourte(t.demandeLe!)}', style: TextStyle(color: palette.encreSecondaire, fontSize: 12)),
            if (t.motif.isNotEmpty) Text('Motif : ${t.motif}', style: TextStyle(color: palette.encreSecondaire)),
            if (t.soldeAuDepart != null && t.soldeAuDepart! > 0)
              Text('Solde dû à l’école de départ : ${montantReseau(t.soldeAuDepart!, widget.devise)}',
                  style: TextStyle(color: palette.erreur)),
            if (t.inscriptionOfferte && t.enCours)
              Text('Frais d’inscription offerts (règle du réseau).', style: TextStyle(color: palette.succes)),
            if (t.motifRefus != null) Text('Refus : ${t.motifRefus}', style: TextStyle(color: palette.erreur)),
            if (dossier != null && widget.aTraiter) ...[
              const Divider(),
              Text('Dossier transmis', style: Theme.of(context).textTheme.labelLarge),
              Text([
                if (dossier['classe'] != null) 'Classe ${dossier['classe']} (${dossier['annee'] ?? ''})',
                'absences ${dossier['absences'] ?? 0}, retards ${dossier['retards'] ?? 0}',
                if (dossier['redoublant'] == true) 'redoublant(e)',
              ].join(' · ')),
              if (dossier['nom_pere'] != null || dossier['nom_mere'] != null)
                Text('Parents : ${[dossier['nom_pere'], dossier['nom_mere']].whereType<String>().join(', ')}'),
              if (dossier['personne_urgence_nom'] != null)
                Text('À prévenir : ${dossier['personne_urgence_nom']} ${dossier['personne_urgence_telephone'] ?? ''}'),
            ],
            if (widget.aTraiter || (t.enCours && t.sens == 'depart' && !t.enAttenteEnvoi))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (widget.aTraiter && t.statut == 'en_attente_accueil') ...[
                      FilledButton.icon(
                        onPressed: _enCours ? null : _accueillir,
                        icon: const Icon(Icons.how_to_reg_outlined),
                        label: const Text('Accueillir'),
                      ),
                      TextButton(onPressed: _enCours ? null : _refuserAccueil, child: const Text('Refuser')),
                    ],
                    if (widget.aTraiter && t.statut == 'a_valider_reseau') ...[
                      FilledButton.icon(
                        onPressed: _enCours ? null : () => _valider(true),
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Valider'),
                      ),
                      TextButton(onPressed: _enCours ? null : () => _valider(false), child: const Text('Refuser')),
                    ],
                    if (!widget.aTraiter && t.sens == 'depart')
                      TextButton(onPressed: _enCours ? null : _annuler, child: const Text('Annuler le transfert')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChoixClasse extends ConsumerWidget {
  const _ChoixClasse({required this.transfertId});

  final String transfertId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(classesAccueilProvider(transfertId));
    return SafeArea(
      child: classes.when(
        loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(messageErreurReseau(e))),
        data: (liste) => liste.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucune classe ouverte cette année : créez d’abord vos classes.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('Dans quelle classe l’accueillir ?'),
                  ),
                  for (final c in liste)
                    ListTile(
                      leading: Icon(c.memeNiveau ? Icons.star_outline : Icons.class_outlined),
                      title: Text(c.nom),
                      subtitle: Text([
                        if (c.memeNiveau) 'même niveau',
                        c.capacite == null ? '${c.effectif} élèves' : '${c.effectif}/${c.capacite} élèves',
                        if (c.complete) 'complète',
                      ].join(' · ')),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Demande de transfert (école de départ)
// ---------------------------------------------------------------------------
class EcranDemandeTransfert extends ConsumerStatefulWidget {
  const EcranDemandeTransfert({super.key, required this.etablissementId, this.devise = 'GNF'});

  final String etablissementId;
  final String devise;

  @override
  ConsumerState<EcranDemandeTransfert> createState() => _EcranDemandeTransfertState();
}

class _EcranDemandeTransfertState extends ConsumerState<EcranDemandeTransfert> {
  final _motif = TextEditingController();
  String _texte = '';
  Timer? _attente;
  EleveTransferable? _eleve;
  DestinationTransfert? _destination;
  bool _enCours = false;

  @override
  void dispose() {
    _attente?.cancel();
    _motif.dispose();
    super.dispose();
  }

  bool get _bloqueParSolde => _eleve != null && _destination != null && _destination!.quitusRequis && _eleve!.solde > 0;

  Future<void> _envoyer() async {
    final eleve = _eleve;
    final destination = _destination;
    if (eleve == null || destination == null || _motif.text.trim().length < 3) return;
    setState(() => _enCours = true);
    try {
      final recu = await ref.read(transfertsReseauRepositoryProvider).demander(
            etablissementId: widget.etablissementId,
            eleve: eleve,
            destination: destination,
            motif: _motif.text,
          );
      ref.invalidate(transfertsReseauProvider);
      if (!mounted) return;
      _signaler(
        context,
        !recu
            ? 'Demande gardée sur le téléphone : envoyée au retour du réseau.'
            : destination.validationReseau
                ? 'Demande envoyée : la Direction Générale doit la valider.'
                : 'Demande envoyée à ${destination.nom}.',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _signaler(context, messageErreurReseau(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final eleves = ref.watch(elevesTransferablesProvider((etablissementId: widget.etablissementId, texte: _texte)));
    final destinations = ref.watch(destinationsTransfertProvider(widget.etablissementId));
    final eleve = _eleve;

    return Scaffold(
      appBar: AppBar(title: const Text('Faire partir un élève')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('1. Élève', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (eleve != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(eleve.nomComplet),
                subtitle: Text([
                  if (eleve.classe != null) eleve.classe!,
                  eleve.solde > 0 ? 'reste dû ${montantReseau(eleve.solde, widget.devise)}' : 'frais soldés',
                ].join(' · ')),
                trailing: TextButton(onPressed: () => setState(() => _eleve = null), child: const Text('Changer')),
              ),
            )
          else ...[
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Nom, prénom ou matricule',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _attente?.cancel();
                _attente = Timer(const Duration(milliseconds: 400), () => setState(() => _texte = v));
              },
            ),
            ...eleves.when<List<Widget>>(
              loading: () => [const LinearProgressIndicator()],
              error: (e, _) => [Text(messageErreurReseau(e))],
              data: (liste) => [
                for (final e in liste)
                  ListTile(
                    enabled: !e.enTransfert,
                    title: Text(e.nomComplet),
                    subtitle: Text([
                      if (e.classe != null) e.classe!,
                      if (e.enTransfert) 'transfert déjà en cours',
                      if (!e.enTransfert && e.solde > 0) 'reste dû ${montantReseau(e.solde, widget.devise)}',
                    ].join(' · ')),
                    onTap: () => setState(() => _eleve = e),
                  ),
                if (liste.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Aucun élève trouvé.')),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Text('2. École d’accueil', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...destinations.when<List<Widget>>(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(messageErreurReseau(e))],
            data: (liste) => liste.isEmpty
                ? [const Text('Votre école n’appartient à aucun réseau avec d’autres écoles.')]
                : [
                    RadioGroup<String>(
                      groupValue: _destination?.etablissementId,
                      onChanged: (id) => setState(() => _destination = liste.firstWhere((d) => d.etablissementId == id)),
                      child: Column(
                        children: [
                          for (final d in liste)
                            RadioListTile<String>(
                              value: d.etablissementId,
                              title: Text(d.nom),
                              subtitle: Text([
                                if (d.ville != null) d.ville!,
                                d.reseau,
                                if (!d.transfertsOuverts) 'transferts fermés',
                              ].join(' · ')),
                            ),
                        ],
                      ),
                    ),
                  ],
          ),
          if (_destination != null && !_destination!.transfertsOuverts)
            Text('Le réseau a fermé les transferts.', style: TextStyle(color: palette.erreur)),
          if (_bloqueParSolde)
            Card(
              color: palette.erreur.withValues(alpha: 0.08),
              child: ListTile(
                leading: Icon(Icons.block, color: palette.erreur),
                title: const Text('Frais à solder avant le départ'),
                subtitle: Text('Le réseau exige des frais soldés. Reste dû : ${montantReseau(eleve!.solde, widget.devise)}.'),
              ),
            ),
          const SizedBox(height: 20),
          Text('3. Motif', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _motif,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Déménagement, rapprochement familial…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _enCours ||
                    _eleve == null ||
                    _destination == null ||
                    !_destination!.transfertsOuverts ||
                    _bloqueParSolde ||
                    _motif.text.trim().length < 3
                ? null
                : _envoyer,
            child: const Text('Demander le transfert'),
          ),
        ],
      ),
    );
  }
}
