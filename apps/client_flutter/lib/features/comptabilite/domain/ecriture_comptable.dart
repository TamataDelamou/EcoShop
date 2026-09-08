/// Projection cliente de `public.ecritures_comptables` (M14) — une écriture
/// = un débit + un crédit de même montant (partie double, garde-fou trigger
/// serveur `ecritures_verifie_tenant` : comptes/journal du même
/// établissement, débit ≠ crédit, montant > 0).
///
/// Porte le facteur Last-Write-Wins d'une saisie hors-ligne
/// (`deviceId`/`clientTs`), même principe que `presences` (M7) et `paniers`
/// (M13) : dernière écriture gagne, pas de fusion de champs.
///
/// Les libellés de compte/journal ne sont **pas** embarqués via PostgREST
/// (deux FK vers `plans_comptables` sur la même ligne rendraient l'embed
/// ambigu) : l'affichage résout `compteDebitId`/`compteCreditId`/`journalId`
/// via les listes déjà chargées côté client (voir `comptabilite_providers.dart`).
class EcritureComptable {
  const EcritureComptable({
    required this.id,
    required this.etablissementId,
    required this.journalId,
    required this.dateEcriture,
    required this.libelle,
    required this.compteDebitId,
    required this.compteCreditId,
    required this.montant,
    this.pieceJustificative,
    this.numeroLot,
    this.userId,
    this.saisiHorsLigne = false,
    this.deviceId,
    this.clientTs,
  });

  factory EcritureComptable.depuisJson(Map<String, dynamic> json) => EcritureComptable(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        journalId: json['journal_id'] as String,
        dateEcriture: DateTime.parse(json['date_ecriture'] as String),
        libelle: json['libelle'] as String,
        compteDebitId: json['compte_debit_id'] as String,
        compteCreditId: json['compte_credit_id'] as String,
        montant: (json['montant'] as num).toDouble(),
        pieceJustificative: json['piece_justificative'] as String?,
        numeroLot: json['numero_lot'] as String?,
        userId: json['user_id'] as String?,
        saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
        deviceId: json['device_id'] as String?,
        clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
      );

  factory EcritureComptable.depuisJsonCache(Map<String, dynamic> json) => EcritureComptable.depuisJson(json);

  Map<String, dynamic> versJsonCache() => versJsonEcriture();

  /// Colonnes réelles de `public.ecritures_comptables` — pour l'upsert (pas
  /// de contrainte unique métier hors PK : l'upsert cible `id`, généré côté
  /// client, comme `evenements_agenda` en M11).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'journal_id': journalId,
        'date_ecriture': _dateIso(dateEcriture),
        'libelle': libelle,
        'compte_debit_id': compteDebitId,
        'compte_credit_id': compteCreditId,
        'montant': montant,
        'piece_justificative': pieceJustificative,
        'numero_lot': numeroLot,
        'user_id': userId,
        'saisi_hors_ligne': saisiHorsLigne,
        'device_id': deviceId,
        'client_ts': (clientTs ?? DateTime.now()).toIso8601String(),
      };

  factory EcritureComptable.depuisJsonEcriture(Map<String, dynamic> json) => EcritureComptable(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        journalId: json['journal_id'] as String,
        dateEcriture: DateTime.parse(json['date_ecriture'] as String),
        libelle: json['libelle'] as String,
        compteDebitId: json['compte_debit_id'] as String,
        compteCreditId: json['compte_credit_id'] as String,
        montant: (json['montant'] as num).toDouble(),
        pieceJustificative: json['piece_justificative'] as String?,
        numeroLot: json['numero_lot'] as String?,
        userId: json['user_id'] as String?,
        saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
        deviceId: json['device_id'] as String?,
        clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
      );

  final String id;
  final String etablissementId;
  final String journalId;
  final DateTime dateEcriture;
  final String libelle;
  final String compteDebitId;
  final String compteCreditId;
  final double montant;
  final String? pieceJustificative;
  final String? numeroLot;
  final String? userId;
  final bool saisiHorsLigne;
  final String? deviceId;
  final DateTime? clientTs;

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
