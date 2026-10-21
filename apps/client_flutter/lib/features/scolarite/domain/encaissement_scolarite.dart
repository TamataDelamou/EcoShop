import 'enums_financier_scolaire.dart';

/// Projection cliente de `public.encaissements_scolarite` (M15quater).
///
/// Entité **dédiée** à l'encaissement de frais de scolarité — jamais une
/// écriture comptable générale (`EcritureComptable`, M14) : liée
/// explicitement à [ficheEleveId]/[inscriptionId], condition posée après le
/// retrait du reçu PDF de M15ter (voir `docs/contrats/M15ter_export_pdf.md`
/// §7). `saisiPar`, `annulePar` et `annuleLe` sont toujours imposés par le
/// serveur (triggers `encaissements_verifie_tenant`/`_immuable`), jamais par
/// une valeur transmise par le client.
class EncaissementScolarite {
  const EncaissementScolarite({
    required this.id,
    required this.etablissementId,
    required this.ficheEleveId,
    required this.inscriptionId,
    required this.montant,
    required this.datePaiement,
    required this.saisiPar,
    this.typeFrais = TypeFraisScolaire.scolarite,
    this.moyenPaiement = MoyenPaiement.especes,
    this.referencePaiement,
    this.statut = StatutEncaissement.valide,
    this.motifAnnulation,
    this.annulePar,
    this.annuleLe,
    this.createdAt,
    this.numeroRecu,
    this.numeroProvisoire,
    this.saisiLeClient,
    this.enAttenteEnvoi = false,
  });

  factory EncaissementScolarite.depuisJson(Map<String, dynamic> json) {
    return EncaissementScolarite(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      inscriptionId: json['inscription_id'] as String,
      montant: (json['montant'] as num).toDouble(),
      datePaiement: DateTime.parse(json['date_paiement'] as String),
      saisiPar: json['saisi_par'] as String,
      typeFrais: TypeFraisScolaire.depuisCode(json['type_frais'] as String?),
      moyenPaiement: MoyenPaiement.depuisCode(json['moyen_paiement'] as String?),
      referencePaiement: json['reference_paiement'] as String?,
      statut: StatutEncaissement.depuisCode(json['statut'] as String?),
      motifAnnulation: json['motif_annulation'] as String?,
      annulePar: json['annule_par'] as String?,
      annuleLe: json['annule_le'] == null ? null : DateTime.parse(json['annule_le'] as String),
      createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String),
      numeroRecu: json['numero_recu'] as String?,
      numeroProvisoire: json['numero_provisoire'] as String?,
      saisiLeClient: json['saisi_le_client'] == null ? null : DateTime.parse(json['saisi_le_client'] as String),
      enAttenteEnvoi: json['en_attente_envoi'] as bool? ?? false,
    );
  }

  /// Paramètres de `enregistrer_encaissement_scolarite` : [id] est la clé
  /// générée sur l'appareil (un renvoi ne crée jamais de doublon) ;
  /// `saisi_par` reste imposé par le serveur, jamais transmis.
  Map<String, dynamic> versParamsEnregistrement() => {
        'p_id': id,
        'p_etablissement': etablissementId,
        'p_fiche_eleve': ficheEleveId,
        'p_inscription': inscriptionId,
        'p_type_frais': typeFrais.code,
        'p_montant': montant,
        'p_moyen': moyenPaiement.code,
        'p_reference': referencePaiement,
        'p_date': _dateIso(datePaiement),
        'p_numero_provisoire': numeroProvisoire,
        'p_saisi_le': (saisiLeClient ?? DateTime.now()).toUtc().toIso8601String(),
      };

  /// Copie avec la clé de l'appareil et, hors connexion, le reçu provisoire.
  EncaissementScolarite avecCle(String cle, {String? numeroProvisoire, DateTime? saisiLe, bool? enAttenteEnvoi}) =>
      EncaissementScolarite(
        id: cle,
        etablissementId: etablissementId,
        ficheEleveId: ficheEleveId,
        inscriptionId: inscriptionId,
        montant: montant,
        datePaiement: datePaiement,
        saisiPar: saisiPar,
        typeFrais: typeFrais,
        moyenPaiement: moyenPaiement,
        referencePaiement: referencePaiement,
        statut: statut,
        motifAnnulation: motifAnnulation,
        annulePar: annulePar,
        annuleLe: annuleLe,
        createdAt: createdAt,
        numeroRecu: numeroRecu,
        numeroProvisoire: numeroProvisoire ?? this.numeroProvisoire,
        saisiLeClient: saisiLe ?? saisiLeClient,
        enAttenteEnvoi: enAttenteEnvoi ?? this.enAttenteEnvoi,
      );

  /// Colonnes envoyées à la création — `id`/`saisi_par` sont générés/imposés
  /// côté serveur, jamais transmis par le client.
  Map<String, dynamic> versJsonCreation() => {
        'etablissement_id': etablissementId,
        'fiche_eleve_id': ficheEleveId,
        'inscription_id': inscriptionId,
        'type_frais': typeFrais.code,
        'montant': montant,
        'moyen_paiement': moyenPaiement.code,
        'reference_paiement': referencePaiement,
        'date_paiement': _dateIso(datePaiement),
      };

  /// Sérialisation complète pour le cache local (repli hors ligne) — inclut
  /// les champs serveur (`saisi_par`, `statut`, annulation) contrairement à
  /// [versJsonCreation], pour un aller-retour fidèle avec [depuisJson].
  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'fiche_eleve_id': ficheEleveId,
        'inscription_id': inscriptionId,
        'type_frais': typeFrais.code,
        'montant': montant,
        'moyen_paiement': moyenPaiement.code,
        'reference_paiement': referencePaiement,
        'date_paiement': _dateIso(datePaiement),
        'saisi_par': saisiPar,
        'statut': statut.code,
        'motif_annulation': motifAnnulation,
        'annule_par': annulePar,
        'annule_le': annuleLe?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'numero_recu': numeroRecu,
        'numero_provisoire': numeroProvisoire,
        'saisi_le_client': saisiLeClient?.toIso8601String(),
        'en_attente_envoi': enAttenteEnvoi,
      };

  final String id;
  final String etablissementId;
  final String ficheEleveId;
  final String inscriptionId;
  final TypeFraisScolaire typeFrais;
  final double montant;
  final MoyenPaiement moyenPaiement;
  final String? referencePaiement;
  final DateTime datePaiement;
  final String saisiPar;
  final StatutEncaissement statut;
  final String? motifAnnulation;
  final String? annulePar;
  final DateTime? annuleLe;
  final DateTime? createdAt;

  /// Numéro de reçu continu attribué par le serveur (SCO-2026-000123).
  final String? numeroRecu;

  /// Reçu remis sans réseau (PROV-<appareil>-0001), rappelé sur le définitif.
  final String? numeroProvisoire;
  final DateTime? saisiLeClient;

  /// Saisi sur cet appareil, pas encore reçu par le serveur.
  final bool enAttenteEnvoi;

  /// Numéro à afficher et à imprimer.
  String? get numeroAffiche => numeroRecu ?? numeroProvisoire;

  bool get estValide => statut == StatutEncaissement.valide;

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
