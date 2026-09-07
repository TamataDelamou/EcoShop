/// Ligne du tableau de bord communication (RPC `analyser_envois`, niveau IA
/// descriptif) — taux de lecture d'un canal sur une période.
class TauxLectureCanal {
  const TauxLectureCanal({
    required this.canal,
    required this.nbEnvoyes,
    required this.nbLus,
    required this.tauxLecture,
  });

  factory TauxLectureCanal.depuisJson(Map<String, dynamic> json) => TauxLectureCanal(
        canal: json['canal'] as String,
        nbEnvoyes: (json['nb_envoyes'] as num).toInt(),
        nbLus: (json['nb_lus'] as num).toInt(),
        tauxLecture: (json['taux_lecture'] as num?)?.toDouble() ?? 0,
      );

  final String canal;
  final int nbEnvoyes;
  final int nbLus;
  final double tauxLecture;
}
