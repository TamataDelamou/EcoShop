import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../export_pdf/data/recu_don_pdf_builder.dart';
import '../../export_pdf/presentation/ecran_apercu_pdf.dart';
import '../../themes/application/theme_providers.dart';
import '../application/dons_providers.dart';
import '../domain/comptabilisation_automatique.dart';
import '../domain/dons.dart';
import '../domain/montant_en_lettres.dart';
import '../domain/pieces_comptables.dart';

/// Dons et donateurs (REG-03 C5) : synthèse de l'année, dons avec reçus
/// numérotés, registre des donateurs, campagnes et projets à fonds
/// affectés. Chaque don passe tout seul en comptabilité (SYCEBNL : 704x,
/// fonds affectés en 165).
class EcranDons extends ConsumerStatefulWidget {
  const EcranDons({super.key, required this.etablissementId, this.annee});

  final String etablissementId;

  /// Année affichée (par défaut l'année en cours).
  final int? annee;

  @override
  ConsumerState<EcranDons> createState() => _EcranDonsState();
}

class _EcranDonsState extends ConsumerState<EcranDons> {
  late int _annee = widget.annee ?? DateTime.now().year;

  CleAnnee get _cle => (etablissementId: widget.etablissementId, annee: _annee);

  void _rafraichir() {
    ref.invalidate(tableauBordDonsProvider(_cle));
    ref.invalidate(listeDonsProvider(_cle));
    ref.invalidate(donateursProvider(widget.etablissementId));
    ref.invalidate(affectationsDonsProvider(widget.etablissementId));
  }

