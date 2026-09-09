import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../../export_pdf/data/bulletin_pdf_builder.dart';
import '../../export_pdf/presentation/ecran_apercu_pdf.dart';
import '../../scolarite/domain/fiche_eleve.dart';
import '../../themes/application/theme_providers.dart';
import '../application/notes_providers.dart';
import '../domain/bulletin.dart';

/// Liste des bulletins publiés d'un élève (M6) — snapshots signés, intégrité
/// vérifiable côté back-office (contrat M06 §2).
class EcranBulletins extends ConsumerWidget {
  const EcranBulletins({super.key, required this.fiche});

  final FicheEleve fiche;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bulletins = ref.watch(bulletinsDeFicheProvider(fiche.id));

    return Scaffold(
      appBar: AppBar(title: Text('Bulletins — ${fiche.prenom}')),
      body: bulletins.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Bulletins indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucun bulletin publié pour le moment.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) =>
                    EntreeAnimee(index: i, enfant: _CarteBulletin(bulletin: liste[i], fiche: fiche)),
              ),
      ),
    );
  }
}

class _CarteBulletin extends ConsumerStatefulWidget {
  const _CarteBulletin({required this.bulletin, required this.fiche});

  final Bulletin bulletin;
  final FicheEleve fiche;

  @override
  ConsumerState<_CarteBulletin> createState() => _CarteBulletinState();
}

class _CarteBulletinState extends ConsumerState<_CarteBulletin> {
  bool _exportEnCours = false;

  Future<void> _exporterPdf() async {
    final etablissement = ref.read(etablissementActifProvider);
    if (etablissement == null) return;
    final variante = ref.read(themeVariantProvider);

    setState(() => _exportEnCours = true);
    try {
      final octets = await construireBulletinPdf(
        bulletin: widget.bulletin,
        fiche: widget.fiche,
        etablissement: etablissement,
        variante: variante,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EcranApercuPdf(
            titre: widget.bulletin.type.libelle,
            octets: octets,
            nomFichier: 'bulletin_${widget.fiche.matricule}.pdf',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bulletin = widget.bulletin;
    final libelleType = bulletin.type.libelle;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(Icons.receipt_long_outlined, color: context.palette.primaire),
        title: Text(libelleType),
        subtitle: bulletin.publieLe != null ? Text('Publié le ${_formatDate(bulletin.publieLe!)}') : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bulletin.contenu.isEmpty)
                  const Text('Contenu détaillé indisponible pour le moment.')
                else
                  for (final entree in bulletin.contenu.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('${entree.key} : ${entree.value}'),
                    ),
                if (bulletin.signatureSha256 != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.verified_outlined, size: 16, color: context.palette.succes),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Intégrité vérifiable — empreinte ${bulletin.signatureSha256!.substring(0, 12)}…',
                          style: TextStyle(fontSize: 12, color: context.palette.encreSecondaire),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _exportEnCours ? null : _exporterPdf,
                    icon: _exportEnCours
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Exporter en PDF'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
