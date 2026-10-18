import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/annee_scolaire.dart';
import '../application/inscription_en_ligne_providers.dart';
import '../domain/inscription_en_ligne.dart';
import 'ecran_dossiers_inscription.dart';
import 'widgets/elements_inscription.dart';

/// Campagne d'inscription d'une année (Direction, REG-08) : dates, délai de
/// réservation, pièces exigées, places par niveau, consignes, publication.
class EcranCampagneInscription extends ConsumerStatefulWidget {
  const EcranCampagneInscription({super.key, required this.etablissementId, this.devise = 'GNF'});

  final String etablissementId;
  final String devise;

  @override
  ConsumerState<EcranCampagneInscription> createState() => _EcranCampagneInscriptionState();
}

class _EcranCampagneInscriptionState extends ConsumerState<EcranCampagneInscription> {
  String? _anneeId;
  String? _chargeePour;
  String? _campagneId;

  late DateTime _ouvertureReinscriptions;
  late DateTime _ouvertureNouvelles;
  late DateTime _dateLimite;
  int _delai = 7;
  List<PieceRequise> _pieces = [];
  final Map<String, TextEditingController> _places = {};
  final _consignes = TextEditingController();
  bool _publiee = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _valeursParDefaut();
  }

  @override
  void dispose() {
    for (final c in _places.values) {
      c.dispose();
    }
    _consignes.dispose();
    super.dispose();
  }

  void _valeursParDefaut() {
    final aujourdhui = DateTime.now();
    final jour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
    _ouvertureReinscriptions = jour;
    _ouvertureNouvelles = jour.add(const Duration(days: 14));
    _dateLimite = jour.add(const Duration(days: 60));
    _delai = 7;
    _pieces = const [
      PieceRequise(code: 'acte_naissance', libelle: 'Acte de naissance (ou jugement supplétif)'),
      PieceRequise(code: 'bulletin', libelle: 'Dernier bulletin de notes'),
      PieceRequise(code: 'photo', libelle: "Photo d'identité", obligatoire: false),
    ];
    _consignes.text = '';
    _publiee = false;
    _campagneId = null;
  }

  void _charger(CampagneInscription? c) {
    _valeursParDefaut();
    for (final ctrl in _places.values) {
      ctrl.text = '';
    }
    if (c == null) return;
    _campagneId = c.id;
    _ouvertureReinscriptions = c.ouvertureReinscriptions;
    _ouvertureNouvelles = c.ouvertureNouvelles;
    _dateLimite = c.dateLimite;
    _delai = c.delaiReservationJours;
    _pieces = List.of(c.piecesRequises);
    _consignes.text = c.consignes ?? '';
    _publiee = c.publiee;
    for (final e in c.places.entries) {
      (_places[e.key] ??= TextEditingController()).text = '${e.value}';
    }
  }

  /// Année visée par défaut : la prochaine année non clôturée, sinon la
  /// courante.
  String? _anneeParDefaut(List<AnneeScolaire> annees) {
    final ouvertes = [for (final a in annees) if (!a.cloturee) a]..sort((a, b) => a.dateDebut.compareTo(b.dateDebut));
    if (ouvertes.isEmpty) return null;
    final courante = ouvertes.where((a) => a.courante).firstOrNull;
    if (courante == null) return ouvertes.last.id;
    return ouvertes.where((a) => a.dateDebut.isAfter(courante.dateDebut)).firstOrNull?.id ?? courante.id;
  }

  Future<void> _choisirDate(DateTime actuelle, void Function(DateTime) affecter) async {
    final d = await showDatePicker(
      context: context,
      initialDate: actuelle,
      firstDate: DateTime(actuelle.year - 1),
      lastDate: DateTime(actuelle.year + 2),
    );
    if (d != null) setState(() => affecter(d));
  }

  Future<void> _ajouterPiece() async {
    final libelle = TextEditingController();
    var obligatoire = true;
    var cycle = 'tous';
    final piece = await showDialog<PieceRequise>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Pièce exigée'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: libelle,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom de la pièce', border: OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: obligatoire,
                onChanged: (v) => set(() => obligatoire = v),
                title: const Text('Obligatoire'),
              ),
              DropdownButtonFormField<String>(
                initialValue: cycle,
                decoration: const InputDecoration(labelText: 'Pour', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'tous', child: Text('Tous les élèves')),
                  DropdownMenuItem(value: 'primaire', child: Text('Maternelle et primaire')),
                  DropdownMenuItem(value: 'secondaire', child: Text('Collège et lycée')),
                ],
                onChanged: (v) => set(() => cycle = v ?? 'tous'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final l = libelle.text.trim();
                if (l.isEmpty) return;
                Navigator.of(c).pop(PieceRequise(
                  code: PieceRequise.codeDepuisLibelle(l),
                  libelle: l,
                  obligatoire: obligatoire,
                  iscedMin: cycle == 'secondaire' ? 2 : 0,
                  iscedMax: cycle == 'primaire' ? 1 : 8,
                ));
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    libelle.dispose();
    if (piece == null) return;
    setState(() {
      _pieces = [..._pieces.where((p) => p.code != piece.code), piece];
    });
  }

  Future<void> _enregistrer() async {
    final anneeId = _anneeId;
    if (anneeId == null) return;
    if (_dateLimite.isBefore(_ouvertureReinscriptions) || _dateLimite.isBefore(_ouvertureNouvelles)) {
      setState(() => _erreur = 'La date limite doit venir après les ouvertures.');
      return;
    }
    final places = <String, int>{};
    for (final e in _places.entries) {
      final n = int.tryParse(e.value.text.trim());
      if (n != null) places[e.key] = n;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final id = await ref.read(inscriptionEnLigneRepositoryProvider).enregistrerCampagne(CampagneInscription(
            etablissementId: widget.etablissementId,
            anneeScolaireId: anneeId,
            ouvertureReinscriptions: _ouvertureReinscriptions,
            ouvertureNouvelles: _ouvertureNouvelles,
            dateLimite: _dateLimite,
            delaiReservationJours: _delai,
            piecesRequises: _pieces,
            places: places,
            consignes: _consignes.text.trim().isEmpty ? null : _consignes.text.trim(),
            publiee: _publiee,
          ));
      ref.invalidate(campagneInscriptionProvider);
      if (!mounted) return;
      setState(() {
        _enCours = false;
        if (id != null) _campagneId = id;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(id == null
            ? 'Campagne enregistrée sur cet appareil : elle sera envoyée au retour du réseau.'
            : _publiee
                ? 'Campagne publiée : les familles peuvent faire leurs demandes.'
                : 'Campagne enregistrée (non publiée).'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = messageErreur(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final structure = ref.watch(structureEtablissementProvider(null)).value;
    final annees = structure?.anneesScolaires ?? const <AnneeScolaire>[];
    _anneeId ??= _anneeParDefaut(annees);
    final anneeId = _anneeId;

    if (anneeId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Campagne d'inscription")),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: Encadre(texte: "Créez d'abord l'année scolaire visée et ses classes (Structure de l'établissement)."),
        ),
      );
    }

    final campagne = ref.watch(
      campagneInscriptionProvider((etablissementId: widget.etablissementId, anneeScolaireId: anneeId)),
    );
    if (campagne.hasValue && _chargeePour != anneeId) {
      _chargeePour = anneeId;
      _charger(campagne.value);
    }
    final classes = ref.watch(structureEtablissementProvider(anneeId)).value?.classes ?? const [];
    final niveauIds = {for (final c in classes) if (c.niveauId != null && c.actif) c.niveauId!}.toList()..sort();
    final noms = ref.watch(_nomsNiveauxProvider(niveauIds.join(','))).value ?? const <String, String>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text("Campagne d'inscription"),
        actions: [
          if (_campagneId != null)
            TextButton.icon(
              key: const Key('voir_dossiers'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EcranDossiersInscription(
                  campagneId: _campagneId!,
                  anneeScolaireId: anneeId,
                  devise: widget.devise,
                ),
              )),
              icon: const Icon(Icons.folder_shared_outlined),
              label: const Text('Dossiers'),
            ),
        ],
      ),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: anneeId,
                  decoration: const InputDecoration(labelText: 'Année scolaire visée', border: OutlineInputBorder()),
                  items: [
                    for (final a in annees)
                      if (!a.cloturee) DropdownMenuItem(value: a.id, child: Text(a.libelle + (a.courante ? ' (en cours)' : ''))),
                  ],
                  onChanged: (v) => setState(() => _anneeId = v),
                ),
                if (niveauIds.isEmpty) ...[
                  const SizedBox(height: 12),
                  const Encadre(
                    icone: Icons.warning_amber_outlined,
                    texte: "Aucune classe n'existe encore pour cette année : créez les classes (avec leur niveau) "
                        'pour que les familles puissent choisir un niveau.',
                  ),
                ],
                const SizedBox(height: 16),
                Text('Calendrier', style: Theme.of(context).textTheme.titleMedium),
                _Date(
                  libelle: 'Ouverture des réinscriptions (anciens élèves)',
                  date: _ouvertureReinscriptions,
                  onTap: () => _choisirDate(_ouvertureReinscriptions, (d) => _ouvertureReinscriptions = d),
                ),
                _Date(
                  libelle: 'Ouverture des demandes des nouveaux élèves',
                  date: _ouvertureNouvelles,
                  onTap: () => _choisirDate(_ouvertureNouvelles, (d) => _ouvertureNouvelles = d),
                ),
                _Date(
                  libelle: 'Date limite',
                  date: _dateLimite,
                  onTap: () => _choisirDate(_dateLimite, (d) => _dateLimite = d),
                ),
                const SizedBox(height: 8),
                Text('Délai pour régler les frais une fois la place offerte : $_delai jour(s)'),
                Slider(
                  value: _delai.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: '$_delai j',
                  onChanged: (v) => setState(() => _delai = v.round()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('Pièces exigées', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton.icon(onPressed: _ajouterPiece, icon: const Icon(Icons.add), label: const Text('Ajouter')),
                  ],
                ),
                for (final p in _pieces)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(p.obligatoire ? Icons.assignment_turned_in_outlined : Icons.assignment_outlined),
                    title: Text(p.libelle),
                    subtitle: Text([
                      p.obligatoire ? 'Obligatoire' : 'Facultative',
                      if (p.iscedMin >= 2) 'collège et lycée' else if (p.iscedMax <= 1) 'maternelle et primaire',
                    ].join(' · ')),
                    trailing: IconButton(
                      tooltip: 'Retirer',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _pieces = [..._pieces.where((x) => x.code != p.code)]),
                    ),
                  ),
                if (niveauIds.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Places par niveau', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    'Laissez vide pour suivre la capacité des classes (illimité si une classe n\'a pas de capacité).',
                    style: TextStyle(color: palette.encreSecondaire, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  for (final id in niveauIds)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _places.putIfAbsent(id, TextEditingController.new),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: noms[id] ?? 'Niveau',
                          suffixText: 'places',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _consignes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Consignes aux familles (facultatif)',
                    hintText: 'Ex. : tests d\'entrée en 6e le samedi 12 à 8 h.',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  key: const Key('publier_campagne'),
                  contentPadding: EdgeInsets.zero,
                  value: _publiee,
                  onChanged: (v) => setState(() => _publiee = v),
                  title: const Text('Publier la campagne'),
                  subtitle: const Text('Les familles la voient et peuvent faire leurs demandes aux dates prévues.'),
                ),
                if (_erreur != null) Encadre(texte: _erreur!, icone: Icons.error_outline, couleur: palette.erreur),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            key: const Key('enregistrer_campagne'),
            onPressed: _enCours ? null : _enregistrer,
            child: _enCours
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Enregistrer'),
          ),
        ),
      ),
    );
  }
}

final _nomsNiveauxProvider = FutureProvider.autoDispose.family<Map<String, String>, String>((ref, ids) {
  final liste = ids.isEmpty ? const <String>[] : ids.split(',');
  return ref.watch(inscriptionEnLigneRepositoryProvider).nomsNiveaux(liste);
});

class _Date extends StatelessWidget {
  const _Date({required this.libelle, required this.date, required this.onTap});

  final String libelle;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(libelle),
      subtitle: Text(dateCourte(date), style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.edit_calendar_outlined),
      onTap: onTap,
    );
  }
}