  void _message(String texte) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  Future<void> _nouveauDon() async {
    final resultat = await Navigator.of(context).push<ResultatDon>(MaterialPageRoute(
      builder: (_) => EcranSaisieDon(etablissementId: widget.etablissementId),
    ));
    if (resultat == null || !mounted) return;
    _rafraichir();
    final incident = resultat.incident == null
        ? ''
        : ' Comptabilité : ${IncidentComptabilisation(id: '', code: resultat.incident!, operation: 'comptabilisation', le: DateTime.now(), sourceType: 'don').explication}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text('Don enregistré — reçu ${resultat.numeroRecu}.$incident'),
      action: SnackBarAction(label: 'Reçu', onPressed: () => _imprimerRecu(resultat.id)),
    ));
  }

  Future<void> _imprimerRecu(String donId) async {
    final etablissement = ref.read(etablissementActifProvider);
    if (etablissement == null) return;
    try {
      final recu = await ref.read(donsRepositoryProvider).recu(donId);
      final octets = await construireRecuDonPdf(
        recu: recu,
        etablissement: etablissement,
        variante: ref.read(themeVariantProvider),
        identite: await ref.read(identitePdfProvider.future),
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EcranApercuPdf(titre: 'Reçu ${recu.numeroRecu}', octets: octets, nomFichier: 'recu-${recu.numeroRecu}.pdf'),
      ));
    } on ErreurDons catch (e) {
      _message(e.messageUtilisateur);
    }
  }

  Future<void> _imprimerReleve(Donateur donateur) async {
    final etablissement = ref.read(etablissementActifProvider);
    if (etablissement == null || donateur.id == null) return;
    try {
      final releve = await ref.read(donsRepositoryProvider).releve(donateur.id!, _annee);
      final octets = await construireReleveDonateurPdf(
        releve: releve,
        etablissement: etablissement,
        variante: ref.read(themeVariantProvider),
        identite: await ref.read(identitePdfProvider.future),
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EcranApercuPdf(
          titre: 'Relevé $_annee — ${donateur.nomComplet}',
          octets: octets,
          nomFichier: 'releve-dons-$_annee.pdf',
        ),
      ));
    } on ErreurDons catch (e) {
      _message(e.messageUtilisateur);
    }
  }

  Future<void> _annulerDon(Don don) async {
    final motif = await showDialog<String>(
      context: context,
      builder: (_) => DialogueTexte(
        titre: 'Annuler le reçu ${don.numeroRecu} ?',
        aide: 'Le don reste au registre, marqué annulé ; son écriture est contre-passée. '
            'Pour corriger une erreur, annulez puis ressaisissez.',
        libelle: 'Motif de l\'annulation',
        bouton: 'Annuler le don',
        cle: 'motif_annulation_don',
      ),
    );
    if (motif == null) return;
    try {
      await ref.read(donsRepositoryProvider).annulerDon(don.id, motif);
      _rafraichir();
      _message('Reçu ${don.numeroRecu} annulé.');
    } on ErreurDons catch (e) {
      _message(e.messageUtilisateur);
    }
  }

  Future<void> _editerDonateur([Donateur? donateur]) async {
    final saisi = await showDialog<Donateur>(
      context: context,
      builder: (_) => DialogueDonateur(etablissementId: widget.etablissementId, donateur: donateur),
    );
    if (saisi == null) return;
    try {
      await ref.read(donsRepositoryProvider).enregistrerDonateur(saisi);
      ref.invalidate(donateursProvider(widget.etablissementId));
    } on ErreurDons catch (e) {
      _message(e.messageUtilisateur);
    }
  }

  Future<void> _engagement(Donateur donateur, List<AffectationDon> campagnes) async {
    final e = await showDialog<({double montant, String periodicite, String? affectationId})>(
      context: context,
      builder: (_) => DialogueEngagement(donateur: donateur, campagnes: campagnes),
    );
    if (e == null) return;
    try {
      await ref.read(donsRepositoryProvider).enregistrerEngagement(
            etablissementId: widget.etablissementId,
            donateurId: donateur.id!,
            affectationId: e.affectationId,
            montant: e.montant,
            periodicite: e.periodicite,
            dateDebut: DateTime.now(),
          );
      ref.invalidate(tableauBordDonsProvider(_cle));
      _message('Engagement enregistré : il apparaît dans la synthèse.');
    } on ErreurDons catch (err) {
      _message(err.messageUtilisateur);
    }
  }

  Future<void> _archiver(Donateur donateur) async {
    try {
      await ref.read(donsRepositoryProvider).archiverDonateur(donateur.id!);
      ref.invalidate(donateursProvider(widget.etablissementId));
    } on ErreurDons catch (e) {
      _message(e.messageUtilisateur);
    }
  }

  Future<void> _editerCampagne([AffectationDon? campagne]) async {
    final saisie = await showDialog<AffectationDon>(
      context: context,
      builder: (_) => DialogueCampagne(etablissementId: widget.etablissementId, campagne: campagne),
    );
    if (saisie == null) return;
    try {
      await ref.read(donsRepositoryProvider).enregistrerAffectation(saisie);
      _rafraichir();
    } on ErreurDons catch (e) {
      _message(e.messageUtilisateur);
    }
  }

  Future<void> _employer(SuiviAffectation projet) async {
    final saisie = await showDialog<({double montant, String libelle})>(
      context: context,
      builder: (_) => DialogueEmploi(projet: projet),
    );
    if (saisie == null) return;
    try {
      final solde = await ref.read(donsRepositoryProvider).constaterEmploi(
            affectationId: projet.id,
            montant: saisie.montant,
            libelle: saisie.libelle,
            date: DateTime.now(),
          );
      ref.invalidate(tableauBordDonsProvider(_cle));
      _message('Emploi enregistré. Reste disponible : ${formaterMontant(solde)}.');
    } on ErreurDons catch (e) {
      _message(e.messageUtilisateur);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anneeCourante = DateTime.now().year;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dons et donateurs'),
          actions: [
            DropdownButton<int>(
              key: const Key('annee_dons'),
              value: _annee,
              underline: const SizedBox(),
              items: [
                for (var a = anneeCourante; a >= anneeCourante - 4; a--) DropdownMenuItem(value: a, child: Text('$a')),
              ],
              onChanged: (a) => setState(() => _annee = a ?? _annee),
            ),
            const SizedBox(width: 12),
          ],
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Synthèse'),
            Tab(text: 'Dons'),
            Tab(text: 'Donateurs'),
            Tab(text: 'Campagnes'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('nouveau_don'),
          onPressed: _nouveauDon,
          icon: const Icon(Icons.volunteer_activism_outlined),
          label: const Text('Nouveau don'),
        ),
        body: TabBarView(children: [
          _OngletSynthese(cle: _cle, onEmployer: _employer),
          _OngletDons(cle: _cle, onRecu: _imprimerRecu, onAnnuler: _annulerDon),
          _OngletDonateurs(
            etablissementId: widget.etablissementId,
            annee: _annee,
            onEditer: _editerDonateur,
            onReleve: _imprimerReleve,
            onEngagement: _engagement,
            onArchiver: _archiver,
          ),
          _OngletCampagnes(etablissementId: widget.etablissementId, onEditer: _editerCampagne),
        ]),
      ),
    );
  }
}

