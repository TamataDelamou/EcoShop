import 'enums_comm.dart';

/// Projection cliente de `public.notifications` (M9).
///
/// Nommée `Notif` plutôt que `Notification` pour éviter toute collision avec
/// `Notification`/`NotificationListener` de `package:flutter/widgets.dart`.
///
/// Seul le destinataire (ou le serveur) peut marquer une notification « lue »
/// — trigger `notifications_verifie_ecriture` — le client ne modifie jamais
/// `contenu`/`canal`/`type` après création.
class Notif {
  const Notif({
    required this.id,
    required this.etablissementId,
    required this.destinataire,
    required this.type,
    this.canal = CanalNotification.sms,
    this.contenu = '',
    this.variante,
    this.variables = const {},
    this.statut = StatutNotification.enAttente,
    this.dateEnvoiPlanifie,
    this.dateEnvoi,
    this.dateLecture,
  });

  factory Notif.depuisJson(Map<String, dynamic> json) => Notif(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        destinataire: json['destinataire'] as String,
        type: json['type'] as String,
        canal: CanalNotification.depuisCode(json['canal'] as String?),
        contenu: json['contenu'] as String? ?? '',
        variante: json['variante'] as String?,
        variables: (json['variables'] as Map<String, dynamic>?) ?? const {},
        statut: StatutNotification.depuisCode(json['statut'] as String?),
        dateEnvoiPlanifie: json['date_envoi_planifie'] == null
            ? null
            : DateTime.parse(json['date_envoi_planifie'] as String),
        dateEnvoi: json['date_envoi'] == null ? null : DateTime.parse(json['date_envoi'] as String),
        dateLecture: json['date_lecture'] == null ? null : DateTime.parse(json['date_lecture'] as String),
      );

  factory Notif.depuisJsonCache(Map<String, dynamic> json) => Notif.depuisJson(json);

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'destinataire': destinataire,
        'type': type,
        'canal': canal.code,
        'contenu': contenu,
        'variante': variante,
        'variables': variables,
        'statut': statut.code,
        'date_envoi_planifie': dateEnvoiPlanifie?.toIso8601String(),
        'date_envoi': dateEnvoi?.toIso8601String(),
        'date_lecture': dateLecture?.toIso8601String(),
      };

  /// Colonnes réelles de `public.notifications` — pour la création (direction
  /// uniquement, toujours en ligne).
  Map<String, dynamic> versJsonEcriture() => {
        'etablissement_id': etablissementId,
        'destinataire': destinataire,
        'type': type,
        'canal': canal.code,
        'contenu': contenu,
        'variante': variante,
        'variables': variables,
      };

  final String id;
  final String etablissementId;
  final String destinataire;
  final String type;
  final CanalNotification canal;
  final String contenu;
  final String? variante;
  final Map<String, dynamic> variables;
  final StatutNotification statut;
  final DateTime? dateEnvoiPlanifie;
  final DateTime? dateEnvoi;
  final DateTime? dateLecture;

  bool get estLue => dateLecture != null;
}
