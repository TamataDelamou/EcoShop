import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../application/creation_etablissement_providers.dart';
import '../domain/demande_etablissement.dart';

/// Backoffice GSG — validation des demandes de création d'établissement
/// (REG-04, cahier §30.1). Réservé à l'administrateur GSG ; l'autorité
/// réelle reste la RPC `traiter_demande_etablissement`.
class EcranValidationEtablissementsGsg extends ConsumerStatefulWidget {
  const EcranValidationEtablissementsGsg({super.key});

  @override
  ConsumerState<EcranValidationEtablissementsGsg> createState() => _EcranValidationEtablissementsGsgState();
}

class _EcranValidationEtablissementsGsgState extends ConsumerState<EcranValidationEtablissementsGsg> {
  final Set<String> _enCours = {};

  Future<void> _decider(DemandeATraiter d, {required bool accepter}) async {
    String? motif;
    if (accepter) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Valider ${d.nomEtablissement} ?'),
          content: const Text(
            "L'établissement sera créé et le demandeur deviendra sa Direction. Cette action est définitive.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Valider')),
          ],
        ),
      );
      if (ok != true) return;
    } else {
      motif = await _demanderMotif(d);
      if (motif == null) return;
    }
    if (!mounted) return;

    setState(() => _enCours.add(d.id));
    try {
      await ref.read(creationEtablissementRepositoryProvider).traiter(
            demandeId: d.id,
            accepter: accepter,
            motif: motif,
          );
      ref.invalidate(demandesEtablissementATraiterProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accepter ? '${d.nomEtablissement} est créé.' : 'Demande refusée, motif transmis.'),
        ));
      }
    } on ErreurCreationEtablissement catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
      }
    } finally {
      if (mounted) setState(() => _enCours.remove(d.id));
    }
  }

  Future<String?> _demanderMotif(DemandeATraiter d) {
    final controleur = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Refuser ${d.nomEtablissement} ?'),
        content: TextField(
          key: const Key('champ_motif_refus'),
          controller: controleur,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motif (communiqué au demandeur)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final t = controleur.text.trim();
              if (t.isNotEmpty) Navigator.of(c).pop(t);
            },
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final demandes = ref.watch(demandesEtablissementATraiterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Demandes d'établissement")),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(demandesEtablissementATraiterProvider.future),
        child: demandes.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Demandes indisponibles pour le moment.', style: TextStyle(color: palette.encreSecondaire)),
              ),
            ],
          ),
          data: (liste) => liste.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 80),
                    Icon(Icons.inbox_rounded, size: 56, color: palette.encreSecondaire.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    Center(
                      child: Text('Aucune demande en attente.', style: TextStyle(color: palette.encreSecondaire)),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: liste.length,
                  itemBuilder: (context, i) => EntreeAnimee(
                    index: i,
                    enfant: _CarteDemande(
                      demande: liste[i],
                      enCours: _enCours.contains(liste[i].id),
                      surAccepter: () => _decider(liste[i], accepter: true),
                      surRefuser: () => _decider(liste[i], accepter: false),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _CarteDemande extends StatelessWidget {
  const _CarteDemande({
    required this.demande,
    required this.enCours,
    required this.surAccepter,
    required this.surRefuser,
  });

  final DemandeATraiter demande;
  final bool enCours;
  final VoidCallback surAccepter;
  final VoidCallback surRefuser;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final d = demande;
    final c = d.creeLe.toLocal();
    Widget ligne(IconData icone, String texte) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, size: 16, color: palette.encreSecondaire),
              const SizedBox(width: 8),
              Expanded(child: Text(texte, style: const TextStyle(fontSize: 13))),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: palette.primaire.withValues(alpha: 0.12),
                  child: Icon(Icons.school_rounded, color: palette.primaire),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.nomEtablissement, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(
                        '${d.ville}, ${d.paysNom ?? d.paysCode} · reçue le '
                        '${c.day.toString().padLeft(2, '0')}/${c.month.toString().padLeft(2, '0')}/${c.year}',
                        style: TextStyle(color: palette.encreSecondaire, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ligne(Icons.person_outline_rounded,
                'Demandeur : ${d.demandeurNom ?? 'non renseigné'} (${d.demandeurIdentifiant ?? '-'})'),
            ligne(Icons.phone_outlined, d.telephone),
            if (d.email != null) ligne(Icons.alternate_email_rounded, d.email!),
            if (d.adresse != null) ligne(Icons.place_outlined, d.adresse!),
            if (d.effectifEstime != null) ligne(Icons.groups_outlined, '${d.effectifEstime} élèves (estimation)'),
            ligne(
              Icons.verified_outlined,
              d.numeroAutorisation == null
                  ? "Aucun numéro d'autorisation d'ouverture fourni"
                  : "Autorisation d'ouverture : ${d.numeroAutorisation}",
            ),
            if (d.message != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: palette.fond, borderRadius: BorderRadius.circular(10)),
                child: Text('« ${d.message} »', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('refuser_${d.id}'),
                    onPressed: enCours ? null : surRefuser,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: Key('accepter_${d.id}'),
                    onPressed: enCours ? null : surAccepter,
                    icon: enCours
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_rounded),
                    label: const Text('Valider'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
