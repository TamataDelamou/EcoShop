import 'dart:convert';
import '../../../core/securite/gardien_actions_sensibles.dart';

import 'package:uuid/uuid.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/dons.dart';
import 'supabase_dons_repository.dart';

/// Dons et donateurs d'abord hors connexion (REG-03 C7).
///
/// Avec réseau : tout passe au serveur, comme avant. Sans réseau :
/// • un don est gardé sur l'appareil, mis en file d'envoi sous une clé
///   générée ici, et reçoit un reçu PROVISOIRE (`PROV-<appareil>-0001`) ; le
///   numéro définitif, continu et sans trou, est attribué par le serveur à
///   l'envoi, qui reconnaît la clé et ne crée jamais de doublon ;
/// • donateurs, campagnes, engagements et annulations partent en file ;
/// • les listes affichent ce qui attend l'envoi à côté de ce qui est connu ;
/// • l'emploi des fonds affectés attend le réseau (solde vérifié au serveur).
class DonsHorsLigneRepository implements DonsRepository {
  DonsHorsLigneRepository(this._distant, this._file, this._store, this._identifiantAppareil);

  final DonsRepository _distant;
  final DriftSyncRepository _file;
  final CacheDocumentStore _store;
  final Future<String> Function() _identifiantAppareil;
  final Uuid _uuid = const Uuid();

  static const entiteDon = 'dons';
  static const entiteDonateur = 'donateurs';
  static const entiteArchivageDonateur = 'donateurs_archivage';
  static const entiteAffectation = 'affectations_dons';
  static const entiteEngagement = 'engagements_dons';
  static const entiteAnnulation = 'dons_annulation';

  static bool _horsLigne(Object e) => e is ErreurDons && e.code == 'HORS_CONNEXION';

  Future<void> _enfiler(String id, String entite, Map<String, dynamic> payload) => _file.enfiler(
        SyncEntree(id: id, entite: entite, operation: 'upsert', payload: jsonEncode(payload)),
      );

  Future<List<Map<String, dynamic>>> _enAttente(String entite) async {
    final entrees = await _file.entreesEnAttente();
    return [
      for (final e in entrees)
        if (e.entite == entite) jsonDecode(e.payload) as Map<String, dynamic>,
    ];
  }

  Future<String> _prochainNumeroProvisoire() async {
    final document = await _store.lireDocument('compteur_provisoire', CacheDocumentStore.cleUnique);
    final n = ((document?['n'] as num?)?.toInt() ?? 0) + 1;
    await _store.ecrireDocument('compteur_provisoire', CacheDocumentStore.cleUnique, {'n': n});
    final appareil = (await _identifiantAppareil()).replaceAll('-', '').toUpperCase();
    final court = appareil.length >= 4 ? appareil.substring(0, 4) : appareil.padRight(4, '0');
    return 'PROV-$court-${n.toString().padLeft(4, '0')}';
  }

  // -------------------------------------------------------------------------
  // Écritures
  // -------------------------------------------------------------------------
  @override
  Future<ResultatDon> enregistrerDon(SaisieDon saisie) async {
    await exigerCodeSecret('Enregistrer le don');
    final id = saisie.id ?? _uuid.v4();
    final avecCle = saisie.avecId(id, saisiLe: saisie.saisiLe ?? DateTime.now());
    try {
      return await _distant.enregistrerDon(avecCle);
    } on ErreurDons catch (e) {
      if (!_horsLigne(e)) rethrow;
    }
    final numero = await _prochainNumeroProvisoire();
    await _enfiler(id, entiteDon, avecCle.avecId(id, numeroProvisoire: numero).versParams());
    return ResultatDon(id: id, numeroRecu: numero, comptabilise: false, provisoire: true);
  }

  @override
  Future<void> annulerDon(String donId, String motif) async {
    await exigerCodeSecret('Annuler le don');
    try {
      await _distant.annulerDon(donId, motif);
    } on ErreurDons catch (e) {
      if (!_horsLigne(e)) rethrow;
      await _enfiler('annulation-$donId', entiteAnnulation, {'p_don_id': donId, 'p_motif': motif});
    }
  }

