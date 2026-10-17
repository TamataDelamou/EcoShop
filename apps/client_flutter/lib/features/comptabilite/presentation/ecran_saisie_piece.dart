import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../application/comptabilite_providers.dart';
import '../application/pieces_comptables_providers.dart';
import '../domain/journal.dart';
import '../domain/pieces_comptables.dart';
import '../domain/plan_comptable.dart';

/// Saisie d'une pièce comptable à plusieurs lignes (REG-03 C2).
///
/// Le total des débits et des crédits s'affiche en direct ; « Valider » n'est
/// proposé que si la pièce est équilibrée. Le brouillard reste modifiable ;
/// une fois validée, la pièce reçoit son numéro définitif et ne change plus.
class EcranSaisiePiece extends ConsumerStatefulWidget {
  const EcranSaisiePiece({super.key, required this.etablissementId, this.brouillard});

  final String etablissementId;

  /// Brouillard à reprendre (détail chargé, lignes comprises).
  final PieceComptable? brouillard;

  @override
  ConsumerState<EcranSaisiePiece> createState() => _EcranSaisiePieceState();
}

class _LigneEdition {
  _LigneEdition({this.compte, String debit = '', String credit = '', String libelle = ''})
      : debit = TextEditingController(text: debit),
        credit = TextEditingController(text: credit),
        libelle = TextEditingController(text: libelle);

  PlanComptable? compte;
  final TextEditingController debit;
  final TextEditingController credit;
  final TextEditingController libelle;

  double get montantDebit => _lire(debit.text);
  double get montantCredit => _lire(credit.text);

  static double _lire(String s) => double.tryParse(s.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.')) ?? 0;

  void dispose() {
    debit.dispose();
    credit.dispose();
    libelle.dispose();
  }
}

class _EcranSaisiePieceState extends ConsumerState<EcranSaisiePiece> {
  final _libelle = TextEditingController();
  final _justificatif = TextEditingController();
  late DateTime _date;
  String? _journalId;
  final List<_LigneEdition> _lignes = [];
  bool _initialise = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final b = widget.brouillard;
    _date = b?.datePiece ?? DateTime.now();
    _journalId = b?.journalId;
    _libelle.text = b?.libelle ?? '';
    _justificatif.text = b?.pieceJustificative ?? '';
  }

  @override
  void dispose() {
    _libelle.dispose();
    _justificatif.dispose();
    for (final l in _lignes) {
      l.dispose();
    }
    super.dispose();
  }

  /// Comptes de détail uniquement (aucun sous-compte actif rattaché).
  List<PlanComptable> _imputables(List<PlanComptable> plan) {
    final parents = {for (final c in plan) if (c.parentId != null) c.parentId};
    return [for (final c in plan) if (c.actif && !parents.contains(c.id)) c];
  }

  void _initialiserLignes(List<PlanComptable> plan) {
    if (_initialise) return;
    _initialise = true;
    final b = widget.brouillard;
    if (b != null && b.lignes.isNotEmpty) {
      for (final l in b.lignes) {
        _lignes.add(_LigneEdition(
          compte: plan.where((c) => c.id == l.compteId).firstOrNull,
          debit: l.debit == 0 ? '' : _brut(l.debit),
          credit: l.credit == 0 ? '' : _brut(l.credit),
          libelle: l.libelle ?? '',
        ));
      }
    } else {
      _lignes
        ..add(_LigneEdition())
        ..add(_LigneEdition());
    }
  }

