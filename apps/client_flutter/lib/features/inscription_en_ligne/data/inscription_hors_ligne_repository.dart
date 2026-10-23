import 'dart:convert';
import '../../../core/securite/gardien_actions_sensibles.dart';

import 'package:uuid/uuid.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/inscription_en_ligne.dart';

/// Inscriptions en ligne d'abord hors connexion (REG-08).
///
/// Avec réseau : tout passe au serveur. Sans réseau :
/// • la demande (réinscription ou nouvel élève) est gardée sur l'appareil
///   sous une clé générée ici, avec un numéro de dossier PROVISOIRE
///   (`PROV-<appareil>-0001`) ; le serveur reconnaît la clé au retour du
///   réseau (jamais de doublon) et attribue le numéro définitif ; une
///   saisie faite avant la date limite reste recevable 7 jours après ;
/// • les pièces photographiées partent APRÈS leur dossier (même file) ;
/// • le dossier apparaît tout de suite dans « Mes dossiers » ;
/// • côté Direction, décisions, paiements en espèces au guichet et
///   paramétrage de la campagne partent aussi en file ;
/// • seul le paiement Orange Money et l'ouverture d'une pièce exigent le
///   réseau (statut lu en direct, lien signé).
class InscriptionHorsLigneRepository implements InscriptionEnLigneRepository {
  InscriptionHorsLigneRepository(this._distant, this._file, this._store, this._identifiantAppareil);

  final InscriptionEnLigneRepository _distant;
  final DriftSyncRepository _file;
  final CacheDocumentStore _store;
  final Future<String> Function() _identifiantAppareil;
  final Uuid _uuid = const Uuid();

  static const entiteDemande = 'demandes_inscription';
  static const entitePiece = 'pieces_inscription';
  static const entiteRetrait = 'retraits_inscription';
  static const entiteDecision = 'decisions_inscription';
  static const entiteGuichet = 'guichet_inscription';
  static const entiteCampagne = 'campagnes_inscription';

  /// Entités rejouées par `RejeuInscriptions`, dans cet ordre de dépendance.
  static const entites = [entiteCampagne, entiteDemande, entitePiece, entiteRetrait, entiteDecision, entiteGuichet];

  static bool _horsLigne(Object e) => e is ErreurInscriptionEnLigne && e.code == 'HORS_CONNEXION';

  Future<void> _enfiler(String id, String entite, Map<String, dynamic> payload) => _file.enfiler(
        SyncEntree(id: id, entite: entite, operation: 'upsert', payload: jsonEncode(payload)),
      );

  Future<List<SyncEntree>> _enAttente(String entite) async =>
      [for (final e in await _file.entreesEnAttente()) if (e.entite == entite) e];

  Future<String> _prochainNumeroProvisoire() async {
    final document = await _store.lireDocument('compteur_provisoire', CacheDocumentStore.cleUnique);
    final n = ((document?['n'] as num?)?.toInt() ?? 0) + 1;
    await _store.ecrireDocument('compteur_provisoire', CacheDocumentStore.cleUnique, {'n': n});
    final appareil = (await _identifiantAppareil()).replaceAll('-', '').toUpperCase();
    final court = appareil.length >= 4 ? appareil.substring(0, 4) : appareil.padRight(4, '0');
    return 'PROV-$court-${n.toString().padLeft(4, '0')}';
  }

  // -------------------------------------------------------------------------
  // Familles
  // -------------------------------------------------------------------------
  @override
  Future<List<ReinscriptionPossible>> reinscriptionsPossibles() => _distant.reinscriptionsPossibles();

  @override
  Future<List<CampagneOuverte>> campagnesOuvertes({String? recherche}) =>
      _distant.campagnesOuvertes(recherche: recherche);

