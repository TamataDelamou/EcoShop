import 'package:flutter/material.dart';

import '../../../accueil/domain/fonction.dart' show Teinte;
import '../../domain/moteur_emploi_du_temps.dart';

/// Une séance à afficher dans la grille de la semaine.
class CaseSemaine {
  const CaseSemaine({
    required this.jour,
    required this.debut,
    required this.fin,
    required this.titre,
    this.detail,
    this.cleCouleur,
    this.verrouillee = false,
    this.onTap,
  });

  final int jour;
  final String debut;
  final String fin;
  final String titre;
  final String? detail;

  /// Même clé, même couleur (une matière garde sa couleur partout).
  final String? cleCouleur;
  final bool verrouillee;
  final VoidCallback? onTap;
}

/// Grille de la semaine (lignes : créneaux de la journée-type ; colonnes :
/// jours), à la manière des emplois du temps imprimés. Défile à
/// l'horizontale sur un téléphone.
class GrilleSemaine extends StatelessWidget {
  const GrilleSemaine({
    super.key,
    required this.jours,
    required this.creneaux,
    required this.cases,
    this.joursLibres = const {},
  });

  final List<int> jours;
  final List<CreneauEmploi> creneaux;
  final List<CaseSemaine> cases;

  /// Jour → « matin », « apres_midi », « journee » : grisé.
  final Map<int, String> joursLibres;

  static const _noms = {1: 'Lun', 2: 'Mar', 3: 'Mer', 4: 'Jeu', 5: 'Ven', 6: 'Sam', 7: 'Dim'};

  /// Teintes des pastilles de l'accueil (contraste vérifié dans les deux
  /// modes) : une matière garde la même partout.
  static Teinte teintePour(String? cle) {
    if (cle == null) return Teinte.bleu;
    var h = 0;
    for (final c in cle.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return Teinte.values[h % Teinte.values.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schema = theme.colorScheme;
    final sombre = theme.brightness == Brightness.dark;
    const largeurHeure = 56.0;
    const largeurJour = 112.0;

    Widget cellule(int jour, CreneauEmploi c) {
      if (!c.cours) {
        return Container(
          height: 26,
          alignment: Alignment.center,
          color: schema.surfaceContainerHighest.withValues(alpha: 0.6),
          child: Text(c.libelle ?? 'Pause', style: theme.textTheme.labelSmall, overflow: TextOverflow.ellipsis),
        );
      }
      final libre = joursLibres[jour];
      final matin = c.debutMinutes < 12 * 60 + 30;
      final bloque = libre == 'journee' || (libre == 'matin' && matin) || (libre == 'apres_midi' && !matin);
      final ici = cases.where((s) => s.jour == jour && minutesDe(s.debut) < c.finMinutes && minutesDe(s.fin) > c.debutMinutes).toList();
      if (ici.isEmpty) {
        return Container(
          height: 64,
          decoration: BoxDecoration(
            color: bloque ? schema.surfaceContainerHighest : null,
            border: Border.all(color: schema.outlineVariant.withValues(alpha: 0.5), width: 0.5),
          ),
        );
      }
      return SizedBox(
        height: 64,
        child: Row(
          children: [
            for (final s in ici)
              Expanded(
                child: Material(
                  color: sombre ? teintePour(s.cleCouleur).fondSombre : teintePour(s.cleCouleur).fondClair,
                  child: InkWell(
                    onTap: s.onTap,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: sombre ? teintePour(s.cleCouleur).iconeSombre : teintePour(s.cleCouleur).iconeClair,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s.titre,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.1),
                                ),
                              ),
                              if (s.verrouillee) const Icon(Icons.lock, size: 11),
                            ],
                          ),
                          if (s.detail != null)
                            Text(
                              s.detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: schema.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: largeurHeure + largeurJour * jours.length,
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: largeurHeure),
                for (final j in jours)
                  SizedBox(
                    width: largeurJour,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_noms[j] ?? '$j', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
            for (final c in creneaux)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: largeurHeure,
                    height: c.cours ? 64 : 26,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4, top: 2),
                      child: Text(
                        c.cours ? '${c.debut}\n${c.fin}' : c.debut,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelSmall?.copyWith(color: schema.onSurfaceVariant),
                      ),
                    ),
                  ),
                  for (final j in jours) SizedBox(width: largeurJour, child: cellule(j, c)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
