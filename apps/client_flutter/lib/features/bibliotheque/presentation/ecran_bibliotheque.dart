import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../export_pdf/data/etiquettes_livres_pdf_builder.dart';
import '../../export_pdf/presentation/ecran_apercu_pdf.dart';
import '../../pointage/domain/pointage.dart' show jetonDepuisLecture;
import '../../themes/application/theme_providers.dart';
import '../application/bibliotheque_providers.dart';
import '../domain/bibliotheque.dart';

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String _message(Object e) => e is ErreurBibliotheque ? e.messageUtilisateur : 'Opération impossible pour le moment.';

/// Bibliothèque côté personnel (cahier 25.2 à 25.4) : guichet de prêt et de
/// retour (sans réseau), catalogue et étiquettes, suivi des retards et de
/// l'inventaire, réglages des délais.
class EcranBibliotheque extends StatelessWidget {
  const EcranBibliotheque({super.key, required this.etablissement});

  final Etablissement etablissement;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bibliothèque'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'Guichet'),
              Tab(icon: Icon(Icons.menu_book_outlined), text: 'Catalogue'),
              Tab(icon: Icon(Icons.assignment_late_outlined), text: 'Suivi'),
              Tab(icon: Icon(Icons.tune), text: 'Réglages'),
            ],
          ),
        ),
        body: Column(
          children: [
            const BandeauSynchronisation(),
            Expanded(
              child: TabBarView(
                children: [
                  _Guichet(etablissementId: etablissement.id),
                  _Catalogue(etablissement: etablissement),
                  _Suivi(etablissementId: etablissement.id),
                  _Reglages(etablissementId: etablissement.id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Guichet
// ---------------------------------------------------------------------------
enum _Mode { pret, retour, inventaire }

class _Ligne {
  const _Ligne(this.texte, this.ok, this.heure);

  final String texte;
  final bool ok;
  final DateTime heure;
}

class _Guichet extends ConsumerStatefulWidget {
  const _Guichet({required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<_Guichet> createState() => _GuichetState();
}

class _GuichetState extends ConsumerState<_Guichet> {
  DonneesGuichet? _donnees;
  String? _erreur;
  _Mode _mode = _Mode.pret;
  LecteurGuichet? _lecteur;
  final List<_Ligne> _journal = [];
  bool _camera = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  MobileScannerController? _controleur;
  final _saisie = TextEditingController();
  final _focus = FocusNode();
  String? _derniere;
  DateTime? _derniereLe;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    unawaited(_charger());
  }

  @override
  void dispose() {
    _controleur?.dispose();
    _saisie.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _charger({bool rafraichir = true}) async {
    try {
      final d = await ref.read(bibliothequeRepositoryProvider).guichet(widget.etablissementId, rafraichir: rafraichir);
      if (mounted) {
        setState(() {
          _donnees = d;
          _erreur = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = _message(e));
    }
  }

  void _noter(String texte, bool ok) {
    setState(() {
      _journal.insert(0, _Ligne(texte, ok, DateTime.now()));
      if (_journal.length > 12) _journal.removeLast();
    });
  }

  Future<void> _lire(String lecture) async {
    final propre = lecture.trim();
    final d = _donnees;
    if (propre.isEmpty || d == null || _occupe) return;
    final maintenant = DateTime.now();
    if (propre == _derniere && _derniereLe != null && maintenant.difference(_derniereLe!) < const Duration(seconds: 3)) return;
    _derniere = propre;
    _derniereLe = maintenant;
    _occupe = true;
    final depot = ref.read(bibliothequeRepositoryProvider);
    try {
      final code = codeExemplaireDepuisLecture(propre);
      if (code == null) {
        // Carte d'élève.
        final lecteur = d.lecteurParJeton(jetonDepuisLecture(propre));
        if (lecteur == null) {
          _noter('Carte inconnue sur cet appareil (rechargez le guichet avec le réseau).', false);
        } else {
          setState(() => _lecteur = lecteur);
          if (_mode != _Mode.pret) setState(() => _mode = _Mode.pret);
        }
        return;
      }
      switch (_mode) {
        case _Mode.pret:
          {
          final lecteur = _lecteur;
          if (lecteur == null) {
            _noter('Scannez d’abord la carte de l’élève.', false);
            return;
          }
          final r = await depot.preter(etablissementId: widget.etablissementId, lecteur: lecteur, code: code);
          _noter(
            switch (r.statut) {
              StatutGuichet.prete => '« ${r.titre} » prêté à ${lecteur.prenom}, à rendre le ${_date(r.echeance!)}',
              StatutGuichet.enAttenteEnvoi =>
                '« ${r.titre} » prêté à ${lecteur.prenom}, à rendre le ${_date(r.echeance!)} (envoi au retour du réseau)',
              _ => '« ${r.titre} » : ${r.message}',
            },
            r.statut == StatutGuichet.prete || r.statut == StatutGuichet.enAttenteEnvoi,
          );
          }
        case _Mode.retour:
          {
          final r = await depot.rendre(etablissementId: widget.etablissementId, code: code);
          _noter(
            switch (r.statut) {
              StatutGuichet.pasEmprunte => '« ${r.titre} » n’était pas en prêt.',
              StatutGuichet.refuse => '« ${r.titre} » : ${r.message}',
              _ => '« ${r.titre} » rendu${r.lecteur == null ? '' : ' par ${r.lecteur!.prenom}'}'
                  '${r.enRetard ? ' (en retard)' : ''}${r.reserve ? ' — RÉSERVÉ : mettez-le de côté' : ''}'
                  '${r.statut == StatutGuichet.enAttenteEnvoi ? ' (envoi au retour du réseau)' : ''}',
            },
            r.statut != StatutGuichet.refuse,
          );
          }
        case _Mode.inventaire:
          {
          final titre = await depot.inventorier(widget.etablissementId, code);
          _noter(titre == null ? '$code : étiquette inconnue' : '$code vu : $titre', titre != null);
          }
      }
      final apres = await depot.guichet(widget.etablissementId, rafraichir: false);
      if (mounted) setState(() => _donnees = apres);
    } catch (e) {
      _noter(_message(e), false);
    } finally {
      _occupe = false;
      _saisie.clear();
      if (!_camera && mounted) _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final d = _donnees;
    if (d == null) {
      return Center(
        child: _erreur == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_erreur!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _charger, child: const Text('Réessayer')),
                ]),
              ),
      );
    }
    final lecteur = _lecteur;
    final empruntsLecteur = lecteur == null ? const <EmpruntGuichet>[] : d.empruntsDe(lecteur.ficheEleveId);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<_Mode>(
                segments: const [
                  ButtonSegment(value: _Mode.pret, icon: Icon(Icons.output), label: Text('Prêt')),
                  ButtonSegment(value: _Mode.retour, icon: Icon(Icons.input), label: Text('Retour')),
                  ButtonSegment(value: _Mode.inventaire, icon: Icon(Icons.inventory_2_outlined), label: Text('Inventaire')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            ),
            IconButton(
              tooltip: _camera ? 'Douchette ou saisie' : 'Caméra',
              icon: Icon(_camera ? Icons.keyboard_alt_outlined : Icons.photo_camera_outlined),
              onPressed: () => setState(() => _camera = !_camera),
            ),
            IconButton(tooltip: 'Recharger', icon: const Icon(Icons.refresh), onPressed: _charger),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          switch (_mode) {
            _Mode.pret => 'Scannez la carte de l’élève, puis l’étiquette de chaque livre.',
            _Mode.retour => 'Scannez l’étiquette du livre rendu.',
            _Mode.inventaire => 'Scannez chaque livre en rayon (réseau nécessaire). Lancez l’inventaire depuis « Suivi ».',
          },
          style: TextStyle(color: palette.encreSecondaire),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _camera
                ? MobileScanner(
                    controller: _controleur ??= MobileScannerController(
                      formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128],
                      detectionSpeed: DetectionSpeed.normal,
                    ),
                    onDetect: (capture) {
                      final v = capture.barcodes.firstOrNull?.rawValue;
                      if (v != null) unawaited(_lire(v));
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
                      decoration: const InputDecoration(hintText: 'Douchette, ou code LIV-000123', border: OutlineInputBorder()),
                      onSubmitted: _lire,
                    ),
                  ),
          ),
        ),
        if (_mode == _Mode.pret) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.person_outline, color: lecteur == null ? palette.encreSecondaire : palette.primaire),
              title: Text(lecteur == null ? 'Aucun élève' : lecteur.nomComplet),
              subtitle: Text(lecteur == null
                  ? 'Scannez sa carte'
                  : '${lecteur.classe ?? ''} · ${empruntsLecteur.length}/${d.parametres.maxEmprunts} emprunt(s)'),
              trailing: lecteur == null
                  ? null
                  : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _lecteur = null)),
            ),
          ),
          for (final e in empruntsLecteur)
            ListTile(
              dense: true,
              leading: Icon(
                Icons.book_outlined,
                color: DateTime.now().isAfter(e.echeance.add(const Duration(days: 1))) ? palette.erreur : palette.encreSecondaire,
              ),
              title: Text(d.exemplaires.where((x) => x.id == e.exemplaireId).firstOrNull?.titre ?? ''),
              subtitle: Text('À rendre le ${_date(e.echeance)}${e.enAttenteEnvoi ? ' · en attente d’envoi' : ''}'),
            ),
        ],
        const SizedBox(height: 12),
        for (final l in _journal)
          ListTile(
            dense: true,
            leading: Icon(l.ok ? Icons.check_circle : Icons.error_outline, color: l.ok ? palette.succes : palette.erreur),
            title: Text(l.texte),
            subtitle: Text('${l.heure.hour.toString().padLeft(2, '0')}:${l.heure.minute.toString().padLeft(2, '0')}'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------
class _Catalogue extends ConsumerStatefulWidget {
  const _Catalogue({required this.etablissement});

  final Etablissement etablissement;

  @override
  ConsumerState<_Catalogue> createState() => _CatalogueState();
}

class _CatalogueState extends ConsumerState<_Catalogue> {
  String _texte = '';
  Timer? _attente;

  @override
  void dispose() {
    _attente?.cancel();
    super.dispose();
  }

  Future<void> _imprimer(List<ExemplaireGuichet> exemplaires, String titre) async {
    if (exemplaires.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun exemplaire à étiqueter.')));
      return;
    }
    final octets = await construireEtiquettesLivresPdf(
      exemplaires: exemplaires,
      etablissement: widget.etablissement,
      variante: ref.read(themeVariantProvider),
      identite: await ref.read(identitePdfProvider.future),
    );
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EcranApercuPdf(titre: titre, octets: octets, nomFichier: 'etiquettes-bibliotheque.pdf'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cle = (etablissementId: widget.etablissement.id, texte: _texte);
    final livres = ref.watch(catalogueProvider(cle));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bouton_nouveau_livre'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EcranFicheLivre(etablissement: widget.etablissement),
        )),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un livre'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Titre, auteur, catégorie, cote, ISBN',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      _attente?.cancel();
                      _attente = Timer(const Duration(milliseconds: 400), () => setState(() => _texte = v.trim()));
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Imprimer toutes les étiquettes',
                  icon: const Icon(Icons.print_outlined),
                  onPressed: () async {
                    final d = await ref.read(bibliothequeRepositoryProvider).guichet(widget.etablissement.id);
                    await _imprimer([...d.exemplaires.where((e) => !e.retire)]..sort((a, b) => a.code.compareTo(b.code)),
                        'Étiquettes bibliothèque');
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: livres.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(_message(e))),
              data: (liste) => liste.isEmpty
                  ? const Center(child: Text('Aucun livre. Ajoutez le premier : l’ISBN remplit la fiche tout seul.'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        for (final l in liste)
                          Card(
                            child: ListTile(
                              title: Text(l.titre),
                              subtitle: Text([
                                if (l.auteurs != null) l.auteurs!,
                                if (l.cote != null) 'cote ${l.cote}',
                                if (l.reservations > 0) '${l.reservations} réservation(s)',
                              ].join(' · ')),
                              trailing: Text(
                                '${l.disponibles}/${l.exemplaires}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: l.disponibles > 0 ? palette.succes : palette.erreur,
                                ),
                              ),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => EcranFicheLivre(etablissement: widget.etablissement, livre: l),
                              )),
                            ),
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

/// Fiche d'un livre : saisie ou modification, préremplie depuis l'ISBN, ajout
/// d'exemplaires et impression de leurs étiquettes.
class EcranFicheLivre extends ConsumerStatefulWidget {
  const EcranFicheLivre({super.key, required this.etablissement, this.livre});

  final Etablissement etablissement;
  final Livre? livre;

  @override
  ConsumerState<EcranFicheLivre> createState() => _EcranFicheLivreState();
}

class _EcranFicheLivreState extends ConsumerState<EcranFicheLivre> {
  late final _isbn = TextEditingController(text: widget.livre?.isbn);
  late final _titre = TextEditingController(text: widget.livre?.titre);
  late final _auteurs = TextEditingController(text: widget.livre?.auteurs);
  late final _editeur = TextEditingController(text: widget.livre?.editeur);
  late final _annee = TextEditingController(text: widget.livre?.annee?.toString());
  late final _categorie = TextEditingController(text: widget.livre?.categorie);
  late final _niveau = TextEditingController(text: widget.livre?.niveau);
  late final _cote = TextEditingController(text: widget.livre?.cote);
  late final _resume = TextEditingController(text: widget.livre?.resume);
  final _nouveaux = TextEditingController(text: '1');
  bool _enCours = false;
  String? _info;

  List<TextEditingController> get _tous => [_isbn, _titre, _auteurs, _editeur, _annee, _categorie, _niveau, _cote, _resume, _nouveaux];

  @override
  void dispose() {
    for (final c in _tous) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _depuisIsbn() async {
    setState(() => _info = 'Recherche…');
    final s = await ref.read(bibliothequeRepositoryProvider).rechercherIsbn(_isbn.text);
    if (!mounted) return;
    if (s == null) {
      setState(() => _info = 'Livre introuvable (ou pas de réseau) : remplissez la fiche à la main.');
      return;
    }
    setState(() {
      _titre.text = s.titre;
      if (s.auteurs != null) _auteurs.text = s.auteurs!;
      if (s.editeur != null) _editeur.text = s.editeur!;
      if (s.annee != null) _annee.text = '${s.annee}';
      _info = 'Fiche remplie depuis l’ISBN : vérifiez-la.';
    });
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _enregistrer({bool imprimer = false}) async {
    if (_titre.text.trim().isEmpty) {
      setState(() => _info = 'Titre requis.');
      return;
    }
    setState(() => _enCours = true);
    try {
      final depot = ref.read(bibliothequeRepositoryProvider);
      final id = await depot.enregistrerLivre(
        widget.etablissement.id,
        SaisieLivre(
          titre: _titre.text.trim(),
          auteurs: _t(_auteurs),
          isbn: _t(_isbn),
          editeur: _t(_editeur),
          annee: int.tryParse(_annee.text.trim()),
          categorie: _t(_categorie),
          niveau: _t(_niveau),
          cote: _t(_cote),
          resume: _t(_resume),
        ),
        id: widget.livre?.id,
        nouveauxExemplaires: int.tryParse(_nouveaux.text.trim()) ?? 0,
      );
      ref.invalidate(catalogueProvider);
      if (imprimer) {
        final exemplaires = await depot.exemplairesDuLivre(widget.etablissement.id, id);
        final octets = await construireEtiquettesLivresPdf(
          exemplaires: exemplaires,
          etablissement: widget.etablissement,
          variante: ref.read(themeVariantProvider),
          identite: await ref.read(identitePdfProvider.future),
        );
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => EcranApercuPdf(titre: 'Étiquettes', octets: octets, nomFichier: 'etiquettes-livre.pdf'),
        ));
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _info = _message(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder());
    final livre = widget.livre;
    return Scaffold(
      appBar: AppBar(title: Text(livre == null ? 'Nouveau livre' : livre.titre)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              Expanded(child: TextField(controller: _isbn, keyboardType: TextInputType.number, decoration: deco('ISBN'))),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(onPressed: _depuisIsbn, icon: const Icon(Icons.auto_fix_high), label: const Text('Remplir')),
            ],
          ),
          if (_info != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_info!)),
          const SizedBox(height: 12),
          TextField(controller: _titre, decoration: deco('Titre *')),
          const SizedBox(height: 10),
          TextField(controller: _auteurs, decoration: deco('Auteur(s)')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _editeur, decoration: deco('Éditeur'))),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _annee,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: deco('Année'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _categorie, decoration: deco('Catégorie (roman, sciences…)'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _niveau, decoration: deco('Niveau (CM2, 3e…)'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _cote, decoration: deco('Cote (emplacement en rayon)')),
          const SizedBox(height: 10),
          TextField(controller: _resume, maxLines: 3, decoration: deco('Résumé')),
          const SizedBox(height: 16),
          TextField(
            controller: _nouveaux,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: deco(livre == null ? 'Nombre d’exemplaires' : 'Exemplaires à ajouter (déjà : ${livre.exemplaires})'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _enCours ? null : () => _enregistrer(imprimer: true),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Enregistrer et imprimer les étiquettes'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _enCours ? null : _enregistrer, child: const Text('Enregistrer')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Suivi : retards, pertes répétées, plus empruntés, inventaire
// ---------------------------------------------------------------------------
class _Suivi extends ConsumerWidget {
  const _Suivi({required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final tb = ref.watch(tableauBibliothequeProvider(etablissementId));
    Future<void> agir(Future<void> Function() action) async {
      try {
        await action();
        ref.invalidate(tableauBibliothequeProvider(etablissementId));
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
      }
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(tableauBibliothequeProvider(etablissementId)),
      child: tb.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_message(e)))]),
        data: (t) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              _Chiffre(titre: 'Livres', valeur: t.livres),
              _Chiffre(titre: 'Exemplaires', valeur: t.exemplaires),
              _Chiffre(titre: 'En prêt', valeur: t.enCours),
              _Chiffre(titre: 'Retards et pertes', valeur: t.retards.length, alerte: t.retards.isNotEmpty),
            ]),
            const SizedBox(height: 20),
            Text('En retard ou perdus', style: Theme.of(context).textTheme.titleMedium),
            if (t.retards.isEmpty) const Text('Aucun.'),
            for (final r in t.retards)
              Card(
                child: ListTile(
                  title: Text('${r.titre} (${r.code ?? ''})'),
                  subtitle: Text('${r.eleve ?? ''}${r.classe == null ? '' : ' · ${r.classe}'} · '
                      '${r.statut?.libelle ?? ''} depuis le ${r.echeance == null ? '' : _date(r.echeance!)}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => agir(() async {
                      final depot = ref.read(bibliothequeRepositoryProvider);
                      if (v == 'renouveler') await depot.renouveler(r.id!);
                      if (v == 'perdu') await depot.declarerPerdu(r.id!);
                    }),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'renouveler', child: Text('Renouveler le prêt')),
                      PopupMenuItem(value: 'perdu', child: Text('Déclarer perdu')),
                    ],
                  ),
                ),
              ),
            if (t.pertesRepetees.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Pertes répétées', style: Theme.of(context).textTheme.titleMedium),
              Text('À signaler à la vie scolaire si besoin : aucune sanction automatique.',
                  style: TextStyle(color: palette.encreSecondaire, fontSize: 13)),
              for (final p in t.pertesRepetees)
                ListTile(dense: true, leading: Icon(Icons.flag_outlined, color: palette.erreur), title: Text(p.eleve), trailing: Text('${p.pertes} pertes')),
            ],
            if (t.plusEmpruntes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Les plus empruntés (12 mois)', style: Theme.of(context).textTheme.titleMedium),
              for (final p in t.plusEmpruntes)
                ListTile(dense: true, leading: const Icon(Icons.trending_up), title: Text(p.titre), trailing: Text('${p.emprunts}')),
            ],
            const SizedBox(height: 16),
            Text('Inventaire', style: Theme.of(context).textTheme.titleMedium),
            if (t.parametres.inventaireDepuis == null)
              const Text('Aucun inventaire en cours.')
            else ...[
              Text('Commencé le ${_date(t.parametres.inventaireDepuis!)} : ${t.inventaireVus ?? 0} exemplaire(s) vu(s), '
                  '${t.introuvables.length} introuvable(s) (hors prêts).'),
              for (final i in t.introuvables.take(50))
                ListTile(dense: true, title: Text('${i.code} — ${i.titre}')),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => agir(() => ref.read(bibliothequeRepositoryProvider).commencerInventaire(etablissementId)),
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(t.parametres.inventaireDepuis == null ? 'Commencer un inventaire' : 'Recommencer l’inventaire'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.titre, required this.valeur, this.alerte = false});

  final String titre;
  final int valeur;
  final bool alerte;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$valeur',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: alerte ? palette.erreur : palette.primaire, fontWeight: FontWeight.w700)),
            Text(titre, style: TextStyle(color: palette.encreSecondaire)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Réglages (25.3 : seuils paramétrables par établissement)
// ---------------------------------------------------------------------------
class _Reglages extends ConsumerStatefulWidget {
  const _Reglages({required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<_Reglages> createState() => _ReglagesState();
}

class _ReglagesState extends ConsumerState<_Reglages> {
  ParametresBibliotheque? _p;

  Future<void> _enregistrer() async {
    final p = _p;
    if (p == null) return;
    try {
      await ref.read(bibliothequeRepositoryProvider).enregistrerParametres(widget.etablissementId, p);
      ref.invalidate(tableauBibliothequeProvider(widget.etablissementId));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Réglages enregistrés.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  Widget _compteur(String titre, int valeur, int min, int max, void Function(int) changer) => ListTile(
        title: Text(titre),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: valeur > min ? () => changer(valeur - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('$valeur', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(onPressed: valeur < max ? () => changer(valeur + 1) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
      );

  ParametresBibliotheque _copie({int? duree, int? max, int? renouv, int? perte, bool? relances}) {
    final p = _p!;
    return ParametresBibliotheque(
      dureePretJours: duree ?? p.dureePretJours,
      maxEmprunts: max ?? p.maxEmprunts,
      renouvellementsMax: renouv ?? p.renouvellementsMax,
      delaiPerteJours: perte ?? p.delaiPerteJours,
      relances: relances ?? p.relances,
      inventaireDepuis: p.inventaireDepuis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tb = ref.watch(tableauBibliothequeProvider(widget.etablissementId));
    _p ??= tb.valueOrNull?.parametres;
    final p = _p;
    if (p == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _compteur('Durée du prêt (jours)', p.dureePretJours, 1, 120, (v) => setState(() => _p = _copie(duree: v))),
        _compteur('Emprunts simultanés par élève', p.maxEmprunts, 1, 20, (v) => setState(() => _p = _copie(max: v))),
        _compteur('Renouvellements possibles', p.renouvellementsMax, 0, 5, (v) => setState(() => _p = _copie(renouv: v))),
        _compteur('« Perdu » après (jours de retard)', p.delaiPerteJours, 1, 365, (v) => setState(() => _p = _copie(perte: v))),
        SwitchListTile(
          value: p.relances,
          onChanged: (v) => setState(() => _p = _copie(relances: v)),
          title: const Text('Relances aux familles'),
          subtitle: const Text('La veille de l’échéance, le lendemain, puis une semaine après'),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton(onPressed: _enregistrer, child: const Text('Enregistrer')),
        ),
      ],
    );
  }
}
