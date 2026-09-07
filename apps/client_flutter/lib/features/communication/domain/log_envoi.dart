import 'enums_comm.dart';

/// Projection cliente de `public.logs_envois` (M9) — **lecture seule** côté
/// client, réservée à `est_comm` (direction/administration) : c'est le
/// serveur/le fournisseur d'envoi qui journalise, jamais l'application.
class LogEnvoi {
  const LogEnvoi({
    required this.id,
    required this.etablissementId,
    required this.notificationId,
    this.fournisseur = '',
    this.statut = StatutEnvoi.envoye,
    this.codeErreur,
    this.dateRetry,
    this.messageIdFournisseur,
  });

  factory LogEnvoi.depuisJson(Map<String, dynamic> json) => LogEnvoi(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        notificationId: json['notification_id'] as String,
        fournisseur: json['fournisseur'] as String? ?? '',
        statut: StatutEnvoi.depuisCode(json['statut'] as String?),
        codeErreur: json['code_erreur'] as String?,
        dateRetry: json['date_retry'] == null ? null : DateTime.parse(json['date_retry'] as String),
        messageIdFournisseur: json['message_id_fournisseur'] as String?,
      );

  final String id;
  final String etablissementId;
  final String notificationId;
  final String fournisseur;
  final StatutEnvoi statut;
  final String? codeErreur;
  final DateTime? dateRetry;
  final String? messageIdFournisseur;
}
