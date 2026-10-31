import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../auth/application/auth_providers.dart';
import '../../export_pdf/data/emploi_du_temps_pdf_builder.dart';
import '../../export_pdf/presentation/ecran_apercu_pdf.dart';
import '../../remplacements/presentation/ecran_mes_remplacements.dart';
import '../../themes/application/theme_providers.dart';
import '../application/planification_providers.dart';

import 'ecran_agenda_evenements.dart';
import 'ecran_emploi_du_temps.dart';
import 'ecran_progression_pedagogique.dart';

/// Menu d'entrée vers la planification d'une classe (M11) — emploi du
/// temps, agenda et, pour le personnel, progression pédagogique.
class EcranPlanificationClasse extends ConsumerWidget {
  const EcranPlanificationClasse({
    super.key,
    required this.classeId,
    required this.anneeId,
    required this.titre,
    this.etablissementId,
    this.peutVoirProgression = false,
  });

  final String classeId;
  final String anneeId;
  final String titre;
  final String? etablissementId;
  final bool peutVoirProgression;

  /// Emploi du temps de la classe en PDF, à l'identité de l'école (REG-41).
  Future<void> _imprimer(BuildContext context, WidgetRef ref) async {
    final etablissement = ref.read(etablissementActifProvider);
    if (etablissement == null) return;
    try {
      final seances = await ref.read(emploisDeClasseProvider(classeId).future);
      final octets = await construireEmploiDuTempsPdf(
        seances: seances,
        etablissement: etablissement,
        titre: 'Emploi du temps - $titre',
        variante: ref.read(themeVariantProvider),
        identite: await ref.read(identitePdfProvider.future),
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EcranApercuPdf(titre: 'Emploi du temps', octets: octets, nomFichier: 'emploi-du-temps.pdf'),
      ));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Emploi du temps indisponible pour le moment.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.calendar_view_week_outlined, color: context.palette.primaire),
              title: const Text('Emploi du temps'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EcranEmploiClasse(classeId: classeId, titre: titre)),
              ),
            ),
          ),
          // Cours remplacés, en étude, déplacés ou annulés (REG-41).
          Card(
            child: ListTile(
              key: const Key('changements_classe'),
              leading: Icon(Icons.swap_horiz, color: context.palette.primaire),
              title: const Text('Changements d’emploi du temps'),
              subtitle: const Text('Cours remplacés, déplacés ou annulés'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EcranChangementsClasse(classeId: classeId)),
              ),
            ),
          ),
          Card(
            child: ListTile(
              key: const Key('imprimer_emploi'),
              leading: Icon(Icons.picture_as_pdf_outlined, color: context.palette.primaire),
              title: const Text('Emploi du temps en PDF'),
              subtitle: const Text('À imprimer ou à partager'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _imprimer(context, ref),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.event_outlined, color: context.palette.accent),
              title: const Text('Agenda'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EcranAgendaEvenements(anneeId: anneeId, classeId: classeId),
                ),
              ),
            ),
          ),
          if (peutVoirProgression && etablissementId != null)
            Card(
              child: ListTile(
                leading: Icon(Icons.trending_up_outlined, color: context.palette.succes),
                title: const Text('Progression pédagogique'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EcranProgressionPedagogique(
                      etablissementId: etablissementId!,
                      classeId: classeId,
                      anneeId: anneeId,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
