import 'enums_comm.dart';

/// Projection cliente de `public.templates_notifications` (M9) — modèle par
/// établissement, type et canal (contrainte `templates_type_canal_unique`).
/// Lecture par tout membre de l'établissement, écriture réservée à
/// `est_comm` (direction/administration), toujours en ligne.
class TemplateNotification {
  const TemplateNotification({
    required this.id,
    required this.etablissementId,
    required this.type,
    this.canal = CanalNotification.sms,
    this.contenu = '',
    this.variables = const [],
    this.actif = true,
  });

  factory TemplateNotification.depuisJson(Map<String, dynamic> json) => TemplateNotification(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        type: json['type'] as String,
        canal: CanalNotification.depuisCode(json['canal'] as String?),
        contenu: json['contenu'] as String? ?? '',
        variables: (json['variables'] as List<dynamic>?)?.cast<String>() ?? const [],
        actif: json['actif'] as bool? ?? true,
      );

  /// Colonnes réelles de `public.templates_notifications` — pour
  /// création/édition (`id` omis à la création : généré côté serveur).
  Map<String, dynamic> versJsonEcriture() => {
        'etablissement_id': etablissementId,
        'type': type,
        'canal': canal.code,
        'contenu': contenu,
        'variables': variables,
        'actif': actif,
      };

  final String id;
  final String etablissementId;
  final String type;
  final CanalNotification canal;
  final String contenu;
  final List<String> variables;
  final bool actif;
}
