import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/barre_actions.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../application/reseau_providers.dart';
import '../domain/reseau.dart';
import 'ecran_regles_reseau.dart';
import 'ecran_transferts_reseau.dart';
import 'elements_reseau.dart';

/// Pilotage d'un réseau par sa Direction Générale (cahier 28.2 à 28.5) :
/// tableau de bord consolidé, écoles, circulaires, calendrier commun,
/// équipe. Les observateurs consultent sans modifier.
class EcranPilotageReseau extends ConsumerWidget {
  const EcranPilotageReseau({super.key, required this.reseauId, required this.nom});

  final String reseauId;
  final String nom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reseau = ref.watch(mesReseauxProvider).valueOrNull?.where((r) => r.id == reseauId).firstOrNull;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(reseau?.nom ?? nom),
          // Actions du réseau, avec leur libellé, sous le titre (REG-28).
          bottom: BarreActions(
            actions: [
              if (reseau != null) ...[
                ActionEcran(
                  cle: const Key('reseau_regles'),
                  icone: Icons.rule_outlined,
                  libelle: 'Règles : frais et transferts',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EcranReglesReseau(
                      reseauId: reseau.id,
                      nom: reseau.nom,
                      peutRegler: reseau.estDirectionGenerale,
                      peutComposerGrille: reseau.peutPiloter,
                    ),
                  )),
                ),
                ActionEcran(
                  cle: const Key('reseau_transferts'),
                  icone: Icons.swap_horiz,
                  libelle: 'Transferts d’élèves',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EcranTransfertsReseau(
                      reseauId: reseau.id,
                      titre: 'Transferts — ${reseau.nom}',
                      peutValider: reseau.peutPiloter,
                      devise: reseau.deviseCode,
                    ),
                  )),
                ),
              ],
            ],
            sousBarre: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.insights_outlined), text: 'Tableau de bord'),
                Tab(icon: Icon(Icons.apartment_outlined), text: 'Écoles'),
                Tab(icon: Icon(Icons.campaign_outlined), text: 'Circulaires'),
                Tab(icon: Icon(Icons.event_outlined), text: 'Calendrier'),
                Tab(icon: Icon(Icons.groups_outlined), text: 'Équipe'),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            const BandeauSynchronisation(),
            Expanded(
              child: reseau == null
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _OngletTableauBord(reseau: reseau),
                        _OngletEcoles(reseau: reseau),
                        _OngletCirculaires(reseau: reseau),
                        _OngletCalendrier(reseau: reseau),
                        _OngletEquipe(reseau: reseau),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

void _signaler(BuildContext context, String texte) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));

// ---------------------------------------------------------------------------
// Tableau de bord
// ---------------------------------------------------------------------------
class _OngletTableauBord extends ConsumerWidget {
  const _OngletTableauBord({required this.reseau});

