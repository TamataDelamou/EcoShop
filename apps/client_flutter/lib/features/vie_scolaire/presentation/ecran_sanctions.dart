import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../scolarite/domain/fiche_eleve.dart';
import '../application/vie_scolaire_providers.dart';
import '../domain/enums_vie_scolaire.dart';
import '../domain/sanction.dart';
import 'widgets/badge_signal_ia.dart';

/// Sanctions d'un élève (M7) — éducatives, jamais punitives par défaut.
///
/// Une sanction d'origine IA reste marquée « proposée, à valider » tant
/// qu'aucun humain ne l'a validée : le serveur l'impose déjà (trigger
/// `sanctions_verifie_validation`), l'écran l'explicite pour l'utilisateur.
///
/// Déclaration manuelle et changement de statut (écart §11 de l'audit,
/// point #5 — `proposerSanction()`/`changerStatutSanction()` existaient déjà
/// côté repository/RLS, seul l'écran manquait) : mêmes règles de visibilité
/// que le reste de l'écran (`estDirection`, déjà utilisé pour « Valider »)
/// — aucune notion de permission plus fine n'est câblée ailleurs côté
/// Flutter dans ce module, l'introduire ici seul serait une incohérence.
class EcranSanctions extends ConsumerWidget {
  const EcranSanctions({super.key, required this.fiche, this.anneeScolaireId});

  final FicheEleve fiche;

  /// Requis pour déclarer une nouvelle sanction (`Sanction.anneeScolaireId`) ;
  /// nul tant que l'année scolaire de la fiche n'a pas pu être résolue (voir
  /// l'appelant, `EcranSuiviVieScolaire`) — le bouton de déclaration reste
  /// alors simplement masqué, jamais une erreur.
  final String? anneeScolaireId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sanctions = ref.watch(sanctionsDeFicheProvider(fiche.id));
    final estDirection = ref.watch(profilProvider).value?.roleRacine == RoleRacine.direction;

    return Scaffold(
      appBar: AppBar(title: Text('Sanctions — ${fiche.prenom}')),
      floatingActionButton: estDirection && anneeScolaireId != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Déclarer une sanction'),
              onPressed: () => _ouvrirFormulaire(context, ref),
            )
          : null,
      body: sanctions.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Sanctions indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucune sanction enregistrée.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) => EntreeAnimee(
                  index: i,
                  enfant: _CarteSanction(sanction: liste[i], peutGerer: estDirection),
                ),
              ),
      ),
    );
  }

  Future<void> _ouvrirFormulaire(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FormulaireSanction(fiche: fiche, anneeScolaireId: anneeScolaireId!),
    );
    ref.invalidate(sanctionsDeFicheProvider(fiche.id));
  }
}

class _CarteSanction extends ConsumerWidget {
  const _CarteSanction({required this.sanction, required this.peutGerer});

