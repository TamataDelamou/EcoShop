import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../referentiel/application/referentiel_providers.dart';
import '../../referentiel/domain/niveau_educatif.dart';
import '../application/scolarite_providers.dart';
import '../data/frais_repository.dart';
import '../domain/classe.dart';
import '../domain/frais_scolarite_config.dart';
import '../domain/palier_paiement_config.dart';
import '../domain/scolarite_repository.dart';

/// Frais de scolarité (M15quater, refait pour REG-39).
///
/// Retour du test sur téléphone (2026-10-31) : les frais se fixent **en
/// fonction des classes**, et le montant doit se **répartir automatiquement**
/// entre les tranches de paiement ou les mois.
///
/// - Tarif par défaut, puis un tarif par niveau (il vaut pour toutes les
///   classes du niveau : 7e A, 7e B…) ;
/// - répartition : en une fois, en N tranches égales, ou par mois ;
/// - aperçu : ce que chaque famille paie à chaque échéance, classe par
///   classe, arrondi au franc (la dernière échéance absorbe l'arrondi).
class EcranParametresFinanciers extends ConsumerStatefulWidget {
  const EcranParametresFinanciers({super.key, required this.etablissementId, required this.anneeScolaireId});

  final String etablissementId;
  final String anneeScolaireId;

  @override
  ConsumerState<EcranParametresFinanciers> createState() => _EcranParametresFinanciersState();
}

enum _Mode { uneFois, tranches, mois }

class _EcranParametresFinanciersState extends ConsumerState<EcranParametresFinanciers> {
  _Mode? _mode;
  int _tranches = 3;
  int _nbMois = 9;
  int _premierMois = 10;
  bool _enCours = false;

  ({String etablissementId, String anneeScolaireId}) get _params =>
      (etablissementId: widget.etablissementId, anneeScolaireId: widget.anneeScolaireId);

  void _dire(String texte) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  String _message(ErreurScolarite e) => switch (e.code) {
        'FRAIS_FIXES_PAR_RESEAU' => 'Les frais de votre école sont fixés par la grille commune de votre réseau.',
        'PERMISSION_REFUSEE' => 'Vous n’avez pas le droit de modifier les frais.',
        'MONTANT_INVALIDE' => 'Montant invalide.',
        _ => 'Enregistrement impossible pour le moment. Vérifiez votre connexion.',
      };