  final MonReseau reseau;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tb = ref.watch(tableauBordReseauProvider(reseau.id));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(tableauBordReseauProvider(reseau.id)),
      child: tb.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          ErreurChargementReseau(erreur: e, reessayer: () => ref.invalidate(tableauBordReseauProvider(reseau.id))),
        ]),
        data: (t) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (t.ecoles.isEmpty)
              const EtatVideReseau(
                icone: Icons.apartment_outlined,
                texte: 'Aucune école membre pour le moment.\nInvitez vos écoles depuis l’onglet « Écoles ».',
              )
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Indicateur(titre: 'Écoles', valeur: '${t.ecoles.length}', icone: Icons.apartment_outlined),
                  _Indicateur(titre: 'Élèves', valeur: '${t.effectif}', icone: Icons.groups_2_outlined),
                  _Indicateur(
                    titre: 'Recouvrement',
                    valeur: t.tauxRecouvrement == null ? '—' : '${t.tauxRecouvrement!.toStringAsFixed(1)} %',
                    icone: Icons.payments_outlined,
                    alerte: (t.tauxRecouvrement ?? 100) < 50,
                  ),
                  _Indicateur(
                    titre: 'Présence (30 j)',
                    valeur: t.tauxPresenceMoyen == null ? '—' : '${t.tauxPresenceMoyen!.toStringAsFixed(1)} %',
                    icone: Icons.fact_check_outlined,
                    alerte: (t.tauxPresenceMoyen ?? 100) < 85,
                  ),
                  _Indicateur(
                    titre: 'Alertes décrochage',
                    valeur: '${t.alertesDecrochage}',
                    icone: Icons.warning_amber_rounded,
                    alerte: t.alertesDecrochage > 0,
                  ),
                  _Indicateur(titre: 'Enseignants', valeur: '${t.enseignants}', icone: Icons.school_outlined),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Encaissé ${montantReseau(t.montantEncaisse, t.deviseCode)} sur ${montantReseau(t.montantDu, t.deviseCode)} '
                'dus pour l’année en cours. Chiffres agrégés : aucune donnée nominative d’élève ne quitte son école.',
                style: TextStyle(color: context.palette.encreSecondaire, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Text('Comparaison des écoles', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final e in t.ecoles) _CarteEcoleIndicateurs(ecole: e, devise: t.deviseCode),
            ],
          ],
        ),
      ),
    );
  }
}

class _Indicateur extends StatelessWidget {
  const _Indicateur({required this.titre, required this.valeur, required this.icone, this.alerte = false});

  final String titre;
  final String valeur;
  final IconData icone;
  final bool alerte;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final couleur = alerte ? palette.erreur : palette.primaire;
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, color: couleur),
              const SizedBox(height: 8),
              Text(valeur, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: couleur, fontWeight: FontWeight.w700)),
              Text(titre, style: TextStyle(color: palette.encreSecondaire, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarteEcoleIndicateurs extends StatelessWidget {
  const _CarteEcoleIndicateurs({required this.ecole, required this.devise});

  final IndicateursEcole ecole;
  final String devise;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final recouvrement = ecole.tauxRecouvrement;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ecole.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (ecole.ville != null) Text(ecole.ville!, style: TextStyle(color: palette.encreSecondaire, fontSize: 13)),
            if (!ecole.anneeOuverte)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Année scolaire pas encore ouverte', style: TextStyle(color: palette.accent, fontSize: 13)),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('${ecole.effectif} élèves'),
                Text('Présence : ${ecole.tauxPresence == null ? '—' : '${ecole.tauxPresence!.toStringAsFixed(1)} %'}'),
                Text('Décrochage : ${ecole.alertesDecrochage}'),
                Text('${ecole.enseignants} enseignants'
                    '${ecole.elevesParEnseignant == null ? '' : ' (${ecole.elevesParEnseignant!.toStringAsFixed(0)} élèves/ens.)'}'),
              ],
            ),
            const SizedBox(height: 10),
            if (recouvrement != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (recouvrement / 100).clamp(0.0, 1.0).toDouble(),
                  minHeight: 8,
                  color: recouvrement < 50 ? palette.erreur : palette.succes,
                  backgroundColor: palette.bordure,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Recouvrement ${recouvrement.toStringAsFixed(1)} % — ${montantReseau(ecole.montantEncaisse, devise)} '
                'sur ${montantReseau(ecole.montantDu, devise)}',
                style: TextStyle(fontSize: 13, color: palette.encreSecondaire),
              ),
            ] else
              Text('Tarifs non renseignés', style: TextStyle(fontSize: 13, color: palette.encreSecondaire)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Écoles
// ---------------------------------------------------------------------------
class _OngletEcoles extends ConsumerWidget {
  const _OngletEcoles({required this.reseau});

  final MonReseau reseau;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ecoles = [...reseau.ecoles]..sort((a, b) => a.nom.compareTo(b.nom));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (reseau.peutPiloter)
          FilledButton.icon(
            key: const Key('bouton_inviter_ecole'),
            onPressed: () async {
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _RechercheEcole(reseauId: reseau.id),
              );
              ref.invalidate(mesReseauxProvider);
            },
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Inviter une école'),
          ),
        const SizedBox(height: 12),
        if (ecoles.isEmpty)
          const EtatVideReseau(icone: Icons.apartment_outlined, texte: 'Aucune école invitée pour le moment.'),
        for (final e in ecoles)
          Card(
            child: ListTile(
              title: Text(e.nom),
              subtitle: Text([
                if (e.ville != null) e.ville!,
                if (e.retraitMotif != null && e.statut == 'retrait_demande') 'Motif : ${e.retraitMotif}',
              ].join(' · ')),
              trailing: StatutEcole(statut: e.statut, libelle: e.libelleStatut),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Une école quitte le réseau sur sa demande, avec l’accord de Global Service Groupe.',
          style: TextStyle(color: context.palette.encreSecondaire, fontSize: 13),
        ),
      ],
    );
  }
}

