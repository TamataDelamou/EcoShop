import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../auth/application/auth_providers.dart';
import '../../export_pdf/data/bulletin_pdf_builder.dart';
import '../../export_pdf/presentation/ecran_apercu_pdf.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../../scolarite/domain/enums_scolarite.dart';
import '../../scolarite/domain/periode_scolaire.dart';
import '../../themes/application/theme_providers.dart';
import '../application/notes_providers.dart';
import '../domain/bulletin.dart';
import '../domain/enums_notes.dart';

/// Génération groupée des bulletins d'une classe (D5, cahier §12.4) —
/// composition (moyenne + rang, RPC serveur `classer_eleves_classe`) puis
/// publication immédiate, un bulletin par élève inscrit. Réservé à la
/// direction (même garde que le reste des actions d'administration
/// scolaire, ex. `EcranSanctions`) — la véritable autorité reste la
/// permission serveur `scolarite.bulletin.gerer` (RLS, défense en
/// profondeur).
class EcranGenerationBulletinsClasse extends ConsumerStatefulWidget {
  const EcranGenerationBulletinsClasse({super.key, required this.classe});

  final Classe classe;

  @override
  ConsumerState<EcranGenerationBulletinsClasse> createState() => _EcranGenerationBulletinsClasseState();
}

class _EcranGenerationBulletinsClasseState extends ConsumerState<EcranGenerationBulletinsClasse> {
  String? _periodeId;
  bool _enCours = false;
  bool _exportEnCours = false;
  String? _erreur;
  List<Bulletin>? _bulletinsGeneres;

  TypeBulletin _typeBulletinPour(PeriodeScolaire? periode) {
    if (periode == null) return TypeBulletin.annuel;
    return switch (periode.type) {
      TypePeriode.trimestre => TypeBulletin.trimestriel,
      TypePeriode.semestre => TypeBulletin.semestriel,
      TypePeriode.terme => TypeBulletin.trimestriel,
    };
  }

  Future<void> _generer(PeriodeScolaire? periode) async {
    setState(() {
      _enCours = true;
      _erreur = null;
      _bulletinsGeneres = null;
    });
    try {
      final bulletins = await ref.read(notesRepositoryProvider).genererBulletinsClasse(
            classeId: widget.classe.id,
            anneeScolaireId: widget.classe.anneeScolaireId,
            periodeId: periode?.id,
            type: _typeBulletinPour(periode),
          );
      if (!mounted) return;
      setState(() => _bulletinsGeneres = bulletins);
      ref.invalidate(bulletinsDeFicheProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _erreur = 'Impossible de générer les bulletins de la classe — réessayez.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _exporterPdf() async {
    final bulletins = _bulletinsGeneres;
    if (bulletins == null || bulletins.isEmpty) return;
    final etablissement = ref.read(etablissementActifProvider);
    if (etablissement == null) return;
    final variante = ref.read(themeVariantProvider);

    setState(() => _exportEnCours = true);
    try {
      final inscriptions = await ref.read(scolariteRepositoryProvider).inscriptionsDeClasse(widget.classe.id);
      final fichesParId = {
        for (final i in inscriptions)
          if (i.fiche != null) i.ficheEleveId: i.fiche!,
      };

      final paires = [
        for (final b in bulletins)
          if (fichesParId[b.ficheEleveId] != null) (bulletin: b, fiche: fichesParId[b.ficheEleveId]!),
      ]..sort((a, b) => a.fiche.nom.compareTo(b.fiche.nom));

      final octets = await construireBulletinsClassePdf(
        paires: paires,
        etablissement: etablissement,
        variante: variante,
        titreClasse: 'Bulletins - ${widget.classe.nom}',
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EcranApercuPdf(
            titre: 'Bulletins - ${widget.classe.nom}',
            octets: octets,
            nomFichier: 'bulletins_${widget.classe.code}.pdf',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final structure = ref.watch(structureEtablissementProvider(widget.classe.anneeScolaireId));

    return Scaffold(
      appBar: AppBar(title: Text('Bulletins - ${widget.classe.nom}')),
      body: structure.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Périodes indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (s) {
          final periodes = s?.periodesTriees ?? const [];
          final periodeSelectionnee =
              periodes.where((p) => p.id == _periodeId).cast<PeriodeScolaire?>().firstOrNull;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Composition et classement (moyenne + rang) calculés côté serveur, '
                  'jamais côté application - un bulletin par élève inscrit.',
                  style: TextStyle(color: context.palette.encreSecondaire, fontSize: 13),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: _periodeId,
                  decoration: const InputDecoration(labelText: 'Période', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Bulletin annuel (aucune période)')),
                    for (final p in periodes) DropdownMenuItem<String?>(value: p.id, child: Text(p.libelle)),
                  ],
                  onChanged: _enCours ? null : (v) => setState(() => _periodeId = v),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _enCours ? null : () => _generer(periodeSelectionnee),
                  icon: _enCours
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.fact_check_outlined),
                  label: const Text('Générer les bulletins de la classe'),
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 12),
                  Text(_erreur!, style: TextStyle(color: context.palette.erreur)),
                ],
                if (_bulletinsGeneres != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _bulletinsGeneres!.isEmpty
                        ? 'Aucun élève avec une moyenne calculable sur cette période.'
                        : '${_bulletinsGeneres!.length} bulletin(s) généré(s) et publié(s).',
                    style: TextStyle(color: context.palette.succes, fontWeight: FontWeight.w600),
                  ),
                  if (_bulletinsGeneres!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _exportEnCours ? null : _exporterPdf,
                      icon: _exportEnCours
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Exporter en PDF (classe entière)'),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