  @override
  Future<String> enregistrerDonateur(Donateur donateur) async {
    final id = donateur.id ?? _uuid.v4();
    final ligne = {...donateur.versJson(), 'id': id};
    try {
      return await _distant.enregistrerDonateur(Donateur.depuisJson(ligne));
    } on ErreurDons catch (e) {
      if (!_horsLigne(e)) rethrow;
    }
    await _enfiler(id, entiteDonateur, ligne);
    return id;
  }

  @override
  Future<void> archiverDonateur(String donateurId) async {
    try {
      await _distant.archiverDonateur(donateurId);
    } on ErreurDons catch (e) {
      if (!_horsLigne(e)) rethrow;
      await _enfiler('archivage-$donateurId', entiteArchivageDonateur,
          {'id': donateurId, 'deleted_at': DateTime.now().toUtc().toIso8601String()});
    }
  }

  @override
  Future<String> enregistrerAffectation(AffectationDon affectation) async {
    final id = affectation.id ?? _uuid.v4();
    final ligne = {...affectation.versJson(), 'id': id};
    try {
      return await _distant.enregistrerAffectation(AffectationDon.depuisJson(ligne));
    } on ErreurDons catch (e) {
      if (!_horsLigne(e)) rethrow;
    }
    await _enfiler(id, entiteAffectation, ligne);
    return id;
  }

  @override
  Future<void> enregistrerEngagement({
    required String etablissementId,
    required String donateurId,
    String? affectationId,
    required double montant,
    required String periodicite,
    required DateTime dateDebut,
  }) async {
    try {
      await _distant.enregistrerEngagement(
        etablissementId: etablissementId,
        donateurId: donateurId,
        affectationId: affectationId,
        montant: montant,
        periodicite: periodicite,
        dateDebut: dateDebut,
      );
    } on ErreurDons catch (e) {
      if (!_horsLigne(e)) rethrow;
      final id = _uuid.v4();
      await _enfiler(
        id,
        entiteEngagement,
        SupabaseDonsRepository.parametresEngagement(
          id: id,
          etablissementId: etablissementId,
          donateurId: donateurId,
          affectationId: affectationId,
          montant: montant,
          periodicite: periodicite,
          dateDebut: dateDebut,
        ),
      );
    }
  }