  @override
  Future<ResultatDemandeInscription> soumettre(SaisieDemandeInscription saisie) async {
    final cle = saisie.id ?? _uuid.v4();
    final avecCle = saisie.avecCle(cle, saisiLe: saisie.saisiLe ?? DateTime.now());
    try {
      return await _distant.soumettre(avecCle);
    } on ErreurInscriptionEnLigne catch (e) {
      if (!_horsLigne(e)) rethrow;
    }
    final numero = await _prochainNumeroProvisoire();
    final envoi = avecCle.avecCle(cle, numeroProvisoire: numero);
    await _enfiler(cle, entiteDemande, {
      ...envoi.versParams(),
      // Affichage local tant que l'école n'a pas reçu le dossier.
      '_affichage': {
        'nom': saisie.nom,
        'prenom': saisie.prenom,
        'date_naissance': saisie.dateNaissance?.toIso8601String(),
        'niveau_id': saisie.niveauId ?? '',
        'niveau_nom': saisie.libelleNiveau,
        'niveau_isced': saisie.niveauIsced,
        'pieces_requises': [for (final p in saisie.piecesRequises) p.versJson()],
        'etablissement_nom': saisie.libelleEcole,
        'type': saisie.type,
        'fiche_eleve_id': saisie.ficheEleveId,
        'intention': saisie.intention,
        'demandeur_qualite': saisie.demandeurQualite,
        'responsable_financier': saisie.responsableFinancier,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    });
    return ResultatDemandeInscription(
      id: cle,
      numeroDossier: numero,
      statut: StatutDemandeInscription.soumise,
      enAttenteEnvoi: true,
    );
  }

  @override
  Future<void> deposerPiece(String demandeId, PieceAEnvoyer piece) async {
    // Dossier encore sur l'appareil : la pièce le suit dans la file.
    final dossierLocal = (await _enAttente(entiteDemande)).any((e) => e.id == demandeId);
    if (!dossierLocal) {
      try {
        return await _distant.deposerPiece(demandeId, piece);
      } on ErreurInscriptionEnLigne catch (e) {
        if (!_horsLigne(e)) rethrow;
      }
    }
    await _enfiler('$demandeId/${piece.code}', entitePiece, {
      'demande_id': demandeId,
      'code': piece.code,
      'extension': piece.extension,
      'octets': base64Encode(piece.octets),
    });
  }

  @override
  Future<List<DemandeInscription>> mesDemandes() async {
    List<DemandeInscription> connues;
    try {
      connues = await _distant.mesDemandes();
    } on ErreurInscriptionEnLigne catch (e) {
      if (!_horsLigne(e)) rethrow;
      connues = const [];
    }
    final locales = await demandesEnAttente();
    final piecesEnAttente = await _piecesEnAttente();
    final retraits = {for (final e in await _enAttente(entiteRetrait)) (jsonDecode(e.payload) as Map)['p_demande']};
    return [
      ...locales.map((d) => _avecPieces(d, piecesEnAttente[d.id])),
      for (final d in connues)
        if (!locales.any((l) => l.id == d.id))
          _avecPieces(retraits.contains(d.id) ? d.avecStatut(StatutDemandeInscription.retiree) : d, piecesEnAttente[d.id]),
    ];
  }

  /// Dossiers saisis sur cet appareil et pas encore reçus par l'école.
  Future<List<DemandeInscription>> demandesEnAttente() async => [
        for (final e in await _enAttente(entiteDemande)) _depuisFile(e),
      ];

  static DemandeInscription _depuisFile(SyncEntree e) {
    final p = jsonDecode(e.payload) as Map<String, dynamic>;
    final a = (p['_affichage'] as Map<String, dynamic>?) ?? const {};
    return DemandeInscription.depuisJson({
      ...a,
      'id': e.id,
      'etablissement_id': '',
      'campagne_id': p['p_campagne'],
      'numero_dossier': p['p_numero_provisoire'] ?? '',
      'numero_provisoire': p['p_numero_provisoire'],
      'statut': 'soumise',
      'en_attente_envoi': true,
    });
  }

  Future<Map<String, Map<String, String>>> _piecesEnAttente() async {
    final resultat = <String, Map<String, String>>{};
    for (final e in await _enAttente(entitePiece)) {
      final p = jsonDecode(e.payload) as Map<String, dynamic>;
      (resultat[p['demande_id'] as String] ??= {})[p['code'] as String] = '';
    }
    return resultat;
  }

  /// Ajoute les pièces en attente d'envoi (chemin vide = sur l'appareil).
  static DemandeInscription _avecPieces(DemandeInscription d, Map<String, String>? enAttente) {
    if (enAttente == null || enAttente.isEmpty) return d;
    return DemandeInscription.depuisJson({
      ..._versJson(d),
      'pieces_demandes_inscription': [
        for (final e in {...d.pieces, ...enAttente}.entries) {'code': e.key, 'chemin': e.value},
      ],
    });
  }

  static Map<String, dynamic> _versJson(DemandeInscription d) => {
        'id': d.id,
        'etablissement_id': d.etablissementId,
        'campagne_id': d.campagneId,
        'type': d.type,
        'numero_dossier': d.numeroDossier,
        'statut': d.statut.code,
        'nom': d.nom,
        'prenom': d.prenom,
        'date_naissance': d.dateNaissance.toIso8601String(),
        'niveau_id': d.niveauId,
        'niveau_nom': d.niveauNom,
        'etablissement_nom': d.etablissementNom,
        'sexe': d.sexe,
        'fiche_eleve_id': d.ficheEleveId,
        'intention': d.intention,
        'demandeur_qualite': d.demandeurQualite,
        'responsable_financier': d.responsableFinancier,
        'alertes': d.alertes,
        'motif': d.motif,
        'rang_attente': d.rangAttente,
        'offre_expire_le': d.offreExpireLe?.toUtc().toIso8601String(),
        'montant_a_regler': d.montantARegler,
        'inscription_id': d.inscriptionId,
        'numero_provisoire': d.numeroProvisoire,
        'created_at': d.creeLe?.toUtc().toIso8601String(),
        'en_attente_envoi': d.enAttenteEnvoi,
        'niveau_isced': d.niveauIsced,
        'pieces_requises': [for (final p in d.piecesRequises) p.versJson()],
        'devise': d.devise,
      };

  @override
  Future<void> retirer(String demandeId) async {
    // Jamais parti : on le retire simplement de la file, avec ses pièces.
    final enFile = await _file.entreesEnAttente();
    if (enFile.any((e) => e.entite == entiteDemande && e.id == demandeId)) {
      for (final e in enFile) {
        if (e.id == demandeId || (e.entite == entitePiece && e.id.startsWith('$demandeId/'))) {
          await _file.retirer(e.id);
        }
      }
      return;
    }
    try {
      await _distant.retirer(demandeId);
    } on ErreurInscriptionEnLigne catch (e) {
      if (!_horsLigne(e)) rethrow;
      await _enfiler('retrait/$demandeId', entiteRetrait, {'p_demande': demandeId});
    }
  }

  // -------------------------------------------------------------------------
  // Direction
  // -------------------------------------------------------------------------
  @override
  Future<CampagneInscription?> campagne(String etablissementId, String anneeScolaireId) =>
      _distant.campagne(etablissementId, anneeScolaireId);

  @override
  Future<String?> enregistrerCampagne(CampagneInscription campagne) async {
    try {
      return await _distant.enregistrerCampagne(campagne);
    } on ErreurInscriptionEnLigne catch (e) {
      if (!_horsLigne(e)) rethrow;
    }
    await _enfiler('campagne/${campagne.etablissementId}/${campagne.anneeScolaireId}', entiteCampagne,
        campagne.versParams());
    return null;
  }

  @override
  Future<List<DemandeInscription>> dossiers(String campagneId) => _distant.dossiers(campagneId);

  @override
  Future<TableauCampagne> tableau(String campagneId) => _distant.tableau(campagneId);

  @override
  Future<StatutDemandeInscription?> traiter(
    String demandeId,
    DecisionDossier decision, {
    String? motif,
    String? niveauId,
    bool forcer = false,
  }) async {
    try {
      return await _distant.traiter(demandeId, decision, motif: motif, niveauId: niveauId, forcer: forcer);
    } on ErreurInscriptionEnLigne catch (e) {
      if (!_horsLigne(e)) rethrow;
    }
    if (decision.motifObligatoire && (motif == null || motif.trim().isEmpty)) {
      throw const ErreurInscriptionEnLigne('MOTIF_OBLIGATOIRE');
    }
    await _enfiler('decision/$demandeId', entiteDecision, {
      'p_demande': demandeId,
      'p_decision': decision.code,
      'p_motif': motif,
      'p_niveau': niveauId,
      'p_forcer': forcer,
    });
    return null;
  }

  @override
  Future<String?> finaliserAuGuichet(String demandeId, {String? classeId, double? montant, String moyen = 'especes'}) async {
    await exigerCodeSecret('Encaisser et inscrire au guichet');
    try {
      return await _distant.finaliserAuGuichet(demandeId, classeId: classeId, montant: montant, moyen: moyen);
    } on ErreurInscriptionEnLigne catch (e) {
      if (!_horsLigne(e)) rethrow;
    }
    // Espèces reçues sans réseau : l'argent est là, l'inscription suivra.
    await _enfiler('guichet/$demandeId', entiteGuichet, {
      'p_demande': demandeId,
      'p_classe': classeId,
      'p_montant': montant,
      'p_moyen': moyen,
    });
    return null;
  }

  @override
  Future<Uri> lienPiece(String chemin) async {
    try {
      return await _distant.lienPiece(chemin);
    } on ErreurInscriptionEnLigne catch (e) {
      if (_horsLigne(e)) throw const ErreurInscriptionEnLigne('RESEAU_REQUIS');
      rethrow;
    }
  }

  @override
  Future<Map<String, String>> nomsNiveaux(List<String> niveauIds) => _distant.nomsNiveaux(niveauIds);

  /// Décisions et paiements au guichet pas encore envoyés (Direction).
  Future<Set<String>> dossiersAvecActionEnAttente() async => {
        for (final e in await _file.entreesEnAttente())
          if (e.entite == entiteDecision || e.entite == entiteGuichet)
            (jsonDecode(e.payload) as Map<String, dynamic>)['p_demande'] as String,
      };
}
