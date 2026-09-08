import 'enums_comptabilite.dart';

/// Projection cliente de `public.journaux` (M14) — livre chronologique
/// (opérations, banque, caisse, achats, ventes selon la convention `type`).
class Journal {
  const Journal({
    required this.id,
    required this.etablissementId,
    required this.code,
    required this.intitule,
    this.type = TypeJournal.operations,
  });

  factory Journal.depuisJson(Map<String, dynamic> json) => Journal(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        code: json['code'] as String,
        intitule: json['intitule'] as String,
        type: TypeJournal.depuisCode(json['type'] as String?),
      );

  factory Journal.depuisJsonCache(Map<String, dynamic> json) => Journal.depuisJson(json);

  Map<String, dynamic> versJsonCache() => versJsonEcriture();

  /// Colonnes réelles de `public.journaux` — pour l'upsert (contrainte unique
  /// `(etablissement_id, code)`).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'code': code,
        'intitule': intitule,
        'type': type.code,
      };

  final String id;
  final String etablissementId;
  final String code;
  final String intitule;
  final TypeJournal type;

  String get libelle => '$code — $intitule';
}
