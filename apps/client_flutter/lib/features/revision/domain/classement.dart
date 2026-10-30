/// Classement de la semaine (REG-37, cahier 22.3, 23.1) : points d'effort,
/// remis à zéro chaque lundi ; vue relative (les 5 premiers, puis l'élève
/// et ses voisins).
class LigneClassement {
  const LigneClassement({required this.rang, required this.nom, required this.points, this.quiz = 0, this.moi = false});

  final int rang;
  final String nom;
  final int points;
  final int quiz;
  final bool moi;
}

class ClassementRevision {
  const ClassementRevision({
    this.actif = false,
    this.raison,
    this.lignes = const [],
    this.monRang,
    this.participants = 0,
    this.visible = true,
    this.mesPoints = 0,
  });

  final bool actif;

  /// SANS_CLASSE, PETITES_CLASSES.
  final String? raison;
  final List<LigneClassement> lignes;
  final int? monRang;
  final int participants;
  final bool visible;
  final int mesPoints;

  factory ClassementRevision.depuisJson(Map<String, dynamic> j) => ClassementRevision(
        actif: j['actif'] == true,
        raison: j['raison'] as String?,
        lignes: [
          for (final l in (j['lignes'] as List?) ?? const [])
            LigneClassement(
              rang: ((l as Map)['rang'] as num?)?.toInt() ?? 0,
              nom: '${l['nom'] ?? ''}',
              points: (l['points'] as num?)?.toInt() ?? 0,
              quiz: (l['quiz'] as num?)?.toInt() ?? 0,
              moi: l['moi'] == true,
            ),
        ],
        monRang: (j['mon_rang'] as num?)?.toInt(),
        participants: (j['participants'] as num?)?.toInt() ?? 0,
        visible: j['visible'] != false,
        mesPoints: (j['mes_points'] as num?)?.toInt() ?? 0,
      );

  /// Un mot d'encouragement selon la place (jamais de honte pour les
  /// derniers : on montre l'écart à combler, pas le rang seul).
  String encouragement() {
    if (!visible) return 'Tu n’apparais pas dans le classement ; tes points comptent quand même pour toi.';
    final r = monRang;
    if (r == null) return 'Fais un quiz cette semaine pour entrer dans le classement.';
    if (r == 1) return 'Tu es en tête cette semaine. Bravo pour ta régularité !';
    final devant = lignes.where((l) => l.rang == r - 1).firstOrNull ??
        lignes.where((l) => l.rang < r).lastOrNull;
    if (devant == null) return 'Continue : chaque quiz terminé rapporte 50 points.';
    final ecart = devant.points - mesPoints;
    return ecart <= 0
        ? 'Tu es au coude à coude avec ${devant.nom} !'
        : 'Encore $ecart points pour rattraper ${devant.nom} : un quiz terminé en rapporte 50.';
  }
}

/// Barème des points d'effort (cahier 22.1), affiché à l'élève.
const baremeEffort = '+10 par bonne réponse, +50 par quiz terminé, +100 par examen blanc terminé.';
