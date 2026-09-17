/// Un élève inscrit (actif) dans une classe, avec sa mention finale
/// éventuelle (cahier §12.4 — admis(e)/recalé(e), classes d'examen
/// uniquement). Projection dédiée de `inscriptions`, pas le modèle
/// `Inscription` partagé (celui-ci passe par un cache Drift/décorateur hors
/// ligne sans rapport avec cette action, toujours en ligne).
class EleveMention {
  const EleveMention({
    required this.inscriptionId,
    required this.ficheEleveId,
    required this.nom,
    required this.prenom,
    this.mentionFinale,
  });

  factory EleveMention.depuisJson(Map<String, dynamic> json) {
    final fiche = json['fiches_eleves'] as Map<String, dynamic>?;
    return EleveMention(
      inscriptionId: json['id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      nom: fiche?['nom'] as String? ?? '',
      prenom: fiche?['prenom'] as String? ?? '',
      mentionFinale: json['mention_finale'] as String?,
    );
  }

  final String inscriptionId;
  final String ficheEleveId;
  final String nom;
  final String prenom;

  /// `'admis'`, `'recale'`, ou `null` (pas encore saisie).
  final String? mentionFinale;
}
