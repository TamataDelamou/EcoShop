import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'ecran_agenda_evenements.dart';
import 'ecran_emploi_du_temps.dart';
import 'ecran_progression_pedagogique.dart';

/// Menu d'entrée vers la planification d'une classe (M11) — emploi du
/// temps, agenda et, pour le personnel, progression pédagogique.
class EcranPlanificationClasse extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_view_week_outlined, color: AppColors.bleuElectrique),
              title: const Text('Emploi du temps'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EcranEmploiClasse(classeId: classeId, titre: titre)),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_outlined, color: AppColors.orangePop),
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
                leading: const Icon(Icons.trending_up_outlined, color: AppColors.vertMenthe),
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
