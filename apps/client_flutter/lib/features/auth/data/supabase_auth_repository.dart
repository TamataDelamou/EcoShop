import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/role_racine.dart';
import '../../etablissement/domain/etablissement.dart';
import '../domain/auth_repository.dart';
import '../domain/canal_otp.dart';
import '../domain/profil.dart';

/// Implémentation Supabase du port [AuthRepository] (ch. 5).
///
/// Toute décision (rôle attribuable, fiche revendicable, établissement
/// activable) est déléguée à une fonction Postgres : le client n'applique
/// aucune règle métier de son propre chef.
class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> demanderCode({
    required String identifiant,
    required CanalOtp canal,
  }) async {
    await _executer(() async {
      switch (canal) {
        case CanalOtp.sms:
        case CanalOtp.whatsapp:
          await _client.auth.signInWithOtp(
            phone: identifiant,
            channel: canal == CanalOtp.whatsapp
                ? OtpChannel.whatsapp
                : OtpChannel.sms,
          );
        case CanalOtp.magicLink:
          await _client.auth.signInWithOtp(
            email: identifiant,
            emailRedirectTo: _redirectionLien,
          );
        case CanalOtp.emailOtp:
          await _client.auth.signInWithOtp(email: identifiant);
      }
    });
  }

  @override
  Future<void> verifierCode({
    required String identifiant,
    required CanalOtp canal,
    required String code,
  }) async {
    if (!canal.demandeSaisieCode) {
      // Le lien magique ouvre la session depuis le lien profond : il n'y a
      // aucun code à vérifier ici.
      throw const ErreurAuth('CANAL_SANS_CODE');
    }

    await _executer(() async {
      if (canal.entree == TypeIdentifiant.telephone) {
        await _client.auth.verifyOTP(
          phone: identifiant,
          token: code,
          type: OtpType.sms,
        );
      } else {
        await _client.auth.verifyOTP(
          email: identifiant,
          token: code,
          type: OtpType.email,
        );
      }
    });
  }

  @override
  Future<Profil?> profilCourant() async {
    final utilisateur = _client.auth.currentUser;
    if (utilisateur == null) return null;

    return _executer(() async {
      final ligne = await _client
          .from('profiles')
          .select()
          .eq('id', utilisateur.id)
          .maybeSingle();
      return ligne == null ? null : Profil.depuisJson(ligne);
    });
  }

  @override
  Future<void> choisirRole(RoleRacine role) async {
    await _executer(
      () => _client.rpc<void>(
        'choisir_role_racine',
        params: {'p_role': role.code},
      ),
    );
  }

  @override
  Future<void> lierFiche({
    required String matricule,
    required DateTime dateNaissance,
  }) async {
    await _executer(
      () => _client.rpc<void>(
        'lier_compte_a_fiche',
        params: {
          'p_matricule': matricule.trim(),
          // Date seule, sans fuseau : la fiche scolaire porte une date civile.
          'p_date_naissance': _formatDateIso(dateNaissance),
        },
      ),
    );
  }

  @override
  Future<bool> ficheLiee() async {
    final utilisateur = _client.auth.currentUser;
    if (utilisateur == null) return false;

    return _executer(() async {
      final lignes = await _client
          .from('fiches_eleves')
          .select('id')
          .eq('profile_id', utilisateur.id)
          .limit(1);
      return lignes.isNotEmpty;
    });
  }

  @override
  Future<List<Etablissement>> mesEtablissements() async {
    return _executer(() async {
      // RLS restreint déjà la table aux établissements dont l'appelant est
      // membre actif : aucun filtre client n'est nécessaire ni suffisant.
      final lignes = await _client.from('etablissements').select().order('nom');
      return lignes
          .map((l) => Etablissement.depuisJson(l))
          .toList(growable: false);
    });
  }

  @override
  Future<void> definirEtablissementActif(String etablissementId) async {
    await _executer(
      () => _client.rpc<void>(
        'definir_etablissement_actif',
        params: {'p_etablissement': etablissementId},
      ),
    );
  }

  @override
  Future<void> deconnecter() => _executer(() => _client.auth.signOut());

  /// Lien profond de retour du lien magique (déclaré dans `config.toml`).
  static const String _redirectionLien = 'io.gsg.ecoshop://login-callback';

  static String _formatDateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Traduit les exceptions Supabase en [ErreurAuth] à code stable.
  ///
  /// Les fonctions Postgres lèvent des exceptions dont le message *est* le
  /// code métier (`TROP_DE_TENTATIVES`…) : on le transporte tel quel plutôt
  /// que de deviner la cause à partir du texte.
  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (e) {
      throw ErreurAuth(_codeDepuisMessage(e.message), e.message);
    } on PostgrestException catch (e) {
      throw ErreurAuth(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_INATTENDUE';
  }
}
