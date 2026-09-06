import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/features/auth/domain/auth_repository.dart';
import 'package:ecoshop_client/features/auth/domain/canal_otp.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';

/// Double de test du port [AuthRepository].
///
/// Aucun test ne touche le réseau ni Supabase : le port existe précisément
/// pour rendre le parcours d'authentification vérifiable hors ligne.
class FauxAuthRepository implements AuthRepository {
  FauxAuthRepository({
    this.profil,
    this.fiche = true,
    this.etablissements = const [],
    this.erreurALever,
  });

  Profil? profil;
  bool fiche;
  List<Etablissement> etablissements;

  /// Erreur levée par le prochain appel, quel qu'il soit.
  ErreurAuth? erreurALever;

  /// Journal des appels, pour vérifier ce qui a été transmis au serveur.
  final List<String> appels = [];

  void _peutEchouer(String appel) {
    appels.add(appel);
    final erreur = erreurALever;
    if (erreur != null) {
      erreurALever = null;
      throw erreur;
    }
  }

  @override
  Future<void> demanderCode({
    required String identifiant,
    required CanalOtp canal,
  }) async {
    _peutEchouer('demanderCode:$identifiant:${canal.code}');
  }

  @override
  Future<void> verifierCode({
    required String identifiant,
    required CanalOtp canal,
    required String code,
  }) async {
    _peutEchouer('verifierCode:$identifiant:$code');
  }

  @override
  Future<Profil?> profilCourant() async {
    appels.add('profilCourant');
    return profil;
  }

  @override
  Future<void> choisirRole(RoleRacine role) async {
    _peutEchouer('choisirRole:${role.code}');
    profil = Profil(
      id: profil?.id ?? 'p1',
      identifiantCanonique: profil?.identifiantCanonique ?? '+224620000000',
      statutCompte: StatutCompte.actif,
      roleRacine: role,
    );
  }

  @override
  Future<void> lierFiche({
    required String matricule,
    required DateTime dateNaissance,
  }) async {
    _peutEchouer('lierFiche:$matricule');
    fiche = true;
  }

  @override
  Future<bool> ficheLiee() async {
    appels.add('ficheLiee');
    return fiche;
  }

  @override
  Future<List<Etablissement>> mesEtablissements() async {
    appels.add('mesEtablissements');
    return etablissements;
  }

  @override
  Future<void> definirEtablissementActif(String etablissementId) async {
    _peutEchouer('definirEtablissementActif:$etablissementId');
  }

  @override
  Future<void> deconnecter() async {
    appels.add('deconnecter');
    profil = null;
  }
}

/// Profil de test — actif, rôle défini par défaut.
Profil profilTest({
  String id = 'p1',
  RoleRacine? role = RoleRacine.parent,
  StatutCompte statut = StatutCompte.actif,
  String? etablissementActifId,
}) {
  return Profil(
    id: id,
    identifiantCanonique: '+224620000000',
    statutCompte: statut,
    roleRacine: role,
    etablissementActifId: etablissementActifId,
  );
}

/// Établissement de test.
Etablissement etablissementTest(String id, String nom) =>
    Etablissement(id: id, nom: nom, slug: nom.toLowerCase(), ville: 'Conakry');
