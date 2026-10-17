import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/dons.dart';

/// Implémentation Supabase (REG-03 C5). Donateurs, campagnes et
/// engagements : tables (RLS direction/comptables) ; dons et emplois de
/// fonds : RPC uniquement (numérotation et comptabilité côté serveur).
class SupabaseDonsRepository implements DonsRepository {
  const SupabaseDonsRepository(this._client);

  final SupabaseClient _client;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<TableauBordDons> tableauBord(String etablissementId, int annee) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('tableau_bord_dons',
            params: {'p_etablissement': etablissementId, 'p_annee': annee});
        return TableauBordDons.depuisJson(json);
      });

  @override
  Future<List<Don>> dons(String etablissementId, int annee) => _executer(() async {
        final lignes = await _client
            .from('dons')
            .select('*, donateurs(nom, prenom), affectations_dons(libelle)')
            .eq('etablissement_id', etablissementId)
            .gte('date_don', '$annee-01-01')
            .lte('date_don', '$annee-12-31')
            .order('date_don', ascending: false)
            .order('numero_recu', ascending: false);
        return [for (final l in lignes) Don.depuisJson(l)];
      });

  @override
  Future<List<Donateur>> donateurs(String etablissementId) => _executer(() async {
        final lignes = await _client
            .from('donateurs')
            .select()
            .eq('etablissement_id', etablissementId)
            .isFilter('deleted_at', null)
            .order('nom');
        return [for (final l in lignes) Donateur.depuisJson(l)];
      });

  @override
  Future<List<AffectationDon>> affectations(String etablissementId) => _executer(() async {
        final lignes = await _client
            .from('affectations_dons')
            .select()
            .eq('etablissement_id', etablissementId)
            .order('active', ascending: false)
            .order('libelle');
        return [for (final l in lignes) AffectationDon.depuisJson(l)];
      });

  @override
  Future<String> enregistrerDonateur(Donateur donateur) => _executer(() async {
        if (donateur.id == null) {
          final l = await _client.from('donateurs').insert(donateur.versJson()).select('id').single();
          return l['id'] as String;
        }
        await _client
            .from('donateurs')
            .update({...donateur.versJson(), 'updated_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', donateur.id!);
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
        await _client.from('affectations_dons').update(affectation.versJson()).eq('id', affectation.id!);
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
      _executer(() => _client.from('engagements_dons').insert({
            'etablissement_id': etablissementId,
            'donateur_id': donateurId,
            'affectation_id': affectationId,
            'montant': montant,
            'periodicite': periodicite,
            'date_debut': _iso(dateDebut),
          }));

  @override
  Future<ResultatDon> enregistrerDon(SaisieDon saisie) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('enregistrer_don', params: saisie.versParams());
        return ResultatDon.depuisJson(json);
      });

  @override
  Future<void> annulerDon(String donId, String motif) =>
      _executer(() => _client.rpc<dynamic>('annuler_don', params: {'p_don_id': donId, 'p_motif': motif}));

  @override
  Future<RecuDon> recu(String donId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('recu_don', params: {'p_don_id': donId});
        return RecuDon.depuisJson(json);
      });

  @override
  Future<ReleveDonateur> releve(String donateurId, int annee) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('releve_donateur',
            params: {'p_donateur_id': donateurId, 'p_annee': annee});
        return ReleveDonateur.depuisJson(json);
      });

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
    }
  }
}
