import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../domain/profil.dart';
import 'auth_providers.dart';

/// Espaces d'un même compte (REG-27) : un parent invité comme enseignant
/// garde son espace parent et gagne un espace enseignant dans l'école.
///
/// Espaces disponibles : le rôle du compte dans l'établissement actif
/// (enseignant, direction, personnel, vendeur) puis son rôle principal.
final espacesDisponiblesProvider = Provider<List<RoleRacine>>((ref) {
  final profil = ref.watch(profilProvider).valueOrNull;
  if (profil == null) return const [];
  final espaces = <RoleRacine>[];
  final dansEcole = RoleRacine.depuisCode(ref.watch(etablissementActifProvider)?.roleDansEtablissement);
  if (dansEcole != null && dansEcole != RoleRacine.parent && dansEcole != RoleRacine.eleve) espaces.add(dansEcole);
  final racine = profil.roleRacine;
  if (racine != null && !espaces.contains(racine)) espaces.add(racine);
  return espaces;
});

final _storeEspaceProvider = Provider<CacheDocumentStore>(
  (ref) => CacheDocumentStore(ref.watch(databaseProvider), 'preferences_accueil'),
);

/// Espace choisi, gardé sur l'appareil pour ce compte et cette école.
class EspaceChoisiController extends AsyncNotifier<RoleRacine?> {
  static const _type = 'espace_choisi';

  String? _cle() {
    final compte = ref.read(profilProvider).valueOrNull?.id;
    if (compte == null) return null;
    return '$compte.${ref.read(etablissementActifProvider)?.id ?? '-'}';
  }

  @override
  Future<RoleRacine?> build() async {
    ref.watch(profilProvider.select((p) => p.valueOrNull?.id));
    ref.watch(etablissementActifProvider.select((e) => e?.id));
    final cle = _cle();
    if (cle == null) return null;
    try {
      final doc = await ref.read(_storeEspaceProvider).lireDocument(_type, cle);
      return RoleRacine.depuisCode(doc?['role'] as String?);
    } catch (_) {
      return null;
    }
  }

  Future<void> choisir(RoleRacine role) async {
    state = AsyncData(role);
    final cle = _cle();
    if (cle == null) return;
    try {
      await ref.read(_storeEspaceProvider).ecrireDocument(_type, cle, {'role': role.code});
    } catch (_) {}
  }
}

final espaceChoisiProvider = AsyncNotifierProvider<EspaceChoisiController, RoleRacine?>(EspaceChoisiController.new);

/// Rôle utilisé à l'écran : l'espace choisi s'il existe encore, sinon le
/// rôle dans l'école (le travail d'abord), sinon le rôle principal.
final roleUtiliseProvider = Provider<RoleRacine?>((ref) {
  final espaces = ref.watch(espacesDisponiblesProvider);
  if (espaces.isEmpty) return ref.watch(profilProvider).valueOrNull?.roleRacine;
  final choisi = ref.watch(espaceChoisiProvider).valueOrNull;
  return choisi != null && espaces.contains(choisi) ? choisi : espaces.first;
});

/// Profil tel que l'affichent l'accueil et la barre du bas : rôle de
/// l'espace utilisé.
final profilAfficheProvider = Provider<Profil?>((ref) {
  final profil = ref.watch(profilProvider).valueOrNull;
  if (profil == null) return null;
  final role = ref.watch(roleUtiliseProvider);
  return role == profil.roleRacine ? profil : profil.avecRole(role);
});
