import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../auth/application/auth_providers.dart';
import '../application/creation_etablissement_providers.dart';
import '../domain/demande_etablissement.dart';
import 'ecran_demande_etablissement.dart';

/// Carte « fondateur » de l'écran de choix du rôle (REG-04) : invitation à
/// demander la création de son école, puis suivi de la demande jusqu'à la
/// validation par Global Service Groupe.
class CarteDemandeEtablissement extends ConsumerWidget {
  const CarteDemandeEtablissement({super.key});

  Future<void> _ouvrirFormulaire(BuildContext context) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranDemandeEtablissement()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demande = ref.watch(maDemandeEtablissementProvider);
    final palette = context.palette;

    // Lecture impossible (hors connexion…) : on propose simplement la demande.
    final d = demande.valueOrNull;

    final Widget contenu;
    if (d == null) {
      contenu = _Cadre(
        key: const ValueKey('aucune'),
        couleur: palette.primaire,
        icone: Icons.add_business_rounded,
        titre: 'Vous dirigez une école ?',
        texte: 'Demandez la création de votre établissement : il sera validé par Global Service Groupe.',
        action: OutlinedButton.icon(
          key: const Key('bouton_creer_etablissement'),
          onPressed: () => _ouvrirFormulaire(context),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Créer mon établissement'),
        ),
      );
    } else {
      contenu = switch (d.statut) {
        StatutDemandeEtablissement.enAttente => _CarteSuivi(
            key: const ValueKey('en_attente'),
            demande: d,
            surActualiser: () => ref.invalidate(maDemandeEtablissementProvider),
          ),
        StatutDemandeEtablissement.acceptee => _Cadre(
            key: const ValueKey('acceptee'),
            couleur: palette.succes,
            icone: Icons.verified_rounded,
            titre: '${d.nomEtablissement} est validé',
            texte: 'Votre espace de Direction est prêt.',
            action: FilledButton(
              onPressed: () => ref.rafraichirSession(),
              child: const Text('Accéder à mon établissement'),
            ),
          ),
        StatutDemandeEtablissement.refusee => _Cadre(
            key: const ValueKey('refusee'),
            couleur: palette.erreur,
            icone: Icons.info_outline_rounded,
            titre: 'Demande pour ${d.nomEtablissement} non retenue',
            texte: 'Motif : ${d.motifRefus ?? 'non précisé'}',
            action: OutlinedButton.icon(
              onPressed: () => _ouvrirFormulaire(context),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Soumettre une nouvelle demande'),
            ),
          ),
      };
    }

    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: contenu);
  }
}

class _Cadre extends StatelessWidget {
  const _Cadre({
    super.key,
    required this.couleur,
    required this.icone,
    required this.titre,
    required this.texte,
    required this.action,
  });

  final Color couleur;
  final IconData icone;
  final String titre;
  final String texte;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: couleur.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icone, color: couleur),
              const SizedBox(width: 10),
              Expanded(child: Text(titre, style: const TextStyle(fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 6),
          Text(texte, style: TextStyle(color: palette.encreSecondaire)),
          const SizedBox(height: 12),
          action,
        ],
      ),
    );
  }
}

class _CarteSuivi extends StatelessWidget {
  const _CarteSuivi({super.key, required this.demande, required this.surActualiser});

  final DemandeEtablissement demande;
  final VoidCallback surActualiser;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final d = demande.creeLe.toLocal();
    final date = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    Widget etape(String texte, {required bool faite, bool enCours = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                faite ? Icons.check_circle_rounded : (enCours ? Icons.hourglass_top_rounded : Icons.circle_outlined),
                size: 18,
                color: faite ? palette.succes : (enCours ? palette.primaire : palette.bordure),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(texte)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.primaire.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(demande.nomEtablissement, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text('${demande.ville} · demande du $date', style: TextStyle(color: palette.encreSecondaire, fontSize: 12)),
          const SizedBox(height: 12),
          etape('Demande envoyée', faite: true),
          etape('Examen par Global Service Groupe', faite: false, enCours: true),
          etape('Ouverture de votre espace de Direction', faite: false),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('bouton_actualiser_demande'),
              onPressed: surActualiser,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Actualiser'),
            ),
          ),
        ],
      ),
    );
  }
}
