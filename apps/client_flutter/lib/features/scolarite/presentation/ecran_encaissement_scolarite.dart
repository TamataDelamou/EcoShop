import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../export_pdf/data/recu_pdf_builder.dart';
import '../../export_pdf/presentation/ecran_apercu_pdf.dart';
import '../../themes/application/theme_providers.dart';
import '../application/scolarite_providers.dart';
import '../domain/encaissement_scolarite.dart';
import '../domain/enums_financier_scolaire.dart';
import '../domain/inscription.dart';
import '../domain/scolarite_repository.dart';

String _formaterMontant(double montant) => NumberFormat.decimalPattern('fr').format(montant);

/// Encaissement de scolarité pour une inscription (M15quater) — écran
/// d'entrée dédié (entité `encaissements_scolarite`), jamais une écriture
/// comptable générale (cf. retrait du reçu PDF de M15ter,
/// `docs/contrats/M15ter_export_pdf.md` §7). Le solde affiché est **toujours**
/// calculé côté serveur (RPC `solde_scolarite`), jamais recalculé ici.
class EcranEncaissementScolarite extends ConsumerStatefulWidget {
  const EcranEncaissementScolarite({super.key, required this.inscription});

  final Inscription inscription;

  @override
  ConsumerState<EcranEncaissementScolarite> createState() => _EcranEncaissementScolariteState();
}

class _EcranEncaissementScolariteState extends ConsumerState<EcranEncaissementScolarite> {
  final _montantCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  TypeFraisScolaire _typeFrais = TypeFraisScolaire.scolarite;
  MoyenPaiement _moyenPaiement = MoyenPaiement.especes;
  DateTime _date = DateTime.now();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _montantCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final montant = double.tryParse(_montantCtrl.text.replaceAll(',', '.'));
    if (montant == null || montant <= 0) {
      setState(() => _erreur = 'Saisissez un montant positif.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final encaissement = EncaissementScolarite(
        id: '',
        etablissementId: widget.inscription.etablissementId,
        ficheEleveId: widget.inscription.ficheEleveId,
        inscriptionId: widget.inscription.id,
        montant: montant,
        datePaiement: _date,
        saisiPar: '',
        typeFrais: _typeFrais,
        moyenPaiement: _moyenPaiement,
        referencePaiement: _referenceCtrl.text.trim().isEmpty ? null : _referenceCtrl.text.trim(),
      );
      await ref.read(scolariteRepositoryProvider).enregistrerEncaissement(encaissement);
      if (!mounted) return;
      ref.invalidate(soldeScolariteProvider(widget.inscription.id));
      ref.invalidate(encaissementsDeInscriptionProvider(widget.inscription.id));
      _montantCtrl.clear();
      _referenceCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encaissement enregistré.')),
      );
    } on ErreurScolarite catch (e) {
      setState(() => _erreur = e.code == 'PERMISSION_REFUSEE'
          ? "Vous n'avez pas le droit d'enregistrer un encaissement."
          : 'Enregistrement impossible pour le moment.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _annuler(EncaissementScolarite encaissement) async {
    final motifCtrl = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler l\'encaissement'),
        content: TextField(
          controller: motifCtrl,
          decoration: const InputDecoration(labelText: 'Motif (obligatoire)'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(motifCtrl.text.trim()),
            child: const Text('Annuler l\'encaissement'),
          ),
        ],
      ),
    );
    if (motif == null || motif.isEmpty || !mounted) return;

    try {
      await ref.read(scolariteRepositoryProvider).annulerEncaissement(
            encaissementId: encaissement.id,
            motif: motif,
          );
      if (!mounted) return;
      ref.invalidate(soldeScolariteProvider(widget.inscription.id));
      ref.invalidate(encaissementsDeInscriptionProvider(widget.inscription.id));
    } on ErreurScolarite {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Annulation impossible pour le moment.')),
      );
    }
  }

  Future<void> _exporterRecu(EncaissementScolarite encaissement) async {
    final etablissement = ref.read(etablissementActifProvider);
    final fiche = await ref.read(ficheEleveProvider(widget.inscription.ficheEleveId).future);
    if (etablissement == null || fiche == null || !mounted) return;

    final variante = ref.read(themeVariantProvider);
    final octets = await construireRecuPdf(
      encaissement: encaissement,
      fiche: fiche,
      etablissement: etablissement,
      variante: variante,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EcranApercuPdf(
          titre: 'Reçu',
          octets: octets,
          nomFichier: 'recu_${encaissement.id}.pdf',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final solde = ref.watch(soldeScolariteProvider(widget.inscription.id));
    final historique = ref.watch(encaissementsDeInscriptionProvider(widget.inscription.id));
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Encaissement de scolarité')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          solde.when(
            loading: () => const ShimmerCarteListe(),
            error: (e, _) => const Text('Solde indisponible hors connexion pour le moment.'),
            data: (s) => Card(
              color: s.estSolde ? palette.succes.withValues(alpha: 0.08) : palette.accent.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Montant dû : ${_formaterMontant(s.montantDu)}'),
                    Text('Montant payé : ${_formaterMontant(s.montantPaye)}'),
                    const SizedBox(height: 6),
                    Text(
                      s.estSolde ? 'Solde acquitté' : 'Reste à payer : ${_formaterMontant(s.solde)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: s.estSolde ? palette.succes : palette.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Nouvel encaissement', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<TypeFraisScolaire>(
            initialValue: _typeFrais,
            decoration: const InputDecoration(labelText: 'Type de frais'),
            items: TypeFraisScolaire.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.libelle)))
                .toList(),
            onChanged: (v) => setState(() => _typeFrais = v ?? _typeFrais),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _montantCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Montant'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MoyenPaiement>(
            initialValue: _moyenPaiement,
            decoration: const InputDecoration(labelText: 'Moyen de paiement'),
            items: MoyenPaiement.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.libelle)))
                .toList(),
            onChanged: (v) => setState(() => _moyenPaiement = v ?? _moyenPaiement),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _referenceCtrl,
            decoration: const InputDecoration(labelText: 'Référence (optionnel)'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text('${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final choisie = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (choisie != null) setState(() => _date = choisie);
            },
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _enCours ? null : _enregistrer,
            child: _enCours
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enregistrer l\'encaissement'),
          ),
          const SizedBox(height: 24),
          Text('Historique', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          historique.when(
            loading: () => const ShimmerCarteListe(),
            error: (e, _) => const Text('Historique indisponible hors connexion pour le moment.'),
            data: (liste) => liste.isEmpty
                ? const Text('Aucun encaissement enregistré.')
                : Column(
                    children: [
                      for (final e in liste)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text('${_formaterMontant(e.montant)} — ${e.typeFrais.libelle}'),
                            subtitle: Text(
                              '${e.moyenPaiement.libelle} · ${e.datePaiement.day.toString().padLeft(2, '0')}/'
                              '${e.datePaiement.month.toString().padLeft(2, '0')}/${e.datePaiement.year}'
                              '${e.estValide ? '' : ' · ANNULÉ (${e.motifAnnulation ?? ''})'}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Exporter le reçu (PDF)',
                                  icon: const Icon(Icons.picture_as_pdf_outlined),
                                  onPressed: () => _exporterRecu(e),
                                ),
                                if (e.estValide)
                                  IconButton(
                                    tooltip: 'Annuler',
                                    icon: Icon(Icons.cancel_outlined, color: palette.erreur),
                                    onPressed: () => _annuler(e),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
