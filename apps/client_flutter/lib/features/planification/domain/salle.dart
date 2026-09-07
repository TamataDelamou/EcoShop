/// Projection cliente de `public.salles` (M11) — ressource physique de
/// l'établissement. Pas de champs LWW (`modifie_le`/`device_id`) : la
/// gestion des salles est une action de bureau, toujours en ligne.
class Salle {
  const Salle({
    required this.id,
    required this.etablissementId,
    required this.code,
    this.nom = '',
    this.capacite,
    this.actif = true,
  });

  factory Salle.depuisJson(Map<String, dynamic> json) => Salle(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        code: json['code'] as String,
        nom: json['nom'] as String? ?? '',
        capacite: json['capacite'] as int?,
        actif: json['actif'] as bool? ?? true,
      );

  factory Salle.depuisJsonCache(Map<String, dynamic> json) => Salle.depuisJson(json);

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'code': code,
        'nom': nom,
        'capacite': capacite,
        'actif': actif,
      };

  final String id;
  final String etablissementId;
  final String code;
  final String nom;
  final int? capacite;
  final bool actif;

  String get libelle => nom.isEmpty ? code : '$code — $nom';
}
