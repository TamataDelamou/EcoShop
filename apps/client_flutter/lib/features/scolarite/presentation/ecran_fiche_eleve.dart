import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/auth/role_racine.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../application/scolarite_providers.dart';
import '../../notes/presentation/ecran_carnet_notes.dart';
import '../../vie_scolaire/presentation/ecran_suivi_vie_scolaire.dart';
import '../domain/fiche_eleve.dart';
import '../domain/inscription.dart';
import '../domain/scolarite_repository.dart';
import 'ecran_detail_classe.dart';
import 'ecran_encaissement_scolarite.dart';

String _formaterMontant(double montant) => NumberFormat.decimalPattern('fr').format(montant);

/// Détail d'une fiche élève : état civil, champs administratifs (M15quater),
/// historique de classes (M5) et suivi financier (M15quater).
class EcranFicheEleve extends ConsumerWidget {
  const EcranFicheEleve({super.key, required this.fiche});

  final FicheEleve fiche;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historique = ref.watch(inscriptionsDeFicheProvider(fiche.id));
    final estDirection = ref.watch(profilProvider).value?.roleRacine == RoleRacine.direction;

    return Scaffold(
      appBar: AppBar(
        title: Text(fiche.nomComplet),
        actions: [
          if (estDirection)
            IconButton(
              tooltip: 'Modifier les informations administratives',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _ouvrirEditionAdmin(context, ref, fiche),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: context.palette.primaire.withValues(alpha: 0.12),
                        child: Text(
                          fiche.prenom.isNotEmpty ? fiche.prenom[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: context.palette.primaire,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fiche.nomComplet,
                                style: Theme.of(context).textTheme.titleMedium),
                            Text('Matricule ${fiche.matricule}',
                                style: TextStyle(color: context.palette.encreSecondaire)),
                          ],
                        ),
                      ),
                      if (!fiche.estActive)
                        Icon(Icons.pause_circle_outline, color: context.palette.encreSecondaire),
                    ],
                  ),
                  const Divider(height: 28),
                  _LigneInfo(libelle: 'Date de naissance', valeur: _formatDate(fiche.dateNaissance)),
                  if (fiche.lieuNaissance != null)
                    _LigneInfo(libelle: 'Lieu de naissance', valeur: fiche.lieuNaissance!),
                  if (fiche.sexe != null)
                    _LigneInfo(libelle: 'Sexe', valeur: fiche.sexe == 'M' ? 'Masculin' : 'Féminin'),
                  if (fiche.nationalite != null)
                    _LigneInfo(libelle: 'Nationalité', valeur: fiche.nationalite!),
                  if (fiche.numeroClasse != null)
                    _LigneInfo(libelle: 'N° dans la classe', valeur: '${fiche.numeroClasse}'),
                  if (fiche.nomPere != null) _LigneInfo(libelle: 'Nom du père', valeur: fiche.nomPere!),
                  if (fiche.nomMere != null) _LigneInfo(libelle: 'Nom de la mère', valeur: fiche.nomMere!),
                  if (fiche.quartier != null) _LigneInfo(libelle: 'Quartier', valeur: fiche.quartier!),
                  if (fiche.personneUrgenceNom != null)
                    _LigneInfo(
                      libelle: 'Contact d\'urgence',
                      valeur: '${fiche.personneUrgenceNom}${fiche.personneUrgenceTelephone != null ? ' (${fiche.personneUrgenceTelephone})' : ''}',
                    ),
                  if (fiche.redoublant)
                    _LigneInfo(libelle: 'Redoublant', valeur: 'Oui'),
                  if (fiche.estSupervise)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: _BadgeSupervision(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EcranCarnetNotes(fiche: fiche)),
                  ),
                  icon: const Icon(Icons.grade_outlined),
                  label: const Text('Notes & bulletins'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EcranSuiviVieScolaire(fiche: fiche)),
                  ),
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Vie scolaire'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Suivi financier', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          historique.when(
            loading: () => const ShimmerCarteListe(),
            error: (erreur, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Suivi financier indisponible hors connexion pour le moment.'),
            ),
            data: (liste) => liste.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Aucune inscription active — rien à encaisser.'),
                  )
                : _CarteFinanciere(inscription: liste.first, estDirection: estDirection),
          ),
          const SizedBox(height: 20),
          Text('Historique de classes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          historique.when(
            loading: () => const ShimmerCarteListe(),
            error: (erreur, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text("Historique indisponible hors connexion pour l'instant."),
            ),
            data: (liste) => liste.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Aucune inscription enregistrée.'),
                  )
                : Column(children: [for (final i in liste) _CarteInscription(inscription: i)]),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _ouvrirEditionAdmin(BuildContext context, WidgetRef ref, FicheEleve fiche) {
    return showDialog<void>(
      context: context,
      builder: (context) => _DialogEditionAdmin(fiche: fiche),
    );
  }
}

/// Carte solde + bouton d'encaissement + statut boursier (M15quater) —
/// solde toujours calculé côté serveur, jamais recalculé ici.
class _CarteFinanciere extends ConsumerWidget {
  const _CarteFinanciere({required this.inscription, required this.estDirection});

