/// Projection d'une ligne renvoyée par la RPC serveur
/// `classer_eleves_classe` (D5) — moyenne et rang d'un élève dans sa classe,
/// jamais recalculés côté client (contrat M06 §5, étendu au classement).
class ClassementEleve {
  const ClassementEleve({
    required this.ficheEleveId,
    required this.moyenne,
    required this.rang,
  });

  factory ClassementEleve.depuisJson(Map<String, dynamic> json) {
    return ClassementEleve(
      ficheEleveId: json['fiche_eleve_id'] as String,
      moyenne: (json['moyenne'] as num).toDouble(),
      rang: json['rang'] as int,
    );
  }

  final String ficheEleveId;
  final double moyenne;
  final int rang;
}
