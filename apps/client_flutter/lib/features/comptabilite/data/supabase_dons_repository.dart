import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../domain/dons.dart';

/// Implémentation Supabase (REG-03 C5). Donateurs, campagnes et
/// engagements : tables (RLS direction/comptables) ; dons et emplois de
/// fonds : RPC uniquement (numérotation et comptabilité côté serveur).
///
/// Hors connexion d'abord (C7) : les consultations sont gardées sur
/// l'appareil ; les écritures acceptent la clé générée par l'appareil
/// (upsert, `p_id`), si bien qu'un envoi rejoué ne crée jamais de doublon.
class SupabaseDonsRepository implements DonsRepository {
  const SupabaseDonsRepository(this._client, [this._lecture]);

  final SupabaseClient _client;
  final LectureHorsLigne? _lecture;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<T> _lire<T>(String type, String cle, Future<Object?> Function() source, T Function(Object? json) decoder) {
    final lecture = _lecture;
    if (lecture == null) return source().then(decoder);
    return lecture.lire(type: type, cle: cle, source: source, decoder: decoder);
  }

  static List<Map<String, dynamic>> _liste(Object? json) =>
      [for (final l in json! as List<dynamic>) l as Map<String, dynamic>];

  @override
  Future<TableauBordDons> tableauBord(String etablissementId, int annee) => _executer(() => _lire(
        'tableau_bord_dons',
        '$etablissementId/$annee',
        () => _client.rpc<Map<String, dynamic>>('tableau_bord_dons',
            params: {'p_etablissement': etablissementId, 'p_annee': annee}),
        (json) => TableauBordDons.depuisJson(json! as Map<String, dynamic>),
      ));

  @override
  Future<List<Don>> dons(String etablissementId, int annee) => _executer(() => _lire(
        'dons',
        '$etablissementId/$annee',
        () => _client
            .from('dons')
            .select('*, donateurs(nom, prenom), affectations_dons(libelle)')
            .eq('etablissement_id', etablissementId)
            .gte('date_don', '$annee-01-01')
            .lte('date_don', '$annee-12-31')
            .order('date_don', ascending: false)
            .order('numero_recu', ascending: false),
        (json) => [for (final l in _liste(json)) Don.depuisJson(l)],
      ));

  @override
  Future<List<Donateur>> donateurs(String etablissementId) => _executer(() => _lire(
        'donateurs',
        etablissementId,
        () => _client
            .from('donateurs')
            .select()
            .eq('etablissement_id', etablissementId)
            .isFilter('deleted_at', null)
            .order('nom'),
        (json) => [for (final l in _liste(json)) Donateur.depuisJson(l)],
      ));

  @override
  Future<List<AffectationDon>> affectations(String etablissementId) => _executer(() => _lire(
        'affectations_dons',
        etablissementId,
        () => _client
            .from('affectations_dons')
            .select()
            .eq('etablissement_id', etablissementId)
            .order('active', ascending: false)
            .order('libelle'),
        (json) => [for (final l in _liste(json)) AffectationDon.depuisJson(l)],
      ));

  @override
  Future<String> enregistrerDonateur(Donateur donateur) => _executer(() async {
        if (donateur.id == null) {
          final l = await _client.from('donateurs').insert(donateur.versJson()).select('id').single();
          return l['id'] as String;
        }
        await _client.from('donateurs').upsert({
          ...donateur.versJson(),
          'id': donateur.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        return donateur.id!;
      });

  @override
  Future<void> archiverDonateur(String donateurId) => _executer(() => _client
      .from('donateurs')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', donateurId));

  @override
  Future<String> enregistrerAffectation(AffectationDon affectation) => _executer(() async {
        if (affectation.id == null) {
          final l = await _client.from('affectations_dons').insert(affectation.versJson()).select('id').single();
          return l['id'] as String;
        }
        await _client.from('affectations_dons').upsert({...affectation.versJson(), 'id': affectation.id});
        return affectation.id!;
      });

  @override
  Future<void> enregistrerEngagement({
    required String etablissementId,
    required String donateurId,
    String? affectationId,
    required double montant,
    required String periodicite,
    required DateTime dateDebut,
  }) =>
      enregistrerEngagementBrut(parametresEngagement(
        id: null,
        etablissementId: etablissementId,
        donateurId: donateurId,
        affectationId: affectationId,
        montant: montant,
        periodicite: periodicite,
        dateDebut: dateDebut,
      ));

  static Map<String, dynamic> parametresEngagement({
    required String? id,
    required String etablissementId,
    required String donateurId,
    String? affectationId,
    required double montant,
    required String periodicite,
    required DateTime dateDebut,
  }) =>
      {
        if (id != null) 'id': id,
        'etablissement_id': etablissementId,
        'donateur_id': donateurId,
        'affectation_id': affectationId,
        'montant': montant,
        'periodicite': periodicite,
        'date_debut': _iso(dateDebut),
      };

  /// Engagement (upsert si la ligne porte déjà sa clé d'appareil).
  Future<void> enregistrerEngagementBrut(Map<String, dynamic> ligne) =>
      _executer(() => _client.from('engagements_dons').upsert(ligne));

  @override
  Future<ResultatDon> enregistrerDon(SaisieDon saisie) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('enregistrer_don', params: saisie.versParams());
        return ResultatDon.depuisJson(json);
      });

  @override
  Future<void> annulerDon(String donId, String motif) =>
      _executer(() => _client.rpc<dynamic>('annuler_don', params: {'p_don_id': donId, 'p_motif': motif}));

  @override
  Future<RecuDon> recu(String donId) => _executer(() => _lire(
        'recu_don',
        donId,
        () => _client.rpc<Map<String, dynamic>>('recu_don', params: {'p_don_id': donId}),
        (json) => RecuDon.depuisJson(json! as Map<String, dynamic>),
      ));

  @override
  Future<ReleveDonateur> releve(String donateurId, int annee) => _executer(() => _lire(
        'releve_donateur',
        '$donateurId/$annee',
        () => _client.rpc<Map<String, dynamic>>('releve_donateur',
            params: {'p_donateur_id': donateurId, 'p_annee': annee}),
        (json) => ReleveDonateur.depuisJson(json! as Map<String, dynamic>),
      ));

  @override
  Future<double> constaterEmploi({
    required String affectationId,
    required double montant,
    required String libelle,
    required DateTime date,
  }) =>
      _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('constater_emploi_fonds', params: {
          'p_affectation_id': affectationId,
          'p_montant': montant,
          'p_libelle': libelle,
          'p_date': _iso(date),
        });
        return (json['solde'] as num?)?.toDouble() ?? 0;
      });

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      throw ErreurDons(RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier) ? premier : 'ERREUR_RESEAU');
    } catch (e) {
      if (estErreurReseau(e)) throw const ErreurDons('HORS_CONNEXION');
      rethrow;
    }
  }
}