  @override
  Future<double> constaterEmploi({
    required String affectationId,
    required double montant,
    required String libelle,
    required DateTime date,
  }) async {
    await exigerCodeSecret('Constater l’emploi des fonds');
    try {
      return await _distant.constaterEmploi(affectationId: affectationId, montant: montant, libelle: libelle, date: date);
    } on ErreurDons catch (e) {
      if (_horsLigne(e)) throw const ErreurDons('RESEAU_REQUIS_EMPLOI');
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Lectures : ce qui est connu + ce qui attend l'envoi
  // -------------------------------------------------------------------------
  Future<List<T>> _ouVide<T>(Future<List<T>> Function() lecture) async {
    try {
      return await lecture();
    } on ErreurDons catch (e) {
      if (_horsLigne(e)) return <T>[];
      rethrow;
    }
  }

  @override
  Future<List<Donateur>> donateurs(String etablissementId) async {
    final base = await _ouVide(() => _distant.donateurs(etablissementId));
    final parId = {for (final d in base) d.id: d};
    for (final ligne in await _enAttente(entiteDonateur)) {
      if (ligne['etablissement_id'] == etablissementId) parId[ligne['id'] as String] = Donateur.depuisJson(ligne);
    }
    final archives = {for (final a in await _enAttente(entiteArchivageDonateur)) a['id'] as String};
    final liste = [for (final d in parId.values) if (!archives.contains(d.id)) d]..sort((a, b) => a.nom.compareTo(b.nom));
    return liste;
  }

  @override
  Future<List<AffectationDon>> affectations(String etablissementId) async {
    final base = await _ouVide(() => _distant.affectations(etablissementId));
    final parId = {for (final a in base) a.id: a};
    for (final ligne in await _enAttente(entiteAffectation)) {
      if (ligne['etablissement_id'] == etablissementId) parId[ligne['id'] as String] = AffectationDon.depuisJson(ligne);
    }
    return parId.values.toList();
  }

  Future<Map<String, String>> _nomsDonateurs(String etablissementId) async {
    try {
      return {for (final d in await donateurs(etablissementId)) if (d.id != null) d.id!: d.nomComplet};
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, String>> _libellesAffectations(String etablissementId) async {
    try {
      return {for (final a in await affectations(etablissementId)) if (a.id != null) a.id!: a.libelle};
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<List<Don>> dons(String etablissementId, int annee) async {
    final base = await _ouVide(() => _distant.dons(etablissementId, annee));
    final connus = {for (final d in base) d.id};
    final annulations = {for (final a in await _enAttente(entiteAnnulation)) a['p_don_id'] as String};
    final enAttente = [
      for (final p in await _enAttente(entiteDon))
        if (p['p_etablissement'] == etablissementId && !connus.contains(p['p_id'])) SaisieDon.depuisParams(p),
    ].where((s) => s.date.year == annee).toList();
    final noms = enAttente.isEmpty ? const <String, String>{} : await _nomsDonateurs(etablissementId);
    final libelles = enAttente.isEmpty ? const <String, String>{} : await _libellesAffectations(etablissementId);
    final provisoires = [
      for (final s in enAttente)
        Don(
          id: s.id!,
          numeroRecu: s.numeroProvisoire ?? 'PROV',
          dateDon: s.date,
          montant: s.montant,
          nature: s.nature,
          moyen: s.moyen,
          donateurId: s.donateurId,
          donateurNom: s.donateurId == null ? null : noms[s.donateurId],
          affectation: s.affectationId == null ? null : libelles[s.affectationId],
          anonyme: s.anonyme,
          annule: annulations.contains(s.id),
          provisoire: true,
        ),
    ];
    final tous = [
      ...provisoires,
      for (final d in base)
        annulations.contains(d.id) && !d.annule
            ? Don(
                id: d.id,
                numeroRecu: d.numeroRecu,
                dateDon: d.dateDon,
                montant: d.montant,
                nature: d.nature,
                moyen: d.moyen,
                donateurId: d.donateurId,
                donateurNom: d.donateurNom,
                affectation: d.affectation,
                anonyme: d.anonyme,
                annule: true,
                motifAnnulation: 'Annulation en attente d\'envoi',
              )
            : d,
    ]..sort((a, b) => b.dateDon.compareTo(a.dateDon));
    return tous;
  }

  @override
  Future<RecuDon> recu(String donId) async {
    for (final p in await _enAttente(entiteDon)) {
      if (p['p_id'] != donId) continue;
      final s = SaisieDon.depuisParams(p);
      final noms = await _nomsDonateurs(s.etablissementId);
      final libelles = await _libellesAffectations(s.etablissementId);
      return RecuDon(
        numeroRecu: s.numeroProvisoire ?? 'PROV',
        numeroProvisoire: s.numeroProvisoire,
        provisoire: true,
        dateDon: s.date,
        montant: s.montant,
        nature: s.nature,
        moyen: s.moyen,
        reference: s.reference,
        affectation: s.affectationId == null ? null : libelles[s.affectationId],
        donateurNom: s.donateurId == null ? null : noms[s.donateurId],
        anonyme: s.anonyme,
      );
    }
    return _distant.recu(donId);
  }

  @override
  Future<TableauBordDons> tableauBord(String etablissementId, int annee) => _distant.tableauBord(etablissementId, annee);

  @override
  Future<ReleveDonateur> releve(String donateurId, int annee) => _distant.releve(donateurId, annee);
}
