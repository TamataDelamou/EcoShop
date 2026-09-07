import 'log_envoi.dart';
import 'notif.dart';
import 'preference_canal.dart';
import 'taux_lecture_canal.dart';
import 'template_notification.dart';

/// Erreur métier de Communication & Notifications, à code stable.
class ErreurComm implements Exception {
  const ErreurComm(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurComm($code)';
}

/// Port du module Communication & Notifications (M9).
///
/// Périmètre strictement aligné sur le DDL réel
/// (`20260906000900_m9_communication_notifications.sql`) : un système de
/// notifications multicanal (SMS/WhatsApp/Email/Push), pas une messagerie.
/// Aucune table `conversations`/`messages`/`annonces`/`cahier_liaison`
/// n'existe côté serveur — voir `features/communication/prototype` pour
/// l'IHM correspondante, explicitement non persistée côté serveur.
abstract interface class CommRepository {
  /// Notifications du destinataire connecté (son fil personnel).
  Future<List<Notif>> mesNotifications(String profileId);

  /// Notifications de tout l'établissement (vue direction/communication).
  Future<List<Notif>> notificationsEtablissement(String etablissementId);

  /// Marque une notification comme lue. Fonctionne hors connexion (file
  /// `sync_queue`) : seul le destinataire peut le faire (trigger serveur).
  Future<bool> marquerLue(String notificationId, {required String destinataire});

  /// Crée une notification (direction/communication uniquement, toujours en
  /// ligne — l'envoi effectif au fournisseur est un traitement serveur).
  Future<Notif> creerNotification(Notif notification);

  /// Préférences de canaux du compte connecté.
  Future<List<PreferenceCanal>> mesPreferences(String profileId);

  /// Définit une préférence de canal. Fonctionne hors connexion (file
  /// `sync_queue`) — strictement personnelle (RLS `profile_id = auth.uid()`).
  Future<bool> definirPreference(PreferenceCanal preference);

  /// Journal des envois d'un établissement (direction/communication).
  Future<List<LogEnvoi>> logsEtablissement(String etablissementId);

  /// Modèles de messages d'un établissement (lecture : tout membre).
  Future<List<TemplateNotification>> templatesEtablissement(String etablissementId);

  /// Crée ou modifie un modèle de message (direction/communication, en ligne).
  Future<void> creerOuModifierTemplate(TemplateNotification template);

  /// Taux de lecture par canal sur une période (RPC `analyser_envois`, IA
  /// descriptive).
  Future<List<TauxLectureCanal>> analyserEnvois(String etablissementId, DateTime debut, DateTime fin);

  /// Créneau d'envoi suggéré pour un destinataire (RPC `suggere_heure_envoi`,
  /// IA prédictive) — format `HH:mm`.
  Future<String> suggereHeureEnvoi(String profileId);

  /// Canal préféré d'un destinataire pour un type de message (RPC
  /// `choisir_canal`, IA prescriptive).
  Future<String> choisirCanal(String profileId, String type);

  /// Variante A/B déterministe pour un destinataire et un type (RPC
  /// `selectionner_variante`, IA prescriptive).
  Future<String> selectionnerVariante(String profileId, String type);

  /// Sentiment (positif/neutre/négatif) d'un texte de retour (RPC
  /// `analyser_feedback`, IA prescriptive — lexique léger).
  Future<String> analyserFeedback(String texte);
}