  final Inscription inscription;
  final bool estDirection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solde = ref.watch(soldeScolariteProvider(inscription.id));
    final palette = context.palette;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            solde.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const Text('Solde indisponible hors connexion pour le moment.'),
              data: (s) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Montant dû : ${_formaterMontant(s.montantDu)}'),
                  Text('Montant payé : ${_formaterMontant(s.montantPaye)}'),
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
            if (inscription.boursier) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.school_outlined, size: 16, color: palette.premium),
                  const SizedBox(width: 6),
                  Text('Boursier cette année',
                      style: TextStyle(color: palette.premium, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EcranEncaissementScolarite(inscription: inscription)),
                    ),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Encaissements'),
                  ),
                ),
                if (estDirection) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await ref.read(scolariteRepositoryProvider).definirStatutBoursier(
                                inscriptionId: inscription.id,
                                boursier: !inscription.boursier,
                              );
                          ref.invalidate(inscriptionsDeFicheProvider(inscription.ficheEleveId));
                        } on ErreurScolarite {
                          // Signal non-bloquant : l'utilisateur retentera depuis l'écran rafraîchi.
                        }
                      },
                      icon: const Icon(Icons.school_outlined),
                      label: Text(inscription.boursier ? 'Retirer bourse' : 'Déclarer boursier'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogEditionAdmin extends ConsumerStatefulWidget {
  const _DialogEditionAdmin({required this.fiche});

  final FicheEleve fiche;

  @override
  ConsumerState<_DialogEditionAdmin> createState() => _DialogEditionAdminState();
}

class _DialogEditionAdminState extends ConsumerState<_DialogEditionAdmin> {
  late final TextEditingController _numeroClasseCtrl;
  late final TextEditingController _nomPereCtrl;
  late final TextEditingController _nomMereCtrl;
  late final TextEditingController _quartierCtrl;
  late final TextEditingController _urgenceNomCtrl;
  late final TextEditingController _urgenceTelCtrl;
  late bool _redoublant;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    final f = widget.fiche;
    _numeroClasseCtrl = TextEditingController(text: f.numeroClasse?.toString() ?? '');
    _nomPereCtrl = TextEditingController(text: f.nomPere ?? '');
    _nomMereCtrl = TextEditingController(text: f.nomMere ?? '');
    _quartierCtrl = TextEditingController(text: f.quartier ?? '');
    _urgenceNomCtrl = TextEditingController(text: f.personneUrgenceNom ?? '');
    _urgenceTelCtrl = TextEditingController(text: f.personneUrgenceTelephone ?? '');
    _redoublant = f.redoublant;
  }

  @override
  void dispose() {
    _numeroClasseCtrl.dispose();
    _nomPereCtrl.dispose();
    _nomMereCtrl.dispose();
    _quartierCtrl.dispose();
    _urgenceNomCtrl.dispose();
    _urgenceTelCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    setState(() => _enCours = true);
    try {
      final fiche = FicheEleve(
        id: widget.fiche.id,
        etablissementId: widget.fiche.etablissementId,
        matricule: widget.fiche.matricule,
        nom: widget.fiche.nom,
        prenom: widget.fiche.prenom,
        dateNaissance: widget.fiche.dateNaissance,
        numeroClasse: int.tryParse(_numeroClasseCtrl.text.trim()),
        nomPere: _nomPereCtrl.text.trim().isEmpty ? null : _nomPereCtrl.text.trim(),
        nomMere: _nomMereCtrl.text.trim().isEmpty ? null : _nomMereCtrl.text.trim(),
        quartier: _quartierCtrl.text.trim().isEmpty ? null : _quartierCtrl.text.trim(),
        personneUrgenceNom: _urgenceNomCtrl.text.trim().isEmpty ? null : _urgenceNomCtrl.text.trim(),
        personneUrgenceTelephone: _urgenceTelCtrl.text.trim().isEmpty ? null : _urgenceTelCtrl.text.trim(),
        redoublant: _redoublant,
      );
      await ref.read(scolariteRepositoryProvider).mettreAJourFicheAdmin(fiche);
      if (!mounted) return;
      ref.invalidate(inscriptionsDeFicheProvider(widget.fiche.id));
      Navigator.of(context).pop();
    } on ErreurScolarite {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Informations administratives'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _numeroClasseCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'N° dans la classe')),
            const SizedBox(height: 8),
            TextField(controller: _nomPereCtrl, decoration: const InputDecoration(labelText: 'Nom du père')),
            const SizedBox(height: 8),
            TextField(controller: _nomMereCtrl, decoration: const InputDecoration(labelText: 'Nom de la mère')),
            const SizedBox(height: 8),
            TextField(controller: _quartierCtrl, decoration: const InputDecoration(labelText: 'Quartier')),
            const SizedBox(height: 8),
            TextField(controller: _urgenceNomCtrl, decoration: const InputDecoration(labelText: 'Contact d\'urgence — nom')),
            const SizedBox(height: 8),
            TextField(controller: _urgenceTelCtrl, decoration: const InputDecoration(labelText: 'Contact d\'urgence — téléphone')),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Redoublant'),
              value: _redoublant,
              onChanged: (v) => setState(() => _redoublant = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _enCours ? null : _enregistrer,
          child: _enCours
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _LigneInfo extends StatelessWidget {
  const _LigneInfo({required this.libelle, required this.valeur});

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(libelle, style: TextStyle(color: context.palette.encreSecondaire)),
          ),
          Expanded(child: Text(valeur, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _BadgeSupervision extends StatelessWidget {
  const _BadgeSupervision();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.palette.premium.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 14, color: context.palette.premium),
          const SizedBox(width: 4),
          Text('Compte supervisé',
              style: TextStyle(color: context.palette.premium, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CarteInscription extends StatelessWidget {
  const _CarteInscription({required this.inscription});

  final Inscription inscription;

  @override
  Widget build(BuildContext context) {
    final classe = inscription.classe;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.class_outlined, color: context.palette.primaire),
        title: Text(classe?.nom ?? 'Classe inconnue'),
        subtitle: Text('Inscrit le ${EcranFicheEleve._formatDate(inscription.dateInscription)}'),
        trailing: classe == null
            ? null
            : IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EcranDetailClasse(classe: classe)),
                ),
              ),
      ),
    );
  }
}