class _RechercheEcole extends ConsumerStatefulWidget {
  const _RechercheEcole({required this.reseauId});

  final String reseauId;

  @override
  ConsumerState<_RechercheEcole> createState() => _RechercheEcoleState();
}

class _RechercheEcoleState extends ConsumerState<_RechercheEcole> {
  final _texte = TextEditingController();
  Timer? _attente;
  List<EcoleDuReseau> _resultats = const [];
  bool _charge = false;
  String? _erreur;
  final Set<String> _invitees = {};

  @override
  void dispose() {
    _attente?.cancel();
    _texte.dispose();
    super.dispose();
  }

  void _chercher(String v) {
    _attente?.cancel();
    _attente = Timer(const Duration(milliseconds: 350), () async {
      if (v.trim().length < 2) {
        setState(() => _resultats = const []);
        return;
      }
      setState(() {
        _charge = true;
        _erreur = null;
      });
      try {
        final r = await ref.read(reseauRepositoryProvider).rechercherEtablissements(widget.reseauId, v.trim());
        if (mounted) setState(() => _resultats = r);
      } catch (e) {
        if (mounted) setState(() => _erreur = messageErreurReseau(e));
      } finally {
        if (mounted) setState(() => _charge = false);
      }
    });
  }

  Future<void> _inviter(EcoleDuReseau e) async {
    try {
      await ref.read(reseauRepositoryProvider).inviter(widget.reseauId, e.etablissementId);
      if (!mounted) return;
      setState(() => _invitees.add(e.etablissementId));
      _signaler(context, 'Invitation envoyée à ${e.nom}.');
    } catch (err) {
      if (mounted) setState(() => _erreur = messageErreurReseau(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Annuaire des établissements', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                key: const Key('champ_recherche_ecole'),
                controller: _texte,
                autofocus: true,
                onChanged: _chercher,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Nom ou ville (accents facultatifs)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_charge) const LinearProgressIndicator(),
              if (_erreur != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erreur!, style: TextStyle(color: palette.erreur))),
              Expanded(
                child: ListView(
                  children: [
                    for (final e in _resultats)
                      ListTile(
                        title: Text(e.nom),
                        subtitle: Text(e.ville ?? ''),
                        trailing: _invitees.contains(e.etablissementId) || e.statut == 'invite'
                            ? const StatutEcole(statut: 'invite', libelle: 'Invitée')
                            : e.statut == 'membre' || e.statut == 'retrait_demande'
                                ? const StatutEcole(statut: 'membre', libelle: 'Membre')
                                : TextButton(onPressed: () => _inviter(e), child: const Text('Inviter')),
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

// ---------------------------------------------------------------------------
// Circulaires
// ---------------------------------------------------------------------------
class _OngletCirculaires extends ConsumerWidget {
  const _OngletCirculaires({required this.reseau});

  final MonReseau reseau;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circulaires = ref.watch(circulairesReseauProvider(reseau.id));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(circulairesReseauProvider(reseau.id)),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (reseau.peutPiloter)
            FilledButton.icon(
              key: const Key('bouton_nouvelle_circulaire'),
              onPressed: () => showDialog<void>(context: context, builder: (_) => _RedactionCirculaire(reseauId: reseau.id)),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Nouvelle circulaire'),
            ),
          const SizedBox(height: 12),
          ...circulaires.when<List<Widget>>(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (e, _) => [
              ErreurChargementReseau(erreur: e, reessayer: () => ref.invalidate(circulairesReseauProvider(reseau.id))),
            ],
            data: (liste) => liste.isEmpty
                ? [const EtatVideReseau(icone: Icons.campaign_outlined, texte: 'Aucune circulaire publiée.')]
                : [for (final c in liste) CarteCirculaire(circulaire: c)],
          ),
        ],
      ),
    );
  }
}

class CarteCirculaire extends StatelessWidget {
  const CarteCirculaire({super.key, required this.circulaire, this.surOuverture});

  final CirculaireReseau circulaire;
  final VoidCallback? surOuverture;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = circulaire;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        onExpansionChanged: (ouvert) {
          if (ouvert) surOuverture?.call();
        },
        leading: Icon(
          c.importante ? Icons.priority_high_rounded : Icons.campaign_outlined,
          color: c.importante ? palette.erreur : palette.primaire,
        ),
        title: Text(c.titre, style: TextStyle(fontWeight: c.lue ? FontWeight.normal : FontWeight.w700)),
        subtitle: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(dateCourte(c.publieeLe)),
            if (c.lectures != null && c.destinataires != null) Text('Lue par ${c.lectures}/${c.destinataires}'),
            if (c.enAttenteEnvoi) const PastilleEnAttente(),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [SelectableText(c.corps)],
      ),
    );
  }
}

