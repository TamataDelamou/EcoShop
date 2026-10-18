import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/bandeau_synchronisation.dart';
import '../../paiement_mobile/application/paiement_mobile_providers.dart';
import '../../paiement_mobile/presentation/ecran_paiement_orange_money.dart';
import '../application/inscription_en_ligne_providers.dart';
import '../domain/inscription_en_ligne.dart';
import 'widgets/elements_inscription.dart';
import 'widgets/prise_piece.dart';

/// Suivi d'un dossier d'inscription par la famille : étape, message de
/// l'école, paiement des frais, pièces, retrait.
class EcranDossierInscription extends ConsumerWidget {
  const EcranDossierInscription({super.key, required this.demandeId});

  final String demandeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dossiers = ref.watch(mesDemandesInscriptionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Dossier d'inscription")),
      body: Column(
        children: [
          const BandeauSynchronisation(),
          Expanded(
            child: dossiers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(padding: const EdgeInsets.all(24), child: Text(messageErreur(e), textAlign: TextAlign.center)),
              ),
              data: (liste) {
                final d = liste.where((x) => x.id == demandeId).firstOrNull;
                if (d == null) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: () => ref.invalidate(mesDemandesInscriptionProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualiser'),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(mesDemandesInscriptionProvider),
                  child: _Contenu(demande: d),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Contenu extends ConsumerWidget {
  const _Contenu({required this.demande});

  final DemandeInscription demande;

  Future<void> _deposer(BuildContext context, WidgetRef ref, PieceAEnvoyer piece) async {
    try {
      await ref.read(inscriptionEnLigneRepositoryProvider).deposerPiece(demande.id, piece);
      ref.invalidate(mesDemandesInscriptionProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageErreur(e))));
    }
  }

  Future<void> _retirer(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Retirer la demande ?'),
        content: const Text("La place éventuellement réservée sera libérée pour une autre famille."),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(inscriptionEnLigneRepositoryProvider).retirer(demande.id);
      ref.invalidate(mesDemandesInscriptionProvider);
      ref.invalidate(reinscriptionsPossiblesProvider);
      if (context.mounted && demande.enAttenteEnvoi) Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageErreur(e))));
    }
  }

  Future<void> _ouvrirPiece(BuildContext context, WidgetRef ref, String chemin) async {
    try {
      final url = await ref.read(inscriptionEnLigneRepositoryProvider).lienPiece(chemin);
      await ref.read(lanceurUrlProvider).ouvrir(url);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageErreur(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final d = demande;
    final attendues = d.piecesAttendues;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.nomComplet, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 2),
                Text(
                  [
                    d.estReinscription ? 'Réinscription' : 'Nouvel élève',
                    if (d.niveauNom != null) d.niveauNom!,
                    if (d.etablissementNom != null) d.etablissementNom!,
                  ].join(' · '),
                  style: TextStyle(color: palette.encreSecondaire),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    PastilleStatut(statut: d.statut, enAttenteEnvoi: d.enAttenteEnvoi),
                    const Spacer(),
                    Text('N° ${d.numeroDossier}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                if (!d.enAttenteEnvoi && d.numeroProvisoire != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Saisi sans réseau sous le n° ${d.numeroProvisoire}',
                        style: TextStyle(color: palette.encreSecondaire, fontSize: 12)),
                  ),
                const SizedBox(height: 10),
                Text(explicationStatut(d)),
              ],
            ),
          ),
        ),
        if (d.motif != null && d.motif!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Encadre(texte: "Message de l'école : ${d.motif}", icone: Icons.forum_outlined, couleur: palette.accent),
        ],
        if (d.aRegler) ...[
          const SizedBox(height: 16),
          Text("Frais d'inscription", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(montant(d.montantARegler, d.devise),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: palette.primaire)),
          if (d.offreExpireLe != null)
            Text('À régler avant le ${dateCourte(d.offreExpireLe!)}', style: TextStyle(color: palette.encreSecondaire)),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('payer_frais_inscription'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF7900),
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EcranPaiementOrangeMoney.fraisInscription(
                  demandeId: d.id,
                  nomEleve: d.nomComplet,
                  numeroDossier: d.numeroDossier,
                  montant: d.montantARegler,
                  devise: d.devise,
                  auSucces: (r) {
                    r.invalidate(mesDemandesInscriptionProvider);
                    r.invalidate(reinscriptionsPossiblesProvider);
                  },
                ),
              ),
            ),
            icon: const Icon(Icons.phone_iphone_rounded),
            label: const Text('Payer avec Orange Money'),
          ),
          const SizedBox(height: 6),
          Text(
            "Ou réglez à l'école (espèces) en donnant le numéro de dossier ${d.numeroDossier}.",
            style: TextStyle(color: palette.encreSecondaire, fontSize: 12),
          ),
        ],
        if (attendues.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Pièces du dossier', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final p in attendues)
            PrisePiece(
              piece: p,
              prise: d.pieces.containsKey(p.code),
              enAttenteEnvoi: d.pieces[p.code] == '',
              onPrise: d.statut.accepteDesPieces ? (piece) => _deposer(context, ref, piece) : null,
              onOuvrir: (d.pieces[p.code] ?? '').isEmpty ? null : () => _ouvrirPiece(context, ref, d.pieces[p.code]!),
            ),
        ],
        if (!d.statut.estClos) ...[
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _retirer(context, ref),
            style: OutlinedButton.styleFrom(foregroundColor: palette.erreur),
            icon: const Icon(Icons.undo),
            label: const Text('Retirer la demande'),
          ),
        ],
      ],
    );
  }
}