  Future<void> _modifierTarif({String? niveauId, required String titre, FraisScolariteConfig? actuel}) async {
    final montant = TextEditingController(text: actuel == null ? '' : actuel.montantAnnuel.toStringAsFixed(0));
    final inscription = TextEditingController(text: actuel == null ? '' : actuel.fraisInscription.toStringAsFixed(0));
    final resultat = await showDialog<String>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: Text(titre),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('champ_montant_annuel'),
            controller: montant,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Scolarité annuelle (GNF)'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('champ_frais_inscription'),
            controller: inscription,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Frais d’inscription (GNF)'),
          ),
        ]),
        actions: [
          if (niveauId != null && actuel != null)
            TextButton(
              onPressed: () => Navigator.of(contexte).pop('defaut'),
              child: const Text('Tarif par défaut'),
            ),
          TextButton(onPressed: () => Navigator.of(contexte).pop(), child: const Text('Annuler')),
          FilledButton(
            key: const Key('valider_tarif'),
            onPressed: () => Navigator.of(contexte).pop('ok'),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (resultat == null) return;
    final valeur = double.tryParse(montant.text);
    if (resultat == 'ok' && valeur == null) {
      _dire('Saisissez le montant annuel.');
      return;
    }
    try {
      await ref.read(fraisRepositoryProvider).enregistrerTarif(
            etablissementId: widget.etablissementId,
            anneeId: widget.anneeScolaireId,
            niveauId: niveauId,
            montantAnnuel: resultat == 'defaut' ? null : valeur,
            fraisInscription: double.tryParse(inscription.text) ?? 0,
          );
      ref.invalidate(fraisScolariteConfigProvider(_params));
      _dire(resultat == 'defaut' ? 'Ce niveau suit le tarif par défaut.' : 'Tarif enregistré.');
    } on ErreurScolarite catch (e) {
      _dire(_message(e));
    } catch (_) {
      _dire('Enregistrement impossible pour le moment. Vérifiez votre connexion.');
    }
  }

  List<PalierPropose> _proposition(DateTime? debut) => switch (_mode) {
        _Mode.tranches => repartitionTranches(_tranches),
        _Mode.mois => repartitionMensuelle(
            premierMois: _premierMois,
            n: _nbMois,
            // Premier mois avant le mois de rentrée (janvier pour une
            // rentrée d'octobre) : année civile suivante.
            annee: (debut?.year ?? DateTime.now().year) + (debut != null && _premierMois < debut.month ? 1 : 0),
          ),
        _ => const [],
      };

  Future<void> _appliquer(List<PalierPropose> paliers) async {
    setState(() => _enCours = true);
    try {
      await ref.read(fraisRepositoryProvider).repartir(
            etablissementId: widget.etablissementId,
            anneeId: widget.anneeScolaireId,
            paliers: paliers,
          );
      ref.invalidate(paliersPaiementConfigProvider(_params));
      setState(() => _mode = null);
      _dire(paliers.isEmpty ? 'Paiement en une fois.' : 'Répartition enregistrée : ${paliers.length} échéances.');
    } on ErreurScolarite catch (e) {
      _dire(_message(e));
    } catch (_) {
      _dire('Enregistrement impossible pour le moment. Vérifiez votre connexion.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final frais = ref.watch(fraisScolariteConfigProvider(_params));
    final paliers = ref.watch(paliersPaiementConfigProvider(_params));
    final structure = ref.watch(structureEtablissementProvider(widget.anneeScolaireId)).valueOrNull;
    final pays = ref.watch(etablissementActifProvider)?.paysCode;
    final niveaux = pays == null
        ? const <NiveauEducatif>[]
        : ref.watch(arborescencePaysProvider(pays)).valueOrNull?.niveaux ?? const <NiveauEducatif>[];
    final nomNiveau = {for (final n in niveaux) n.id: n.nom};
    final ordreNiveau = {for (final n in niveaux) n.id: n.ordre};

    // Classes de l'année regroupées par niveau.
    final classesParNiveau = <String, List<Classe>>{};
    for (final c in structure?.classes ?? const <Classe>[]) {
      if (!c.actif || c.niveauId == null) continue;
      classesParNiveau.putIfAbsent(c.niveauId!, () => []).add(c);
    }
    final niveauxEcole = classesParNiveau.keys.toList()
      ..sort((a, b) => (ordreNiveau[a] ?? 999).compareTo(ordreNiveau[b] ?? 999));
    DateTime? debutAnnee;
    for (final a in structure?.anneesScolaires ?? const []) {
      if (a.id == widget.anneeScolaireId) debutAnnee = a.dateDebut;
    }

    final schema = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Frais de scolarité')),
      body: frais.when(
        loading: () => ListView(padding: const EdgeInsets.all(16), children: const [ShimmerCarteListe(), ShimmerCarteListe()]),
        error: (_, _) => const Center(child: Text('Tarifs indisponibles hors connexion pour le moment.')),
        data: (tarifs) {
          FraisScolariteConfig? defaut;
          final parNiveau = <String, FraisScolariteConfig>{};
          for (final f in tarifs) {
            if (f.estTarifParDefaut) {
              defaut = f;
            } else {
              parNiveau[f.niveauId!] = f;
            }
          }
          final listePaliers = paliers.valueOrNull ?? const <PalierPaiementConfig>[];
          final proposition = _mode == null ? null : _proposition(debutAnnee);
          final pourcentages = proposition != null
              ? [for (final p in proposition) p.pourcentage]
              : [for (final p in listePaliers) p.pourcentage];
          final libelles = proposition != null ? [for (final p in proposition) p.nom] : [for (final p in listePaliers) p.nom];

          // Lignes de l'aperçu : chaque niveau de l'école avec son tarif.
          final lignes = <(String, double)>[
            for (final n in niveauxEcole)
              if ((parNiveau[n] ?? defaut) != null) (nomNiveau[n] ?? 'Niveau', (parNiveau[n] ?? defaut)!.montantAnnuel),
            if (niveauxEcole.isEmpty && defaut != null) ('Toutes les classes', defaut.montantAnnuel),
          ];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // 1. Tarif par défaut
              Text('Tarif par défaut', style: theme.textTheme.titleMedium),
              const Text('Pour toutes les classes qui n’ont pas de tarif propre.'),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  key: const Key('tarif_defaut'),
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(defaut == null ? 'Non fixé' : '${_gnf(defaut.montantAnnuel)} par an'),
                  subtitle: Text(defaut == null || defaut.fraisInscription == 0
                      ? 'Touchez pour fixer le tarif'
                      : 'Inscription : ${_gnf(defaut.fraisInscription)}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _modifierTarif(titre: 'Tarif par défaut', actuel: defaut),
                ),
              ),

              // 2. Par niveau de classe
              const SizedBox(height: 20),
              Text('Tarif par classe', style: theme.textTheme.titleMedium),
              const Text('Un tarif par niveau : il vaut pour toutes les classes de ce niveau.'),
              const SizedBox(height: 8),
              if (niveauxEcole.isEmpty)
                const Text('Créez d’abord vos classes (« Configurer mon établissement »).')
              else
                Card(
                  child: Column(children: [
                    for (final n in niveauxEcole)
                      ListTile(
                        key: Key('tarif_niveau_$n'),
                        title: Text(nomNiveau[n] ?? 'Niveau'),
                        subtitle: Text(classesParNiveau[n]!.map((c) => c.nom).join(', ')),
                        trailing: Text(
                          parNiveau[n] != null
                              ? _gnf(parNiveau[n]!.montantAnnuel)
                              : defaut != null
                                  ? '${_gnf(defaut.montantAnnuel)} (défaut)'
                                  : 'À fixer',
                          style: TextStyle(
                            fontWeight: parNiveau[n] != null ? FontWeight.w700 : FontWeight.w400,
                            color: parNiveau[n] != null ? null : context.palette.encreSecondaire,
                          ),
                        ),
                        onTap: () => _modifierTarif(niveauId: n, titre: nomNiveau[n] ?? 'Niveau', actuel: parNiveau[n]),
                      ),
                  ]),
                ),

              // 3. Répartition
              const SizedBox(height: 20),
              Text('Répartition du paiement', style: theme.textTheme.titleMedium),
              Text(listePaliers.isEmpty
                  ? 'Actuellement : paiement en une fois.'
                  : 'Actuellement : ${listePaliers.length} échéances (${listePaliers.map((p) => p.nom).join(', ')}).'),
              const SizedBox(height: 8),
              SegmentedButton<_Mode>(
                key: const Key('choix_repartition'),
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: _Mode.uneFois, label: Text('En une fois')),
                  ButtonSegment(value: _Mode.tranches, label: Text('Tranches')),
                  ButtonSegment(value: _Mode.mois, label: Text('Par mois')),
                ],
                selected: {?_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.isEmpty ? null : s.first),
              ),
              if (_mode == _Mode.tranches)
                _Compteur(
                  libelle: 'Nombre de tranches',
                  valeur: _tranches,
                  min: 2,
                  max: 6,
                  onChanged: (v) => setState(() => _tranches = v),
                ),
              if (_mode == _Mode.mois) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('premier_mois'),
                  initialValue: _premierMois,
                  decoration: const InputDecoration(labelText: 'Premier mois', border: OutlineInputBorder()),
                  items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(moisFrancais[m - 1]))],
                  onChanged: (v) => setState(() => _premierMois = v ?? _premierMois),
                ),
                _Compteur(
                  libelle: 'Nombre de mois',
                  valeur: _nbMois,
                  min: 2,
                  max: 12,
                  onChanged: (v) => setState(() => _nbMois = v),
                ),
                const Text('Échéance : le 10 de chaque mois.', style: TextStyle(fontSize: 12)),
              ],

              // 4. Aperçu
              if (pourcentages.isNotEmpty && lignes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(proposition != null ? 'Aperçu' : 'Montants par échéance', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    key: const Key('apercu_repartition'),
                    columnSpacing: 18,
                    headingRowHeight: 40,
                    columns: [
                      const DataColumn(label: Text('Classe')),
                      for (final l in libelles) DataColumn(label: Text(l), numeric: true),
                    ],
                    rows: [
                      for (final (nom, montant) in lignes)
                        DataRow(cells: [
                          DataCell(Text(nom)),
                          for (final m in montantsParPalier(montant, pourcentages)) DataCell(Text(_gnf(m.toDouble()))),
                        ]),
                    ],
                  ),
                ),
              ],
              if (_mode != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('appliquer_repartition'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _enCours ? null : () => _appliquer(proposition ?? const []),
                  icon: _enCours
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('Appliquer cette répartition'),
                ),
                const SizedBox(height: 6),
                Text('Elle remplace les échéances actuelles de l’année, pour toutes les classes.',
                    style: TextStyle(fontSize: 12, color: schema.onSurfaceVariant)),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _gnf(double montant) {
    final brut = montant.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < brut.length; i++) {
      if (i > 0 && (brut.length - i) % 3 == 0) b.write(' ');
      b.write(brut[i]);
    }
    return '$b GNF';
  }
}

class _Compteur extends StatelessWidget {
  const _Compteur({required this.libelle, required this.valeur, required this.min, required this.max, required this.onChanged});

  final String libelle;
  final int valeur;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Expanded(child: Text(libelle, style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(onPressed: valeur > min ? () => onChanged(valeur - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
        Text('$valeur', style: Theme.of(context).textTheme.titleLarge),
        IconButton(onPressed: valeur < max ? () => onChanged(valeur + 1) : null, icon: const Icon(Icons.add_circle_outline)),
      ]),
    );
  }
}