class _RedactionCirculaire extends ConsumerStatefulWidget {
  const _RedactionCirculaire({required this.reseauId});

  final String reseauId;

  @override
  ConsumerState<_RedactionCirculaire> createState() => _RedactionCirculaireState();
}

class _RedactionCirculaireState extends ConsumerState<_RedactionCirculaire> {
  final _titre = TextEditingController();
  final _corps = TextEditingController();
  bool _importante = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _titre.dispose();
    _corps.dispose();
    super.dispose();
  }

  Future<void> _publier() async {
    if (_titre.text.trim().length < 3 || _corps.text.trim().length < 3) {
      setState(() => _erreur = 'Titre et texte requis.');
      return;
    }
    setState(() => _enCours = true);
    try {
      final recue = await ref.read(reseauRepositoryProvider).publierCirculaire(
            reseauId: widget.reseauId,
            titre: _titre.text.trim(),
            corps: _corps.text.trim(),
            importante: _importante,
          );
      ref.invalidate(circulairesReseauProvider(widget.reseauId));
      if (!mounted) return;
      Navigator.of(context).pop();
      _signaler(context, recue
          ? 'Circulaire envoyée aux directions des écoles membres.'
          : 'Circulaire gardée sur le téléphone : elle partira au retour du réseau.');
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreurReseau(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle circulaire'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titre,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Titre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _corps,
              maxLines: 8,
              maxLength: 4000,
              decoration: const InputDecoration(labelText: 'Texte', border: OutlineInputBorder()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _importante,
              onChanged: (v) => setState(() => _importante = v),
              title: const Text('Importante'),
              subtitle: const Text('Signalée en tête de la notification'),
            ),
            if (_erreur != null) Text(_erreur!, style: TextStyle(color: context.palette.erreur)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _enCours ? null : () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _enCours ? null : _publier, child: const Text('Publier')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Calendrier commun
// ---------------------------------------------------------------------------
class _OngletCalendrier extends ConsumerWidget {
  const _OngletCalendrier({required this.reseau});

  final MonReseau reseau;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ({String reseauId, String? etablissementId}) cle = (reseauId: reseau.id, etablissementId: null);
    final evenements = ref.watch(evenementsReseauProvider(cle));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(evenementsReseauProvider(cle)),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (reseau.peutPiloter)
            FilledButton.icon(
              key: const Key('bouton_nouvel_evenement'),
              onPressed: () => showDialog<void>(context: context, builder: (_) => _SaisieEvenement(reseauId: reseau.id)),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une date commune'),
            ),
          const SizedBox(height: 4),
          Text(
            'Rentrée, congés, examens : chaque école choisit de les ajouter à son agenda.',
            style: TextStyle(color: context.palette.encreSecondaire, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ...evenements.when<List<Widget>>(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (e, _) => [ErreurChargementReseau(erreur: e, reessayer: () => ref.invalidate(evenementsReseauProvider(cle)))],
            data: (liste) => liste.isEmpty
                ? [const EtatVideReseau(icone: Icons.event_outlined, texte: 'Aucune date commune.')]
                : [
                    for (final e in liste)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.event_outlined),
                          title: Text(e.titre),
                          subtitle: Wrap(
                            spacing: 8,
                            children: [
                              Text('${e.libelleType} · ${periode(e.debut, e.fin)}'),
                              if (e.enAttenteEnvoi) const PastilleEnAttente(),
                            ],
                          ),
                          trailing: reseau.peutPiloter && !e.enAttenteEnvoi
                              ? IconButton(
                                  tooltip: 'Supprimer',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    try {
                                      await ref.read(reseauRepositoryProvider).supprimerEvenement(e.id);
                                      ref.invalidate(evenementsReseauProvider(cle));
                                    } catch (err) {
                                      if (context.mounted) _signaler(context, messageErreurReseau(err));
                                    }
                                  },
                                )
                              : null,
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

class _SaisieEvenement extends ConsumerStatefulWidget {
  const _SaisieEvenement({required this.reseauId});

  final String reseauId;

  @override
  ConsumerState<_SaisieEvenement> createState() => _SaisieEvenementState();
}

class _SaisieEvenementState extends ConsumerState<_SaisieEvenement> {
  final _titre = TextEditingController();
  String _type = 'conges';
  DateTimeRange? _periode;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _titre.dispose();
    super.dispose();
  }

  Future<void> _choisirDates() async {
    final maintenant = DateTime.now();
    final choix = await showDateRangePicker(
      context: context,
      firstDate: DateTime(maintenant.year - 1),
      lastDate: DateTime(maintenant.year + 2),
      initialDateRange: _periode,
      helpText: 'Période',
    );
    if (choix != null) setState(() => _periode = choix);
  }

  Future<void> _enregistrer() async {
    final p = _periode;
    if (_titre.text.trim().length < 3 || p == null) {
      setState(() => _erreur = 'Titre et dates requis.');
      return;
    }
    setState(() => _enCours = true);
    try {
      final recu = await ref.read(reseauRepositoryProvider).enregistrerEvenement(
            reseauId: widget.reseauId,
            titre: _titre.text.trim(),
            type: _type,
            debut: p.start,
            fin: p.end,
          );
      ref.invalidate(evenementsReseauProvider((reseauId: widget.reseauId, etablissementId: null)));
      if (!mounted) return;
      Navigator.of(context).pop();
      _signaler(context, recu ? 'Date ajoutée au calendrier du réseau.' : 'Date gardée : elle partira au retour du réseau.');
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreurReseau(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _periode;
    return AlertDialog(
      title: const Text('Date commune'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titre,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Intitulé', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: [for (final t in typesEvenementReseau.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
            onChanged: (v) => setState(() => _type = v ?? 'autre'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _choisirDates,
            icon: const Icon(Icons.date_range_outlined),
            label: Text(p == null ? 'Choisir les dates' : periode(p.start, p.end)),
          ),
          if (_erreur != null) Text(_erreur!, style: TextStyle(color: context.palette.erreur)),
        ],
      ),
      actions: [
        TextButton(onPressed: _enCours ? null : () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _enCours ? null : _enregistrer, child: const Text('Enregistrer')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Équipe et dissolution
// ---------------------------------------------------------------------------
class _OngletEquipe extends ConsumerWidget {
  const _OngletEquipe({required this.reseau});

  final MonReseau reseau;

  Future<void> _nommer(BuildContext context, WidgetRef ref) async {
    final identifiant = TextEditingController();
    var role = 'adjoint';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Ajouter un responsable'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: identifiant,
                decoration: const InputDecoration(
                  labelText: 'Courriel ou téléphone du compte',
                  helperText: 'La personne doit déjà avoir un compte EcoShop',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Rôle', border: OutlineInputBorder()),
                items: [for (final r in rolesReseau.entries) DropdownMenuItem(value: r.key, child: Text(r.value))],
                onChanged: (v) => setState(() => role = v ?? 'adjoint'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    // Pas de dispose() ici : la boîte se referme encore (animation) et
    // utilise le champ ; le contrôleur est simplement abandonné.
    final valeur = identifiant.text.trim();
    if (ok != true || valeur.isEmpty) return;
    try {
      await ref.read(reseauRepositoryProvider).nommerResponsable(reseau.id, valeur, role);
      ref.invalidate(mesReseauxProvider);
      if (context.mounted) _signaler(context, 'Responsable ajouté.');
    } catch (e) {
      if (context.mounted) _signaler(context, messageErreurReseau(e));
    }
  }

  Future<void> _dissoudre(BuildContext context, WidgetRef ref) async {
    final nom = await doubleConfirmation(
      context,
      titre: 'Dissoudre le réseau',
      explication: 'La dissolution met fin au réseau « ${reseau.nom} » : toutes les écoles en sont retirées, '
          'le tableau de bord, les circulaires et le calendrier commun ne sont plus accessibles. '
          'Les écoles gardent toutes leurs données. Ce n’est pas un simple retrait d’école.',
      consigne: 'Pour confirmer, saisissez le nom exact du réseau :',
      attendu: reseau.nom,
      libelleAction: 'Dissoudre définitivement',
    );
    if (nom == null) return;
    try {
      await ref.read(reseauRepositoryProvider).dissoudre(reseau.id, nom);
      ref.invalidate(mesReseauxProvider);
      if (context.mounted) {
        Navigator.of(context).pop();
        _signaler(context, 'Le réseau « ${reseau.nom} » est dissous.');
      }
    } catch (e) {
      if (context.mounted) _signaler(context, messageErreurReseau(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (reseau.estDirectionGenerale)
          FilledButton.icon(
            onPressed: () => _nommer(context, ref),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Ajouter un responsable'),
          ),
        const SizedBox(height: 12),
        for (final r in reseau.responsables)
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(r.nom),
              subtitle: Text(rolesReseau[r.role] ?? r.role),
              trailing: reseau.estDirectionGenerale
                  ? IconButton(
                      tooltip: 'Retirer',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () async {
                        try {
                          await ref.read(reseauRepositoryProvider).retirerResponsable(reseau.id, r.profileId);
                          ref.invalidate(mesReseauxProvider);
                        } catch (e) {
                          if (context.mounted) _signaler(context, messageErreurReseau(e));
                        }
                      },
                    )
                  : null,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Adjoint : pilote le réseau (écoles, circulaires, calendrier). Observateur : consulte le tableau de bord.',
          style: TextStyle(color: palette.encreSecondaire, fontSize: 13),
        ),
        if (reseau.estDirectionGenerale) ...[
          const SizedBox(height: 32),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: palette.erreur),
            onPressed: () => _dissoudre(context, ref),
            icon: const Icon(Icons.dangerous_outlined),
            label: const Text('Dissoudre le réseau'),
          ),
        ],
      ],
    );
  }
}
