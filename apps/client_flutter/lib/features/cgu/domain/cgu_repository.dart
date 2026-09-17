import 'cgu_statut.dart';

/// Erreur métier ou réseau du port [CguRepository].
class ErreurCgu implements Exception {
  const ErreurCgu(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurCgu($code)';
}

/// Port CGU / consentement générique (cahier §34.10).
///
/// [statut] renvoie `null` pour un profil sans rôle choisi ou un rôle
/// plateforme (`admin_gsg`/`admin_contenu`) — hors périmètre du cahier, qui
/// ne cite que Élève/Parent/Enseignant/Direction/Vendeur/Fondateur de
/// réseau. L'acceptation elle-même passe par un simple `insert` RLS-gardé
/// (`profile_id = auth.uid()`), pas une RPC : la seule règle serveur qui
/// compte est que [statut] ne considère « acceptée » que l'acceptation de la
/// version COURANTE — accepter une version obsolète ne débloque rien.
abstract interface class CguRepository {
  Future<CguStatut?> statut();

  Future<void> accepter(String cguVersionId);
}
