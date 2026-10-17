import 'enums_comptabilite.dart';

/// Projection cliente de `public.plans_comptables` (M14) — un nœud du plan
/// comptable. En référentiel simplifié l'arbre est OUVERT ; en référentiel
/// OHADA (REG-03 C1) les comptes [reglementaire]s sont chargés par le
/// serveur et verrouillés, l'école n'ajoute que des sous-comptes.
class PlanComptable {
  const PlanComptable({
    required this.id,
    required this.etablissementId,
    required this.code,
    required this.intitule,
    this.type = TypeCompte.autre,
    this.parentId,
    this.actif = true,
    this.reglementaire = false,
    this.extensionEcoshop = false,
  });

  factory PlanComptable.depuisJson(Map<String, dynamic> json) => PlanComptable(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        code: json['code'] as String,
        intitule: json['intitule'] as String,
        type: TypeCompte.depuisCode(json['type'] as String?),
        parentId: json['parent_id'] as String?,
        actif: json['actif'] as bool? ?? true,
        reglementaire: json['reglementaire'] as bool? ?? false,
        extensionEcoshop: json['extension_ecoshop'] as bool? ?? false,
      );

  factory PlanComptable.depuisJsonCache(Map<String, dynamic> json) => PlanComptable.depuisJson(json);

  Map<String, dynamic> versJsonCache() => {
        ...versJsonEcriture(),
        'reglementaire': reglementaire,
        'extension_ecoshop': extensionEcoshop,
      };

  /// Colonnes réelles de `public.plans_comptables` — pour l'upsert (contrainte
  /// unique `(etablissement_id, code)`).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'code': code,
        'intitule': intitule,
        'type': type.code,
        'parent_id': parentId,
        'actif': actif,
      };

  final String id;
  final String etablissementId;
  final String code;
  final String intitule;
  final TypeCompte type;
  final String? parentId;
  final bool actif;

  /// Compte du plan OHADA : ni modifiable ni supprimable (verrou serveur).
  final bool reglementaire;

  /// Sous-compte ajouté par EcoShop au plan officiel (scolarité, Orange Money…).
  final bool extensionEcoshop;

  String get libelle => '$code — $intitule';
}
