import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/glass_card.dart';
import '../application/parent_ia_providers.dart';
import '../domain/parent_ia_config.dart';
import '../domain/parent_ia_repository.dart';
import 'ecran_parent_ia_declaration_usage.dart';
import 'ecran_parent_ia_historique.dart';

/// PARENT IA — écran d'activation, ÉLÈVE UNIQUEMENT (M16, sous-livrable
/// 4/7, cahier §15.3). Affiche le consentement explicite AVANT toute
/// activation, puis le compte à rebours du verrou de 30 jours — sans aucun
/// moyen de le contourner depuis l'UI : le bouton "Désactiver" appelle
/// `desactiver_parent_ia`, qui refuse tant que le délai n'est pas écoulé
/// (voir le message d'erreur affiché tel quel).
class EcranParentIaActivation extends ConsumerStatefulWidget {
  const EcranParentIaActivation({super.key, required this.ficheEleveId});

  final String ficheEleveId;

  @override
  ConsumerState<EcranParentIaActivation> createState() =>
      _EcranParentIaActivationState();
}

class _EcranParentIaActivationState
    extends ConsumerState<EcranParentIaActivation> {
  bool _consentementCoche = false;
  bool _enCours = false;

  Future<void> _activer() async {
    setState(() => _enCours = true);
    try {
      await ref
          .read(parentIaRepositoryProvider)
          .activer(
            ficheEleveId: widget.ficheEleveId,
            consentement: _consentementCoche,
          );
      ref.invalidate(parentIaConfigProvider(widget.ficheEleveId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('PARENT IA activé — verrouillé pour 30 jours.'),
          backgroundColor: context.palette.succes,
        ),
      );
    } on ErreurParentIa catch (e) {
      _afficherErreur(e);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _tenterDesactiver() async {
    setState(() => _enCours = true);
    try {
      await ref
          .read(parentIaRepositoryProvider)
          .desactiver(widget.ficheEleveId);
      ref.invalidate(parentIaConfigProvider(widget.ficheEleveId));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PARENT IA désactivé.')));
    } on ErreurParentIa catch (e) {
      _afficherErreur(e);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _afficherErreur(ErreurParentIa e) {
    if (!mounted) return;
    // Le détail (ex. « PARENT_IA_VERROUILLE 17 jour(s) restant(s). ») vient
    // du serveur — affiché tel quel, jamais reformulé côté client.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.detail ?? e.code),
        backgroundColor: context.palette.erreur,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(parentIaConfigProvider(widget.ficheEleveId));

    return Scaffold(
      appBar: AppBar(title: const Text('PARENT IA')),
      body: config.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (erreur, _) => const Center(
          child: Text('Configuration indisponible pour le moment.'),
        ),
        data: (c) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EnTete(actif: c.actif),
            const SizedBox(height: 20),
            if (c.actif) ..._blocsActif(c) else ..._blocsInactif(),
          ],
        ),
      ),
    );
  }

  List<Widget> _blocsActif(ParentIaConfig c) {
    return [
      GlassCard(
        enfant: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Badge(
                  texte: 'Actif',
                  couleur: context.palette.succes,
                  icone: Icons.check_circle,
                ),
                const Spacer(),
                if (c.estVerrouille)
                  _Badge(
                    texte: '${c.joursRestantsAvantDeverrouillage} j verrou',
                    couleur: context.palette.accent,
                    icone: Icons.lock_outline_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Activé le ${c.dateActivation != null ? _formatDate(c.dateActivation!) : '—'}',
              style: TextStyle(
                color: context.palette.encreSecondaire,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        icon: const Icon(Icons.edit_note_outlined),
        label: const Text('Déclarer mon usage'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EcranParentIaDeclarationUsage(
              ficheEleveId: widget.ficheEleveId,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.history_outlined),
        label: const Text('Voir mon historique'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EcranParentIaHistorique(
              ficheEleveId: widget.ficheEleveId,
              nomEleve: 'moi',
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: Icon(
          c.estVerrouille
              ? Icons.lock_outline_rounded
              : Icons.pause_circle_outline,
          color: context.palette.erreur,
        ),
        label: Text(
          c.estVerrouille
              ? 'Verrouillé — ${c.joursRestantsAvantDeverrouillage} j restants'
              : 'Désactiver PARENT IA',
          style: TextStyle(color: context.palette.erreur),
        ),
        onPressed: (c.estVerrouille || _enCours) ? null : _tenterDesactiver,
      ),
    ];
  }

  List<Widget> _blocsInactif() {
    return [
      GlassCard(
        enfant: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Comment ça marche',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            SizedBox(height: 8),
            _PointExplicatif(
              icon: Icons.phone_iphone_rounded,
              texte:
                  "L'IA analyse ton temps passé sur les réseaux sociaux et les jeux.",
            ),
            _PointExplicatif(
              icon: Icons.trending_up_rounded,
              texte:
                  'Elle croise cet usage avec ton risque de décrochage scolaire.',
            ),
            _PointExplicatif(
              icon: Icons.notifications_active_outlined,
              texte:
                  "Si l'usage est jugé excessif, tu reçois une notification.",
            ),
            _PointExplicatif(
              icon: Icons.visibility_outlined,
              texte: "Ton parent peut consulter l'historique des restrictions.",
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      GlassCard(
        couleurBordure: context.palette.accent.withValues(alpha: 0.4),
        enfant: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_clock_rounded,
              color: context.palette.accent,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "Une fois activé, ce paramètre reste verrouillé 30 jours minimum, même si tu changes d'avis. Réfléchis avant de valider.",
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      GlassCard(
        // `Material` explicite : `GlassCard` peint son propre fond opaque
        // (glassmorphism), qui masquerait sinon l'encre/le splash du
        // `CheckboxListTile` (celui-ci peint sur le `Material` ancêtre le
        // plus proche).
        enfant: Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            value: _consentementCoche,
            onChanged: (v) => setState(() => _consentementCoche = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              "J'accepte que l'IA analyse mon temps d'usage des réseaux sociaux et des jeux pour m'aider à mieux gérer mon temps.",
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        icon: _enCours
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.shield_outlined),
        label: const Text('Activer PARENT IA'),
        onPressed: (_consentementCoche && !_enCours) ? _activer : null,
      ),
    ];
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.actif});

  final bool actif;

  @override
  Widget build(BuildContext context) {
    final couleur = actif ? context.palette.succes : context.palette.primaire;
    return Center(
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              actif ? Icons.shield_rounded : Icons.shield_outlined,
              color: couleur,
              size: 34,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            actif ? 'PARENT IA est actif' : 'PARENT IA est désactivé',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _PointExplicatif extends StatelessWidget {
  const _PointExplicatif({required this.icon, required this.texte});

  final IconData icon;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.palette.primaire),
          const SizedBox(width: 8),
          Expanded(child: Text(texte, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.texte,
    required this.couleur,
    required this.icone,
  });

  final String texte;
  final Color couleur;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: couleur),
          const SizedBox(width: 4),
          Text(
            texte,
            style: TextStyle(
              color: couleur,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
