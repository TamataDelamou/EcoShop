import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../domain/invitation.dart';

/// Implémentation Supabase de [InvitationsRepository]. Tout passe par des
/// fonctions serveur qui vérifient elles-mêmes les droits et la règle REG-16.
class SupabaseInvitationsRepository implements InvitationsRepository {
  const SupabaseInvitationsRepository(this._client);

  final SupabaseClient _client;

  List<Map<String, dynamic>> _lignes(Object? r) => [for (final l in (r as List)) (l as Map).cast<String, dynamic>()];

  @override
  Future<List<InvitationRecue>> mesInvitations() => _executer(() async {
        final r = await _client.rpc<dynamic>('mes_invitations');
        return [for (final l in _lignes(r)) InvitationRecue.depuisJson(l)];
      });

  @override
  Future<void> repondre(String invitationId, {required bool accepter}) => _executer(() =>
      _client.rpc<dynamic>('repondre_invitation', params: {'p_invitation': invitationId, 'p_accepter': accepter}));

  @override
  Future<List<InvitationEnvoyee>> invitationsEtablissement(String etablissementId) => _executer(() async {
        final r = await _client.rpc<dynamic>('invitations_etablissement', params: {'p_etablissement': etablissementId});
        return [for (final l in _lignes(r)) InvitationEnvoyee.depuisJson(l)];
      });

  @override
  Future<List<PosteInvitable>> postes(String etablissementId) => _executer(() async {
        final r = await _client.rpc<dynamic>('postes_invitables', params: {'p_etablissement': etablissementId});
        return [for (final l in _lignes(r)) PosteInvitable(l['id'] as String, l['nom'] as String)];
      });

  @override
  Future<void> inviter({
    required String etablissementId,
    required String identifiant,
    required RoleRacine role,
    String? posteId,
  }) =>
      _executer(() => _client.rpc<dynamic>('inviter_membre', params: {
            'p_etablissement': etablissementId,
            'p_identifiant': identifiant,
            'p_role': role.code,
            'p_poste': posteId,
          }));

  @override
  Future<InvitationAcceptee> accepterParCode(String code) => _executer(() async {
        final r = ((await _client.rpc<dynamic>('accepter_invitation_par_code', params: {'p_code': code})) as Map)
            .cast<String, dynamic>();
        final erreur = r['erreur'] as String?;
        if (erreur != null) throw ErreurInvitations(erreur);
        return InvitationAcceptee(
          etablissementId: r['etablissement_id'] as String,
          etablissement: r['etablissement'] as String? ?? 'l’école',
          role: r['role'] as String? ?? '',
        );
      });

  @override
  Future<void> revoquer(String invitationId) =>
      _executer(() => _client.rpc<dynamic>('revoquer_invitation', params: {'p_invitation': invitationId}));

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurInvitations(_codeDepuisMessage(e.message), e.message);
    } catch (e) {
      if (e is ErreurInvitations) rethrow;
      throw ErreurInvitations(estErreurReseau(e) ? 'ERREUR_RESEAU' : 'ERREUR_INATTENDUE', '$e');
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_INATTENDUE';
  }
}