Widget _chargement() =>
    ListView(padding: const EdgeInsets.all(16), children: List.generate(3, (_) => const ShimmerCarteListe()));

Widget _erreur(Object e) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(e is ErreurDons ? e.messageUtilisateur : 'Indisponible hors connexion pour le moment.',
            textAlign: TextAlign.center),
      ),
    );

// ---------------------------------------------------------------------------
// Synthèse
// ---------------------------------------------------------------------------
class _OngletSynthese extends ConsumerWidget {
  const _OngletSynthese({required this.cle, required this.onEmployer});

  final CleAnnee cle;
  final void Function(SuiviAffectation) onEmployer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tb = ref.watch(tableauBordDonsProvider(cle));
    final palette = context.palette;
    final titre = Theme.of(context).textTheme.titleMedium;
    return tb.when(
      loading: _chargement,
      error: (e, _) => _erreur(e),
      data: (t) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(tableauBordDonsProvider(cle)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Dons reçus en ${t.annee}', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(formaterMontant(t.total),
                      key: const Key('total_dons'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: palette.primaire)),
                  if (t.evolution != null)
                    Text(
                      '${t.evolution! >= 0 ? '+' : ''}${(t.evolution! * 100).round()} % par rapport à ${t.annee - 1} '
                      '(${formaterMontant(t.totalAnneePrecedente)})',
                      style: TextStyle(color: t.evolution! >= 0 ? palette.primaire : palette.accent),
                    ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _Pastille('${t.nombreDons} don(s)'),
                    _Pastille('${t.nombreDonateurs} donateur(s)'),
                    _Pastille('${t.nouveauxDonateurs} nouveau(x)', cle: const Key('nouveaux_donateurs')),
                    _Pastille('${t.donateursFideles} fidèle(s)'),
                  ]),
                ]),
              ),
            ),
            if (t.parNature.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Par nature', style: titre),
              Card(
                child: Column(children: [
                  for (final n in t.parNature)
                    ListTile(
                      dense: true,
                      title: Text(n.nature.libelle),
                      subtitle: Text('${n.nombre} don(s)'),
                      trailing: Text(formaterMontant(n.montant)),
                    ),
                ]),
              ),
            ],
            if (t.affectations.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Campagnes et projets', style: titre),
              for (final a in t.affectations)
                Card(
                  key: Key('campagne_${a.libelle}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(a.libelle, style: Theme.of(context).textTheme.titleSmall)),
                        if (!a.active) const Text('close'),
                      ]),
                      Text(a.type.libelle, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 6),
                      if (a.progression != null) ...[
                        LinearProgressIndicator(value: a.progression),
                        const SizedBox(height: 4),
                        Text('${formaterMontant(a.collecte)} sur ${formaterMontant(a.objectif!)} '
                            '(${(a.progression! * 100).round()} %) · ${a.donateurs} donateur(s)'),
                      ] else
                        Text('${formaterMontant(a.collecte)} collectés · ${a.donateurs} donateur(s)'),
                      if (a.type == TypeAffectation.projet) ...[
                        Text('Employé : ${formaterMontant(a.emploie)} · disponible : ${formaterMontant(a.disponible)}',
                            key: Key('disponible_${a.libelle}')),
                        if (a.disponible > 0)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: Key('employer_${a.libelle}'),
                              onPressed: () => onEmployer(a),
                              icon: const Icon(Icons.shopping_cart_checkout_outlined),
                              label: const Text('Employer des fonds'),
                            ),
                          ),
                      ],
                    ]),
                  ),
                ),
            ],
            if (t.engagementsEnRetard.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Engagements en retard', style: titre),
              Card(
                child: Column(children: [
                  for (final e in t.engagementsEnRetard)
                    ListTile(
                      key: Key('engagement_${e.donateur}'),
                      leading: Icon(Icons.schedule_outlined, color: palette.accent),
                      title: Text(e.donateur),
                      subtitle: Text([
                        '${formaterMontant(e.montant)} ${e.periodiciteLibelle}',
                        if (e.eleve != null) 'pour ${e.eleve}',
                        if (e.affectation != null) e.affectation!,
                      ].join(' · ')),
                      trailing: Text('− ${formaterMontant(e.retard)}', style: TextStyle(color: palette.accent)),
                    ),
                ]),
              ),
            ],
            if (t.aRelancer.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('À remercier et relancer', style: titre),
              Text('Ont donné en ${t.annee - 1}, pas encore en ${t.annee}, et acceptent d\'être contactés.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.encreSecondaire)),
              Card(
                child: Column(children: [
                  for (final r in t.aRelancer)
                    ListTile(
                      key: Key('relancer_${r.nom}'),
                      leading: const Icon(Icons.favorite_border),
                      title: Text(r.nom),
                      subtitle: Text('${t.annee - 1} : ${formaterMontant(r.montantAnneePrecedente)}'),
                      trailing: r.telephone == null
                          ? null
                          : IconButton(
                              tooltip: 'Copier le numéro',
                              icon: const Icon(Icons.copy_outlined),
                              onPressed: () => Clipboard.setData(ClipboardData(text: r.telephone!)),
                            ),
                    ),
                ]),
              ),
            ],
            if (t.meilleursDonateurs.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Principaux donateurs', style: titre),
              Card(
                child: Column(children: [
                  for (final m in t.meilleursDonateurs)
                    ListTile(dense: true, title: Text(m.nom), trailing: Text(formaterMontant(m.montant))),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille(this.texte, {this.cle});

  final String texte;
  final Key? cle;

  @override
  Widget build(BuildContext context) => Chip(key: cle, label: Text(texte), visualDensity: VisualDensity.compact);
}

// ---------------------------------------------------------------------------
// Dons
// ---------------------------------------------------------------------------
class _OngletDons extends ConsumerWidget {
  const _OngletDons({required this.cle, required this.onRecu, required this.onAnnuler});

  final CleAnnee cle;
  final void Function(String donId) onRecu;
  final void Function(Don don) onAnnuler;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dons = ref.watch(listeDonsProvider(cle));
    return dons.when(
      loading: _chargement,
      error: (e, _) => _erreur(e),
      data: (liste) => liste.isEmpty
          ? Center(child: Text('Aucun don en ${cle.annee}.'))
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: liste.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final d = liste[i];
                final barre = d.annule ? const TextStyle(decoration: TextDecoration.lineThrough) : null;
                return ListTile(
                  key: Key('don_${d.numeroRecu}'),
                  title: Text(d.donateurAffiche, style: barre),
                  subtitle: Text([
                    d.numeroRecu,
                    dateCourte(d.dateDon),
                    d.nature.libelle,
                    if (d.affectation != null) d.affectation!,
                    if (d.annule) 'ANNULÉ',
                  ].join(' · ')),
                  trailing: Text(formaterMontant(d.montant), style: barre),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (context) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(
                          title: Text('Reçu ${d.numeroRecu}', style: Theme.of(context).textTheme.titleMedium),
                          subtitle: d.annule && d.motifAnnulation != null ? Text('Annulé : ${d.motifAnnulation}') : null,
                        ),
                        ListTile(
                          key: const Key('action_recu'),
                          leading: const Icon(Icons.picture_as_pdf_outlined),
                          title: const Text('Voir et imprimer le reçu'),
                          onTap: () {
                            Navigator.of(context).pop();
                            onRecu(d.id);
                          },
                        ),
                        if (!d.annule)
                          ListTile(
                            key: const Key('action_annuler_don'),
                            leading: Icon(Icons.block_outlined, color: Theme.of(context).colorScheme.error),
                            title: const Text('Annuler ce don'),
                            onTap: () {
                              Navigator.of(context).pop();
                              onAnnuler(d);
                            },
                          ),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Donateurs
// ---------------------------------------------------------------------------
class _OngletDonateurs extends ConsumerWidget {
  const _OngletDonateurs({
    required this.etablissementId,
    required this.annee,
    required this.onEditer,
    required this.onReleve,
    required this.onEngagement,
    required this.onArchiver,
  });

  final String etablissementId;
  final int annee;
  final void Function([Donateur?]) onEditer;
  final void Function(Donateur) onReleve;
  final void Function(Donateur, List<AffectationDon>) onEngagement;
  final void Function(Donateur) onArchiver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donateurs = ref.watch(donateursProvider(etablissementId));
    final campagnes = ref.watch(affectationsDonsProvider(etablissementId)).value ?? const <AffectationDon>[];
    return donateurs.when(
      loading: _chargement,
      error: (e, _) => _erreur(e),
      data: (liste) => ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ListTile(
            key: const Key('ajouter_donateur'),
            leading: const Icon(Icons.person_add_alt_outlined),
            title: const Text('Ajouter un donateur'),
            onTap: () => onEditer(),
          ),
          const Divider(height: 1),
          for (final d in liste)
            ListTile(
              key: Key('donateur_${d.nom}'),
              leading: Icon(switch (d.type) {
                TypeDonateur.personne => Icons.person_outline,
                TypeDonateur.organisation => Icons.business_outlined,
                TypeDonateur.eglise => Icons.church_outlined,
              }),
              title: Text(d.nomComplet),
              subtitle: Text([
                d.type.libelle,
                if (d.telephone != null) d.telephone!,
                if (!d.accepteContact) 'ne pas contacter',
              ].join(' · ')),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                builder: (context) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(title: Text(d.nomComplet, style: Theme.of(context).textTheme.titleMedium)),
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Modifier'),
                      onTap: () {
                        Navigator.of(context).pop();
                        onEditer(d);
                      },
                    ),
                    ListTile(
                      key: const Key('action_releve'),
                      leading: const Icon(Icons.summarize_outlined),
                      title: Text('Relevé des dons $annee (PDF)'),
                      onTap: () {
                        Navigator.of(context).pop();
                        onReleve(d);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.event_repeat_outlined),
                      title: const Text('Engagement régulier (parrainage, promesse)'),
                      onTap: () {
                        Navigator.of(context).pop();
                        onEngagement(d, campagnes);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.archive_outlined),
                      title: const Text('Archiver'),
                      onTap: () {
                        Navigator.of(context).pop();
                        onArchiver(d);
                      },
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Campagnes
// ---------------------------------------------------------------------------
class _OngletCampagnes extends ConsumerWidget {
  const _OngletCampagnes({required this.etablissementId, required this.onEditer});

  final String etablissementId;
  final void Function([AffectationDon?]) onEditer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campagnes = ref.watch(affectationsDonsProvider(etablissementId));
    return campagnes.when(
      loading: _chargement,
      error: (e, _) => _erreur(e),
      data: (liste) => ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ListTile(
            key: const Key('ajouter_campagne'),
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Nouvelle campagne ou nouveau projet'),
            onTap: () => onEditer(),
          ),
          const Divider(height: 1),
          for (final c in liste)
            ListTile(
              title: Text(c.libelle),
              subtitle: Text([
                c.type.libelle,
                if (c.objectif != null) 'objectif ${formaterMontant(c.objectif!)}',
                if (!c.active) 'close',
              ].join(' · ')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => onEditer(c),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saisie d'un don
// ---------------------------------------------------------------------------
class EcranSaisieDon extends ConsumerStatefulWidget {
  const EcranSaisieDon({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<EcranSaisieDon> createState() => _EcranSaisieDonState();
}

class _EcranSaisieDonState extends ConsumerState<EcranSaisieDon> {
  final _montant = TextEditingController();
  final _reference = TextEditingController();
  final _commentaire = TextEditingController();
  NatureDon _nature = NatureDon.don;
  MoyenDon _moyen = MoyenDon.especes;
  DateTime _date = DateTime.now();
  String? _donateurId;
  String? _affectationId;
  bool _anonyme = false;
  bool _enCours = false;

  @override
  void dispose() {
    _montant.dispose();
    _reference.dispose();
    _commentaire.dispose();
    super.dispose();
  }

  double? get _valeur => double.tryParse(_montant.text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));

  Future<void> _choisirDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _nouveauDonateur() async {
    final saisi = await showDialog<Donateur>(
      context: context,
      builder: (_) => DialogueDonateur(etablissementId: widget.etablissementId),
    );
    if (saisi == null) return;
    try {
      final id = await ref.read(donsRepositoryProvider).enregistrerDonateur(saisi);
      ref.invalidate(donateursProvider(widget.etablissementId));
      if (mounted) setState(() => _donateurId = id);
    } on ErreurDons catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    }
  }

  Future<void> _enregistrer() async {
    final montant = _valeur;
    if (montant == null || montant <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Indiquez un montant supérieur à zéro.')));
      return;
    }
    setState(() => _enCours = true);
    try {
      final r = await ref.read(donsRepositoryProvider).enregistrerDon(SaisieDon(
            etablissementId: widget.etablissementId,
            montant: montant,
            nature: _nature,
            moyen: _moyen,
            date: _date,
            donateurId: _donateurId,
            affectationId: _affectationId,
            reference: _reference.text,
            commentaire: _commentaire.text,
            anonyme: _anonyme,
          ));
      if (mounted) Navigator.of(context).pop(r);
    } on ErreurDons catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final donateurs = ref.watch(donateursProvider(widget.etablissementId)).value ?? const <Donateur>[];
    final campagnes = [
      for (final c in ref.watch(affectationsDonsProvider(widget.etablissementId)).value ?? const <AffectationDon>[])
        if (c.active) c,
    ];
    final campagne = campagnes.where((c) => c.id == _affectationId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau don')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('montant_don'),
            controller: _montant,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Montant', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<NatureDon>(
            key: const Key('nature_don'),
            initialValue: _nature,
            decoration: const InputDecoration(labelText: 'Nature', border: OutlineInputBorder()),
            items: [for (final n in NatureDon.values) DropdownMenuItem(value: n, child: Text(n.libelle))],
            onChanged: (n) => setState(() => _nature = n ?? _nature),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MoyenDon>(
            key: const Key('moyen_don'),
            initialValue: _moyen,
            decoration: const InputDecoration(labelText: 'Moyen de paiement', border: OutlineInputBorder()),
            items: [for (final m in MoyenDon.values) DropdownMenuItem(value: m, child: Text(m.libelle))],
            onChanged: (m) => setState(() => _moyen = m ?? _moyen),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                key: ValueKey('donateur_don_$_donateurId'),
                initialValue: _donateurId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Donateur', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Sans nom (quête, anonyme)')),
                  for (final d in donateurs) DropdownMenuItem<String?>(value: d.id, child: Text(d.nomComplet)),
                ],
                onChanged: (id) => setState(() => _donateurId = id),
              ),
            ),
            IconButton(
              key: const Key('creer_donateur_saisie'),
              tooltip: 'Nouveau donateur',
              onPressed: _nouveauDonateur,
              icon: const Icon(Icons.person_add_alt_outlined),
            ),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: const Key('campagne_don'),
            initialValue: _affectationId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Campagne ou projet', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Aucune (don libre)')),
              for (final c in campagnes) DropdownMenuItem<String?>(value: c.id, child: Text(c.libelle)),
            ],
            onChanged: (id) => setState(() => _affectationId = id),
          ),
          if (campagne?.type == TypeAffectation.projet)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(TypeAffectation.projet.aide, style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text('Date du don : ${dateCourte(_date)}'),
            onTap: _choisirDate,
          ),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(
                labelText: 'Référence (Orange Money, chèque, virement)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentaire,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Commentaire', border: OutlineInputBorder()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _anonyme,
            onChanged: (v) => setState(() => _anonyme = v),
            title: const Text('Le donateur souhaite rester anonyme'),
            subtitle: const Text('Son nom figure sur le reçu, jamais dans les listes et rapports.'),
          ),
          const SizedBox(height: 12),
          if (_valeur != null && _valeur! > 0)
            Text('Montant en lettres : ${montantEnLettresAffiche(_valeur!)}',
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('enregistrer_don'),
            onPressed: _enCours ? null : _enregistrer,
            icon: const Icon(Icons.check),
            label: const Text('Enregistrer et numéroter le reçu'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogues (chacun son propre état : jamais de setState d'un parent)
// ---------------------------------------------------------------------------
class DialogueTexte extends StatefulWidget {
  const DialogueTexte({
    super.key,
    required this.titre,
    required this.libelle,
    required this.bouton,
    required this.cle,
    this.aide,
  });

  final String titre;
  final String libelle;
  final String bouton;
  final String cle;
  final String? aide;

  @override
  State<DialogueTexte> createState() => _DialogueTexteState();
}

class _DialogueTexteState extends State<DialogueTexte> {
  final _texte = TextEditingController();

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valide = _texte.text.trim().length >= 3;
    return AlertDialog(
      title: Text(widget.titre),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.aide != null) ...[Text(widget.aide!), const SizedBox(height: 12)],
        TextField(
          key: Key(widget.cle),
          controller: _texte,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.libelle),
          onChanged: (_) => setState(() {}),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Retour')),
        FilledButton(
          key: Key('${widget.cle}_ok'),
          onPressed: valide ? () => Navigator.of(context).pop(_texte.text.trim()) : null,
          child: Text(widget.bouton),
        ),
      ],
    );
  }
}

class DialogueDonateur extends StatefulWidget {
  const DialogueDonateur({super.key, required this.etablissementId, this.donateur});

  final String etablissementId;
  final Donateur? donateur;

  @override
  State<DialogueDonateur> createState() => _DialogueDonateurState();
}

class _DialogueDonateurState extends State<DialogueDonateur> {
  late final _nom = TextEditingController(text: widget.donateur?.nom);
  late final _prenom = TextEditingController(text: widget.donateur?.prenom);
  late final _telephone = TextEditingController(text: widget.donateur?.telephone);
  late final _email = TextEditingController(text: widget.donateur?.email);
  late final _adresse = TextEditingController(text: widget.donateur?.adresse);
  late TypeDonateur _type = widget.donateur?.type ?? TypeDonateur.personne;
  late bool _contact = widget.donateur?.accepteContact ?? true;

  @override
  void dispose() {
    for (final c in [_nom, _prenom, _telephone, _email, _adresse]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.donateur == null ? 'Nouveau donateur' : 'Modifier le donateur'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<TypeDonateur>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final t in TypeDonateur.values) DropdownMenuItem(value: t, child: Text(t.libelle))],
            onChanged: (t) => setState(() => _type = t ?? _type),
          ),
          TextField(
            key: const Key('nom_donateur'),
            controller: _nom,
            decoration: InputDecoration(labelText: _type == TypeDonateur.personne ? 'Nom' : 'Nom de l\'organisation'),
            onChanged: (_) => setState(() {}),
          ),
          if (_type == TypeDonateur.personne)
            TextField(controller: _prenom, decoration: const InputDecoration(labelText: 'Prénom')),
          TextField(
            controller: _telephone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Téléphone'),
          ),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Courriel'),
          ),
          TextField(controller: _adresse, decoration: const InputDecoration(labelText: 'Adresse')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _contact,
            onChanged: (v) => setState(() => _contact = v),
            title: const Text('Accepte d\'être recontacté'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Retour')),
        FilledButton(
          key: const Key('enregistrer_donateur'),
          onPressed: _nom.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(Donateur(
                    id: widget.donateur?.id,
                    etablissementId: widget.etablissementId,
                    type: _type,
                    nom: _nom.text,
                    prenom: _type == TypeDonateur.personne ? _prenom.text : null,
                    telephone: _telephone.text,
                    email: _email.text,
                    adresse: _adresse.text,
                    accepteContact: _contact,
                    notes: widget.donateur?.notes,
                  )),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class DialogueCampagne extends StatefulWidget {
  const DialogueCampagne({super.key, required this.etablissementId, this.campagne});

  final String etablissementId;
  final AffectationDon? campagne;

  @override
  State<DialogueCampagne> createState() => _DialogueCampagneState();
}

class _DialogueCampagneState extends State<DialogueCampagne> {
  late final _libelle = TextEditingController(text: widget.campagne?.libelle);
  late final _objectif = TextEditingController(
      text: widget.campagne?.objectif == null ? '' : widget.campagne!.objectif!.round().toString());
  late TypeAffectation _type = widget.campagne?.type ?? TypeAffectation.libre;
  late bool _active = widget.campagne?.active ?? true;

  @override
  void dispose() {
    _libelle.dispose();
    _objectif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.campagne == null ? 'Nouvelle campagne' : 'Modifier la campagne'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            key: const Key('libelle_campagne'),
            controller: _libelle,
            decoration: const InputDecoration(labelText: 'Nom (ex. Construction de la bibliothèque)'),
            onChanged: (_) => setState(() {}),
          ),
          DropdownButtonFormField<TypeAffectation>(
            key: const Key('type_campagne'),
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final t in TypeAffectation.values) DropdownMenuItem(value: t, child: Text(t.libelle))],
            onChanged: (t) => setState(() => _type = t ?? _type),
          ),
          const SizedBox(height: 4),
          Text(_type.aide, style: Theme.of(context).textTheme.bodySmall),
          TextField(
            controller: _objectif,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Objectif (facultatif)'),
          ),
          if (widget.campagne != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Ouverte aux dons'),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Retour')),
        FilledButton(
          key: const Key('enregistrer_campagne'),
          onPressed: _libelle.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(AffectationDon(
                    id: widget.campagne?.id,
                    etablissementId: widget.etablissementId,
                    libelle: _libelle.text,
                    type: _type,
                    description: widget.campagne?.description,
                    objectif: double.tryParse(_objectif.text.replaceAll(RegExp(r'\s'), '')),
                    dateFin: widget.campagne?.dateFin,
                    active: _active,
                  )),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class DialogueEmploi extends StatefulWidget {
  const DialogueEmploi({super.key, required this.projet});

  final SuiviAffectation projet;

  @override
  State<DialogueEmploi> createState() => _DialogueEmploiState();
}

class _DialogueEmploiState extends State<DialogueEmploi> {
  final _montant = TextEditingController();
  final _libelle = TextEditingController();

  @override
  void dispose() {
    _montant.dispose();
    _libelle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final montant = double.tryParse(_montant.text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));
    final valide = montant != null && montant > 0 && montant <= widget.projet.disponible && _libelle.text.trim().length >= 3;
    return AlertDialog(
      title: Text('Employer les fonds — ${widget.projet.libelle}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Disponible : ${formaterMontant(widget.projet.disponible)}. La dépense elle-même se saisit en pièce '
            'comptable ; ici, on constate que les dons affectés ont servi au projet.'),
        TextField(
          key: const Key('montant_emploi'),
          controller: _montant,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Montant employé'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          key: const Key('libelle_emploi'),
          controller: _libelle,
          decoration: const InputDecoration(labelText: 'À quoi les fonds ont servi'),
          onChanged: (_) => setState(() {}),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Retour')),
        FilledButton(
          key: const Key('valider_emploi'),
          onPressed: valide ? () => Navigator.of(context).pop((montant: montant, libelle: _libelle.text.trim())) : null,
          child: const Text('Constater'),
        ),
      ],
    );
  }
}

class DialogueEngagement extends StatefulWidget {
  const DialogueEngagement({super.key, required this.donateur, required this.campagnes});

  final Donateur donateur;
  final List<AffectationDon> campagnes;

  @override
  State<DialogueEngagement> createState() => _DialogueEngagementState();
}

class _DialogueEngagementState extends State<DialogueEngagement> {
  final _montant = TextEditingController();
  String _periodicite = 'mensuelle';
  String? _affectationId;

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final montant = double.tryParse(_montant.text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));
    return AlertDialog(
      title: Text('Engagement de ${widget.donateur.nomComplet}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _montant,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Montant promis à chaque échéance'),
          onChanged: (_) => setState(() {}),
        ),
        DropdownButtonFormField<String>(
          initialValue: _periodicite,
          decoration: const InputDecoration(labelText: 'Fréquence'),
          items: const [
            DropdownMenuItem(value: 'mensuelle', child: Text('Chaque mois')),
            DropdownMenuItem(value: 'trimestrielle', child: Text('Chaque trimestre')),
            DropdownMenuItem(value: 'annuelle', child: Text('Chaque année')),
          ],
          onChanged: (p) => setState(() => _periodicite = p ?? _periodicite),
        ),
        DropdownButtonFormField<String?>(
          initialValue: _affectationId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Campagne'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Aucune')),
            for (final c in widget.campagnes)
              if (c.active) DropdownMenuItem<String?>(value: c.id, child: Text(c.libelle)),
          ],
          onChanged: (id) => setState(() => _affectationId = id),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Retour')),
        FilledButton(
          onPressed: montant == null || montant <= 0
              ? null
              : () => Navigator.of(context).pop((montant: montant, periodicite: _periodicite, affectationId: _affectationId)),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

/// « Cinq cent mille », première lettre en capitale.
String montantEnLettresAffiche(double montant) {
  final t = montantEnLettres(montant);
  return t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
}