  final Sanction sanction;
  final bool peutGerer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(sanction.typeSanction.libelle,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                _PastilleStatutSanction(statut: sanction.statut),
              ],
            ),
            const SizedBox(height: 6),
            Text(sanction.motif),
            if (sanction.contexteEducatif != null) ...[
              const SizedBox(height: 4),
              Text(
                sanction.contexteEducatif!,
                style: TextStyle(color: context.palette.encreSecondaire, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            if (sanction.origine == OrigineSanction.ia) ...[
              BadgeSignalIa(
                texte: sanction.estPropositionIaNonValidee
                    ? 'Proposition IA — à valider par un humain'
                    : 'Origine IA — validée par un humain',
              ),
              const SizedBox(height: 8),
            ],
            if (peutGerer && sanction.estPropositionIaNonValidee)
              FilledButton.icon(
                onPressed: () async {
                  final profil = ref.read(profilProvider).value;
                  if (profil == null) return;
                  await ref
                      .read(vieScolaireRepositoryProvider)
                      .validerSanction(sanction.id, valideePar: profil.id);
                  ref.invalidate(sanctionsDeFicheProvider(sanction.ficheEleveId));
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Valider la proposition'),
              ),
            // Le changement de statut (notifiée/exécutée/annulée — « levée »
            // incluse) n'a de sens qu'une fois la sanction réellement
            // actionnable : jamais sur une proposition IA encore à valider,
            // le trigger serveur `sanctions_verifie_validation` le
            // rejetterait de toute façon pour l'origine IA.
            if (peutGerer && !sanction.estPropositionIaNonValidee)
              Align(
                alignment: Alignment.centerRight,
                child: PopupMenuButton<StatutSanction>(
                  tooltip: 'Changer le statut',
                  onSelected: (statut) async {
                    await ref
                        .read(vieScolaireRepositoryProvider)
                        .changerStatutSanction(sanction.id, statut.code);
                    ref.invalidate(sanctionsDeFicheProvider(sanction.ficheEleveId));
                  },
                  itemBuilder: (context) => [
                    for (final statut in StatutSanction.values)
                      if (statut != sanction.statut && statut != StatutSanction.proposee)
                        PopupMenuItem(value: statut, child: Text(libelleStatutSanction(statut))),
                  ],
                  child: const Chip(
                    avatar: Icon(Icons.edit_outlined, size: 16),
                    label: Text('Changer le statut'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Libellé partagé entre la pastille de statut et le menu de changement —
/// une seule source de vérité pour ce mapping.
String libelleStatutSanction(StatutSanction statut) => switch (statut) {
      StatutSanction.proposee => 'Proposée',
      StatutSanction.notifiee => 'Notifiée',
      StatutSanction.executee => 'Exécutée',
      StatutSanction.annulee => 'Annulée (levée)',
    };

class _PastilleStatutSanction extends StatelessWidget {
  const _PastilleStatutSanction({required this.statut});

  final StatutSanction statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutSanction.proposee => context.palette.premium,
      StatutSanction.notifiee => context.palette.accent,
      StatutSanction.executee => context.palette.primaire,
      StatutSanction.annulee => context.palette.encreSecondaire,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        libelleStatutSanction(statut),
        style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Formulaire de déclaration manuelle — origine `humaine` toujours (seule
/// l'IA passe par `demarrer_analyse_risque_echec`/`recommander_sanction_
/// educative`, jamais ce formulaire), donc aucune contrainte de validation
/// serveur à respecter ici (le trigger `sanctions_verifie_validation` ne
/// s'applique qu'à `origine = 'ia'`).
class _FormulaireSanction extends ConsumerStatefulWidget {
  const _FormulaireSanction({required this.fiche, required this.anneeScolaireId});

  final FicheEleve fiche;
  final String anneeScolaireId;

  @override
  ConsumerState<_FormulaireSanction> createState() => _FormulaireSanctionState();
}

class _FormulaireSanctionState extends ConsumerState<_FormulaireSanction> {
  TypeSanction _type = TypeSanction.avertissement;
  StatutSanction _statutInitial = StatutSanction.notifiee;
  DateTime _dateDebut = DateTime.now();
  DateTime? _dateFin;
  final _motifCtrl = TextEditingController();
  final _contexteCtrl = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _motifCtrl.dispose();
    _contexteCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirDate({required bool debut}) async {
    final choisie = await showDatePicker(
      context: context,
      initialDate: debut ? _dateDebut : (_dateFin ?? _dateDebut),
      firstDate: DateTime(_dateDebut.year - 1),
      lastDate: DateTime(_dateDebut.year + 2),
    );
    if (choisie == null) return;
    setState(() {
      if (debut) {
        _dateDebut = choisie;
        if (_dateFin != null && _dateFin!.isBefore(_dateDebut)) _dateFin = null;
      } else {
        _dateFin = choisie;
      }
    });
  }

  Future<void> _enregistrer() async {
    final motif = _motifCtrl.text.trim();
    if (motif.isEmpty) {
      setState(() => _erreur = 'Le motif est obligatoire.');
      return;
    }
    final profil = ref.read(profilProvider).value;
    if (profil == null) return;

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final sanction = construireSanctionDeclaree(
        etablissementId: widget.fiche.etablissementId,
        ficheEleveId: widget.fiche.id,
        anneeScolaireId: widget.anneeScolaireId,
        decisionnaireId: profil.id,
        typeSanction: _type,
        motif: motif,
        dateDebut: _dateDebut,
        dateFin: _dateFin,
        contexteEducatif: _contexteCtrl.text.trim().isEmpty ? null : _contexteCtrl.text.trim(),
        statut: _statutInitial,
      );
      await ref.read(vieScolaireRepositoryProvider).proposerSanction(sanction);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = 'Envoi impossible : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Déclarer une sanction'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<TypeSanction>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type de sanction'),
              items: [
                for (final type in TypeSanction.values)
                  DropdownMenuItem(value: type, child: Text(type.libelle)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _motifCtrl,
              decoration: const InputDecoration(labelText: 'Motif'),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contexteCtrl,
              decoration: const InputDecoration(labelText: 'Contexte éducatif (optionnel)'),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date de début'),
              subtitle: Text(_formatDate(_dateDebut)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () => _choisirDate(debut: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date de fin (optionnel)'),
              subtitle: Text(_dateFin == null ? 'Non définie' : _formatDate(_dateFin!)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () => _choisirDate(debut: false),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<StatutSanction>(
              initialValue: _statutInitial,
              decoration: const InputDecoration(labelText: 'Statut initial'),
              items: [
                for (final statut in StatutSanction.values)
                  if (statut != StatutSanction.proposee)
                    DropdownMenuItem(value: statut, child: Text(libelleStatutSanction(statut))),
              ],
              onChanged: (v) => setState(() => _statutInitial = v ?? _statutInitial),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(_erreur!, style: TextStyle(color: context.palette.erreur)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _enCours ? null : _enregistrer,
          child: _enCours
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Déclarer'),
        ),
      ],
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
