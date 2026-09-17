/// Projection cliente du retour de la RPC `cgu_statut()` (cahier §34.10) —
/// version CGU courante du parcours de l'appelant (`simplifie`/`complet`,
/// dérivé de son `role_racine`) et statut d'acceptation.
class CguStatut {
  const CguStatut({
    required this.cguVersionId,
    required this.parcours,
    required this.numeroVersion,
    required this.contenu,
    required this.publieeLe,
    required this.acceptee,
  });

  factory CguStatut.depuisJson(Map<String, dynamic> json) => CguStatut(
        cguVersionId: json['cgu_version_id'] as String,
        parcours: json['parcours'] as String,
        numeroVersion: json['numero_version'] as String,
        contenu: json['contenu'] as String,
        publieeLe: DateTime.parse(json['publiee_le'] as String),
        acceptee: json['acceptee'] as bool? ?? false,
      );

  final String cguVersionId;
  final String parcours;
  final String numeroVersion;
  final String contenu;
  final DateTime publieeLe;
  final bool acceptee;
}
