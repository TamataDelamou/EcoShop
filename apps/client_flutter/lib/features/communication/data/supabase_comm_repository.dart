import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/comm_repository.dart';
import '../domain/log_envoi.dart';
import '../domain/notif.dart';
import '../domain/preference_canal.dart';
import '../domain/taux_lecture_canal.dart';
import '../domain/template_notification.dart';

/// Implémentation Supabase du port [CommRepository] (M9).
class SupabaseCommRepository implements CommRepository {
  const SupabaseCommRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Notif>> mesNotifications(String profileId) {
    return _executer(() async {
      final lignes = await _client
          .from('notifications')
          .select()
          .eq('destinataire', profileId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      return lignes.map((l) => Notif.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<Notif>> notificationsEtablissement(String etablissementId) {
    return _executer(() async {
      final lignes = await _client
          .from('notifications')
          .select()
          .eq('etablissement_id', etablissementId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      return lignes.map((l) => Notif.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> marquerLue(String notificationId, {required String destinataire}) {
    return _executer(() async {
      await _client
          .from('notifications')
          .update({'date_lecture': DateTime.now().toUtc().toIso8601String(), 'statut': 'lue'})
          .eq('id', notificationId)
          .eq('destinataire', destinataire);
      return true;
    });
  }

  @override
  Future<Notif> creerNotification(Notif notification) {
    return _executer(() async {
      final ligne = await _client.from('notifications').insert(notification.versJsonEcriture()).select().single();
      return Notif.depuisJson(ligne);
    });
  }

  @override
  Future<List<PreferenceCanal>> mesPreferences(String profileId) {
    return _executer(() async {
      final lignes = await _client.from('preferences_canaux').select().eq('profile_id', profileId).order('canal');
      return lignes.map((l) => PreferenceCanal.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> definirPreference(PreferenceCanal preference) {
    return _executer(() async {
      await _client
          .from('preferences_canaux')
          .upsert(preference.versJsonEcriture(), onConflict: 'profile_id,canal');
      return true;
    });
  }

  @override
  Future<List<LogEnvoi>> logsEtablissement(String etablissementId) {
    return _executer(() async {
      final lignes = await _client
          .from('logs_envois')
          .select()
          .eq('etablissement_id', etablissementId)
          .order('created_at', ascending: false);
      return lignes.map((l) => LogEnvoi.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<TemplateNotification>> templatesEtablissement(String etablissementId) {
    return _executer(() async {
      final lignes = await _client
          .from('templates_notifications')
          .select()
          .eq('etablissement_id', etablissementId)
          .order('type');
      return lignes.map((l) => TemplateNotification.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<void> creerOuModifierTemplate(TemplateNotification template) {
    return _executer(() async {
      await _client
          .from('templates_notifications')
          .upsert(template.versJsonEcriture(), onConflict: 'etablissement_id,type,canal');
    });
  }

  @override
  Future<List<TauxLectureCanal>> analyserEnvois(String etablissementId, DateTime debut, DateTime fin) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'analyser_envois',
        params: {
          'p_etablissement': etablissementId,
          'p_debut': _dateIso(debut),
          'p_fin': _dateIso(fin),
        },
      );
      return resultat.map((l) => TauxLectureCanal.depuisJson(l as Map<String, dynamic>)).toList(growable: false);
    });
  }

  @override
  Future<String> suggereHeureEnvoi(String profileId) {
    return _executer(() async {
      final resultat = await _client.rpc<String>('suggere_heure_envoi', params: {'p_profile': profileId});
      return resultat.length >= 5 ? resultat.substring(0, 5) : resultat;
    });
  }

  @override
  Future<String> choisirCanal(String profileId, String type) {
    return _executer(() async {
      return _client.rpc<String>('choisir_canal', params: {'p_profile': profileId, 'p_type': type});
    });
  }

  @override
  Future<String> selectionnerVariante(String profileId, String type) {
    return _executer(() async {
      return _client.rpc<String>('selectionner_variante', params: {'p_profile': profileId, 'p_type': type});
    });
  }

  @override
  Future<String> analyserFeedback(String texte) {
    return _executer(() async {
      return _client.rpc<String>('analyser_feedback', params: {'p_texte': texte});
    });
  }

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurComm(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
