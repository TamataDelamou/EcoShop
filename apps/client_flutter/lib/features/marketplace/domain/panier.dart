/// Projection cliente de `public.paniers` (M13) — panier MONO-VENDEUR : un
/// seul [commercantId] par panier (garde-fou trigger côté serveur).
///
/// Propriétaire = [profileId] (compte authentifié) : le module ne couvre pas
/// le parcours 100% anonyme du DDL `paniers.visiteur_id`/M15 — le cadre
/// retenu authentifie tout acheteur (OTP, même mécanisme que le reste de
/// l'app), y compris sans rattachement établissement (rôle Parent
/// auto-inscrit). `etablissementId` reste NOT NULL côté serveur ; tant qu'il
/// n'est pas connu, le panier reste un [PanierBrouillonLocal] purement local.
class Panier {
  const Panier({
    required this.id,
    required this.etablissementId,
    required this.profileId,
    this.commercantId,
    this.statut = 'actif',
    this.saisiHorsLigne = false,
    this.deviceId,
    this.clientTs,
  });

  factory Panier.depuisJson(Map<String, dynamic> json) => Panier(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        profileId: json['profile_id'] as String,
        commercantId: json['commercant_id'] as String?,
        statut: json['statut'] as String? ?? 'actif',
        saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
        deviceId: json['device_id'] as String?,
        clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
      );

  factory Panier.depuisJsonCache(Map<String, dynamic> json) => Panier.depuisJson(json);

  Map<String, dynamic> versJsonCache() => versJsonEcriture();

  /// Colonnes réelles de `public.paniers` — pour l'upsert (pas de contrainte
  /// unique métier hors PK : l'upsert cible `id`, généré côté client).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'profile_id': profileId,
        'commercant_id': commercantId,
        'statut': statut,
        'saisi_hors_ligne': saisiHorsLigne,
        'device_id': deviceId,
        'client_ts': (clientTs ?? DateTime.now()).toIso8601String(),
      };

  factory Panier.depuisJsonEcriture(Map<String, dynamic> json) => Panier(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        profileId: json['profile_id'] as String,
        commercantId: json['commercant_id'] as String?,
        statut: json['statut'] as String? ?? 'actif',
        saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
        deviceId: json['device_id'] as String?,
        clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
      );

  Panier copierAvec({String? commercantId, String? statut}) => Panier(
        id: id,
        etablissementId: etablissementId,
        profileId: profileId,
        commercantId: commercantId ?? this.commercantId,
        statut: statut ?? this.statut,
        saisiHorsLigne: saisiHorsLigne,
        deviceId: deviceId,
        clientTs: clientTs,
      );

  final String id;
  final String etablissementId;
  final String profileId;
  final String? commercantId;
  final String statut;
  final bool saisiHorsLigne;
  final String? deviceId;
  final DateTime? clientTs;
}