  static String _brut(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  double get _totalDebit => _lignes.fold(0, (s, l) => s + l.montantDebit);
  double get _totalCredit => _lignes.fold(0, (s, l) => s + l.montantCredit);

  SaisiePiece? _construire() {
    final journal = _journalId;
    if (journal == null) {
      setState(() => _erreur = 'Choisissez un journal.');
      return null;
    }
    if (_libelle.text.trim().isEmpty) {
      setState(() => _erreur = 'Le libellé est obligatoire.');
      return null;
    }
    final lignes = <LignePiece>[];
    for (final l in _lignes) {
      final d = l.montantDebit;
      final c = l.montantCredit;
      if (l.compte == null && d == 0 && c == 0) continue; // ligne vide ignorée
      if (l.compte == null || (d > 0) == (c > 0) || d < 0 || c < 0) {
        setState(() => _erreur = 'Chaque ligne : un compte et un montant au débit OU au crédit.');
        return null;
      }
      lignes.add(LignePiece(compteId: l.compte!.id, debit: d, credit: c, libelle: l.libelle.text));
    }
    if (lignes.isEmpty) {
      setState(() => _erreur = 'Ajoutez au moins une ligne.');
      return null;
    }
    return SaisiePiece(
      pieceId: widget.brouillard?.id,
      etablissementId: widget.etablissementId,
      journalId: journal,
      datePiece: _date,
      libelle: _libelle.text.trim(),
      pieceJustificative: _justificatif.text.trim().isEmpty ? null : _justificatif.text.trim(),
      lignes: lignes,
    );
  }

  Future<void> _enregistrer({required bool valider}) async {
    final saisie = _construire();
    if (saisie == null) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final depot = ref.read(piecesComptablesRepositoryProvider);
    try {
      final id = await depot.enregistrer(saisie);
      String? reference;
      if (valider) reference = await depot.valider(id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(reference != null ? 'Pièce $reference validée.' : 'Brouillard enregistré.'),
      ));
    } on ErreurPiecesComptables catch (e) {
      if (mounted) setState(() => _erreur = e.messageUtilisateur);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final journaux = ref.watch(journauxProvider(widget.etablissementId));
    final plan = ref.watch(planComptableProvider(widget.etablissementId));

    return Scaffold(
      appBar: AppBar(title: Text(widget.brouillard == null ? 'Nouvelle pièce' : 'Modifier le brouillard')),
      body: plan.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Plan comptable indisponible hors connexion.')),
        data: (comptes) {
          _initialiserLignes(comptes);
          final imputables = _imputables(comptes);
          final ecart = _totalDebit - _totalCredit;
          final equilibree = _totalDebit > 0 && ecart.abs() < 0.005 && _lignes.length >= 2;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Expanded(
                  child: journaux.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => const Text('Journaux indisponibles.'),
                    data: (liste) => DropdownButtonFormField<String>(
                      key: const Key('piece_journal'),
                      initialValue: _journalId,
                      decoration: const InputDecoration(labelText: 'Journal'),
                      items: [
                        for (final Journal j in liste.where((j) => j.code != 'AN'))
                          DropdownMenuItem(value: j.id, child: Text('${j.code} — ${j.intitule}')),
                      ],
                      onChanged: (v) => setState(() => _journalId = v),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 130,
                  child: InkWell(
                  key: const Key('piece_date'),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date'),
                    child: Text(dateCourte(_date)),
                  ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                key: const Key('piece_libelle'),
                controller: _libelle,
                decoration: const InputDecoration(labelText: 'Libellé de la pièce'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _justificatif,
                decoration: const InputDecoration(
                  labelText: 'Pièce justificative',
                  helperText: 'Référence du reçu, de la facture… (exigée par le droit comptable)',
                ),
              ),
              const SizedBox(height: 20),
              Text('Lignes', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (var i = 0; i < _lignes.length; i++) _ligne(context, i, imputables),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('ajouter_ligne'),
                  onPressed: () => setState(() => _lignes.add(_LigneEdition())),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une ligne'),
                ),
              ),
              const SizedBox(height: 8),
              _Totaux(debit: _totalDebit, credit: _totalCredit, equilibree: equilibree),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('enregistrer_brouillard'),
                    onPressed: _enCours ? null : () => _enregistrer(valider: false),
                    child: const Text('Enregistrer le brouillard'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('enregistrer_et_valider'),
                    onPressed: _enCours || !equilibree ? null : () => _enregistrer(valider: true),
                    child: const Text('Valider la pièce'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Une pièce validée reçoit un numéro définitif et ne se modifie plus ; une erreur se corrige par contre-passation.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.encreSecondaire),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ligne(BuildContext context, int i, List<PlanComptable> imputables) {
    final l = _lignes[i];
    final choix = imputables.any((c) => c.id == l.compte?.id) ? l.compte : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<PlanComptable>(
                  key: Key('ligne_${i}_compte'),
                  isExpanded: true,
                  initialValue: choix,
                  decoration: const InputDecoration(labelText: 'Compte'),
                  items: [
                    for (final c in imputables)
                      DropdownMenuItem(value: c, child: Text(c.libelle, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => l.compte = v),
                ),
              ),
              IconButton(
                tooltip: 'Retirer la ligne',
                onPressed: _lignes.length <= 1
                    ? null
                    : () => setState(() {
                          _lignes.removeAt(i).dispose();
                        }),
                icon: const Icon(Icons.close),
              ),
            ]),
            Row(children: [
              Expanded(child: _montant(Key('ligne_${i}_debit'), l.debit, 'Débit', () => l.credit.clear())),
              const SizedBox(width: 12),
              Expanded(child: _montant(Key('ligne_${i}_credit'), l.credit, 'Crédit', () => l.debit.clear())),
              const SizedBox(width: 44),
            ]),
            TextField(
              controller: l.libelle,
              decoration: const InputDecoration(labelText: 'Libellé de la ligne (facultatif)', isDense: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _montant(Key key, TextEditingController ctrl, String label, VoidCallback viderAutreSens) => TextField(
        key: key,
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
        decoration: InputDecoration(labelText: label),
        onChanged: (v) => setState(() {
          if (v.isNotEmpty) viderAutreSens();
        }),
      );
}

class _Totaux extends StatelessWidget {
  const _Totaux({required this.debit, required this.credit, required this.equilibree});

  final double debit;
  final double credit;
  final bool equilibree;

  @override
  Widget build(BuildContext context) {
    final couleur = equilibree ? context.palette.primaire : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(equilibree ? Icons.check_circle_outline : Icons.balance_outlined, color: couleur),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Débit ${formaterMontant(debit)}  ·  Crédit ${formaterMontant(credit)}'
            '${equilibree ? '  —  équilibrée' : '  —  écart ${formaterMontant((debit - credit).abs())}'}',
            key: const Key('totaux_piece'),
          ),
        ),
      ]),
    );
  }
}
