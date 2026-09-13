import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../application/rh_providers.dart';
import '../domain/employe.dart';
import '../domain/enums_rh.dart';
import 'ecran_absences_personnel.dart';
import 'ecran_annuaire_personnel.dart' show heroAvatarEmploye;
import 'ecran_conges.dart';
import 'ecran_contrats.dart';
import 'ecran_paie.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/pastille_statut_employe.dart';

/// Fiche employé (M8) — infos, contrat en cours, charge horaire, et pour la
/// RH/direction : signaux IA (risque de turn-over, recommandation de
/// formation), toujours présentés comme des signaux à valider humainement.
class EcranFicheEmploye extends ConsumerStatefulWidget {
  const EcranFicheEmploye({super.key, required this.employe});

  final Employe employe;

  @override
  ConsumerState<EcranFicheEmploye> createState() => _EcranFicheEmployeState();
}

class _EcranFicheEmployeState extends ConsumerState<EcranFicheEmploye> {
  late Employe _employe;

  @override
  void initState() {
    super.initState();
    _employe = widget.employe;
  }

  Future<void> _modifierContact() async {
    final resultat = await showDialog<Employe>(
      context: context,
      builder: (_) => _DialogueContact(employe: _employe),
    );
    if (resultat == null) return;
    try {
      await ref.read(rhRepositoryProvider).creerOuModifierEmploye(resultat);
      ref.invalidate(employeProvider(_employe.id));
      ref.invalidate(employesEtablissementProvider);
      if (mounted) setState(() => _employe = resultat);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'enregistrer le contact — réessayez.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final employe = _employe;
    final profil = ref.watch(profilProvider).value;
    final estRh = profil?.roleRacine == RoleRacine.direction;
    final estSoiMeme = profil != null && profil.id == employe.profileId;

    final contrats = ref.watch(contratsDeEmployeProvider(employe.id));
    final chargeHoraire = ref.watch(chargeHoraireProvider(employe.id));

    return Scaffold(
      appBar: AppBar(title: Text(employe.nomAffiche ?? employe.matricule)),
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
                      Hero(
                        tag: heroAvatarEmploye(employe.id),
                        child: CircleAvatar(
                          radius: 26,
                          backgroundColor: context.palette.primaire.withValues(alpha: 0.12),
                          child: Text(
                            (employe.nomAffiche?.trim().isNotEmpty ?? false)
                                ? employe.nomAffiche!.trim().substring(0, 1).toUpperCase()
                                : employe.matricule.substring(0, 1).toUpperCase(),
                            style: TextStyle(color: context.palette.primaire, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(employe.nomAffiche ?? employe.matricule,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                      ),
                      PastilleStatutEmploye(statut: employe.statut),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Matricule : ${employe.matricule}'),
                  Text('Catégorie : ${employe.categorie.libelle}'),
                  Text('Embauché le ${_formatDate(employe.dateEmbauche)}'),
                  const SizedBox(height: 12),
                  chargeHoraire.when(
                    loading: () => const ShimmerBloc(hauteur: 14, largeur: 160),
                    error: (erreur, _) => const SizedBox.shrink(),
                    data: (heures) => Text(
                      'Charge horaire hebdomadaire : $heures h',
                      style: TextStyle(color: context.palette.encreSecondaire),
                    ),
                  ),
                  if (estRh) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Contact', style: Theme.of(context).textTheme.titleSmall),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Modifier le contact',
                          onPressed: _modifierContact,
                        ),
                      ],
                    ),
                    Text(
                      'Téléphone (usage interne) : ${employe.telephone?.isNotEmpty ?? false ? employe.telephone : 'Non renseigné'}',
                      style: TextStyle(color: context.palette.encreSecondaire),
                    ),
                    Text(
                      'Email (affiché sur le bulletin, matières secondaires) : ${employe.email?.isNotEmpty ?? false ? employe.email : 'Non renseigné'}',
                      style: TextStyle(color: context.palette.encreSecondaire),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          contrats.when(
            loading: () => const ShimmerCarteListe(),
            error: (erreur, _) => const SizedBox.shrink(),
            data: (liste) {
              final actuel = liste.where((c) => c.estEnCours).toList();
              if (actuel.isEmpty) return const SizedBox.shrink();
              final contrat = actuel.first;
              return Card(
                child: ListTile(
                  leading: Icon(Icons.description_outlined, color: context.palette.primaire),
                  title: Text('Contrat en cours — ${contrat.type.libelle}'),
                  subtitle: Text(
                    contrat.dateFin == null
                        ? 'Depuis le ${_formatDate(contrat.dateDebut)}'
                        : 'Du ${_formatDate(contrat.dateDebut)} au ${_formatDate(contrat.dateFin!)}',
                  ),
                ),
              );
            },
          ),
          if (estRh) ...[
            const SizedBox(height: 16),
            _CarteScoreTurnover(employeId: employe.id),
            if (employe.categorie == CategorieEmploye.enseignant) ...[
              const SizedBox(height: 16),
              _CarteRecommandationFormation(employeId: employe.id),
            ],
          ],
          const SizedBox(height: 24),
          Text('Dossier', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _LienDossier(
            icone: Icons.description_outlined,
            libelle: 'Contrats',
            visible: estRh,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranContrats(employe: employe)),
            ),
          ),
          _LienDossier(
            icone: Icons.beach_access_outlined,
            libelle: 'Congés',
            visible: estRh || estSoiMeme,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranConges(employe: employe, estRh: estRh)),
            ),
          ),
          _LienDossier(
            icone: Icons.event_busy_outlined,
            libelle: 'Absences',
            visible: estRh || estSoiMeme,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranAbsencesPersonnel(employe: employe, estRh: estRh)),
            ),
          ),
          _LienDossier(
            icone: Icons.payments_outlined,
            libelle: 'Paie',
            visible: estRh || estSoiMeme,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranPaie(employe: employe)),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// Édition du contact (D5) — téléphone (usage interne, jamais imprimé) et
/// email (affiché sur le bulletin pour les matières du secondaire).
class _DialogueContact extends StatefulWidget {
  const _DialogueContact({required this.employe});

