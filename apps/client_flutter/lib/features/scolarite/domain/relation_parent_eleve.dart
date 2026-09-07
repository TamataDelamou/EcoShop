import 'enums_scolarite.dart';
import 'fiche_eleve.dart';

/// Projection cliente de `public.relations_parent_eleve` (M5).
///
/// Support du sélecteur d'enfant : [fiche] est peuplée via l'embed
/// `relations_parent_eleve(*, fiches_eleves(*))` utilisé par
/// `mesEnfants()`.
class RelationParentEleve {
  const RelationParentEleve({
    required this.id,
    required this.etablissementId,
    required this.parentProfileId,
    required this.ficheEleveId,
    this.typeRelation = TypeRelationParentale.parent,
    this.statut = StatutRelation.confirmee,
    this.autorise = true,
    this.fiche,
  });

  factory RelationParentEleve.depuisJson(Map<String, dynamic> json) {
    final ficheJson = json['fiches_eleves'] as Map<String, dynamic>?;
    return RelationParentEleve(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      parentProfileId: json['parent_profile_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      typeRelation: TypeRelationParentale.depuisCode(json['type_relation'] as String?),
      statut: StatutRelation.depuisCode(json['statut'] as String?),
      autorise: json['autorise'] as bool? ?? true,
      fiche: ficheJson == null ? null : FicheEleve.depuisJson(ficheJson),
    );
  }

  /// Sérialisation plate pour le cache local.
  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'parent_profile_id': parentProfileId,
        'fiche_eleve_id': ficheEleveId,
        'type_relation': typeRelation.code,
        'statut': statut.code,
        'autorise': autorise,
        'fiches_eleves': fiche?.versJson(),
      };

  final String id;
  final String etablissementId;
  final String parentProfileId;
  final String ficheEleveId;
  final TypeRelationParentale typeRelation;
  final StatutRelation statut;
  final bool autorise;
  final FicheEleve? fiche;

  bool get estActive => statut == StatutRelation.confirmee && autorise;
}
