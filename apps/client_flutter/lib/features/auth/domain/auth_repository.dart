import '../../../core/auth/role_racine.dart';
import '../../etablissement/domain/etablissement.dart';
import 'canal_otp.dart';
import 'profil.dart';

/// Erreur métier d'authentification, portant un code stable.
///
/// Les codes proviennent des exceptions levées par les fonctions Postgres
/// (`ROLE_DEJA_DEFINI`, `TROP_DE_TENTATIVES`…) : le client les traduit en
/// message utilisateur sans jamais réinterpréter la décision du serveur.
class ErreurAuth implements Exception {
  const ErreurAuth(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurAuth($code)';
}

/// Port d'authentification — implémenté par Supabase en production, simulé en
/// test. Aucun widget ne dépend directement de `supabase_flutter`.
abstract interface class AuthRepository {
  /// Demande l'envoi d'un code sur [canal] pour [identifiant].
  ///
  /// [identifiant] doit être pré-normalisé : E.164 pour le téléphone, e-mail
  /// en minuscules. La normalisation ad hoc au moment de l'appel est interdite
  /// (ch. 5.4.1).
  Future<void> demanderCode({
    required String identifiant,
    required CanalOtp canal,
  });

  /// Vérifie le code reçu et ouvre la session.
  Future<void> verifierCode({
    required String identifiant,
    required CanalOtp canal,
    required String code,
  });

  /// Profil du compte connecté, ou null hors session.
  Future<Profil?> profilCourant();

  /// Fixe le rôle racine (RPC `choisir_role_racine`, rôles auto-inscriptibles).
  Future<void> choisirRole(RoleRacine role);

  /// Revendique une fiche élève (RPC `lier_compte_a_fiche`).
  Future<void> lierFiche({
    required String matricule,
    required DateTime dateNaissance,
  });

  /// Vrai si le compte est déjà lié à une fiche élève.
  Future<bool> ficheLiee();

  /// Établissements dont le compte est membre actif.
  Future<List<Etablissement>> mesEtablissements();

  /// Sélectionne l'établissement actif (RPC `definir_etablissement_actif`).
  Future<void> definirEtablissementActif(String etablissementId);

  /// Ferme la session.
  Future<void> deconnecter();
}
