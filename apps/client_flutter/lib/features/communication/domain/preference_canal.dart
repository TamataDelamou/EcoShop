import 'enums_comm.dart';

/// Projection cliente de `public.preferences_canaux` (M9) — strictement
/// personnelles (RLS : `profile_id = auth.uid()`). Écriture tolérante
/// hors-ligne (file `sync_queue`) : un changement de préférence en zone mal
/// couverte ne doit pas attendre le retour du réseau.
class PreferenceCanal {
  const PreferenceCanal({
    required this.id,
    required this.profileId,
    required this.canal,
    this.actif = true,
    this.horaireDebut = '08:00',
    this.horaireFin = '19:00',
    this.frequence = FrequenceNotification.immediat,
  });

  factory PreferenceCanal.depuisJson(Map<String, dynamic> json) => PreferenceCanal(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        canal: CanalNotification.depuisCode(json['canal'] as String?),
        actif: json['actif'] as bool? ?? true,
        horaireDebut: _tronquerHeure(json['horaire_debut'] as String? ?? '08:00'),
        horaireFin: _tronquerHeure(json['horaire_fin'] as String? ?? '19:00'),
        frequence: FrequenceNotification.depuisCode(json['frequence'] as String?),
      );

  factory PreferenceCanal.depuisJsonCache(Map<String, dynamic> json) => PreferenceCanal.depuisJson(json);

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'profile_id': profileId,
        'canal': canal.code,
        'actif': actif,
        'horaire_debut': horaireDebut,
        'horaire_fin': horaireFin,
        'frequence': frequence.code,
      };

  /// Colonnes réelles de `public.preferences_canaux` — pour l'upsert
  /// (contrainte `prefs_canal_unique (profile_id, canal)`).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'profile_id': profileId,
        'canal': canal.code,
        'actif': actif,
        'horaire_debut': horaireDebut,
        'horaire_fin': horaireFin,
        'frequence': frequence.code,
      };

  factory PreferenceCanal.depuisJsonEcriture(Map<String, dynamic> json) => PreferenceCanal.depuisJson(json);

  final String id;
  final String profileId;
  final CanalNotification canal;
  final bool actif;

  /// Format `HH:mm` — la colonne SQL est `time`, Postgres/PostgREST le
  /// sérialise en `HH:mm:ss`, tronqué à l'affichage.
  final String horaireDebut;
  final String horaireFin;
  final FrequenceNotification frequence;

  static String _tronquerHeure(String heure) => heure.length >= 5 ? heure.substring(0, 5) : heure;
}