  final Employe employe;

  @override
  State<_DialogueContact> createState() => _DialogueContactState();
}

class _DialogueContactState extends State<_DialogueContact> {
  late final TextEditingController _telephoneCtrl =
      TextEditingController(text: widget.employe.telephone ?? '');
  late final TextEditingController _emailCtrl = TextEditingController(text: widget.employe.email ?? '');

  @override
  void dispose() {
    _telephoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier le contact'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _telephoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Téléphone',
              helperText: 'Usage interne — jamais imprimé sur un document',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              helperText: 'Affiché sur le bulletin (tableau par matière)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final telephone = _telephoneCtrl.text.trim();
            final email = _emailCtrl.text.trim();
            Navigator.of(context).pop(
              Employe(
                id: widget.employe.id,
                etablissementId: widget.employe.etablissementId,
                profileId: widget.employe.profileId,
                matricule: widget.employe.matricule,
                categorie: widget.employe.categorie,
                dateEmbauche: widget.employe.dateEmbauche,
                statut: widget.employe.statut,
                nomAffiche: widget.employe.nomAffiche,
                telephone: telephone.isEmpty ? null : telephone,
                email: email.isEmpty ? null : email,
              ),
            );
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _LienDossier extends StatelessWidget {
  const _LienDossier({
    required this.icone,
    required this.libelle,
    required this.visible,
    required this.onTap,
  });

  final IconData icone;
  final String libelle;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icone, color: context.palette.primaire),
        title: Text(libelle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _CarteScoreTurnover extends ConsumerWidget {
  const _CarteScoreTurnover({required this.employeId});

  final String employeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score = ref.watch(scoreTurnoverProvider(employeId));

    return score.when(
      loading: () => const ShimmerCarteListe(),
      error: (erreur, _) => const SizedBox.shrink(),
      data: (valeur) {
        final palette = context.palette;
        final couleur = valeur >= 0.7
            ? palette.erreur
            : (valeur >= 0.4 ? palette.accent : palette.succes);
        return GlassCard(
          couleurBordure: couleur.withValues(alpha: 0.3),
          enfant: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Risque de turn-over', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text(
                    '${(valeur * 100).toStringAsFixed(0)} %',
                    style: TextStyle(color: couleur, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const BadgeSignalIa(texte: 'Signal IA — jamais un motif de décision seul'),
            ],
          ),
        );
      },
    );
  }
}

class _CarteRecommandationFormation extends ConsumerWidget {
  const _CarteRecommandationFormation({required this.employeId});

  final String employeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final structure = ref.watch(structureEtablissementProvider(null));

    return structure.when(
      loading: () => const SizedBox.shrink(),
      error: (erreur, _) => const SizedBox.shrink(),
      data: (donnees) {
        final anneeId = donnees?.anneeCourante?.id;
        if (anneeId == null) return const SizedBox.shrink();
        return _Recommandations(employeId: employeId, anneeId: anneeId);
      },
    );
  }
}

class _Recommandations extends ConsumerWidget {
  const _Recommandations({required this.employeId, required this.anneeId});

  final String employeId;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommandations = ref.watch(recommanderFormationProvider((employeId: employeId, anneeId: anneeId)));

    return recommandations.when(
      loading: () => const ShimmerCarteListe(),
      error: (erreur, _) => const SizedBox.shrink(),
      data: (liste) {
        if (liste.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Formations recommandées', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const BadgeSignalIa(texte: 'Signal IA — décision RH/direction'),
                const SizedBox(height: 8),
                for (final r in liste)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('${r.code} — ${r.libelle}'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
