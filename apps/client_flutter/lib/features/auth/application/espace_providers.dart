import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/config/env.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../domain/profil.dart';
import 'auth_providers.dart';

/// Un espace = un rôle **dans une école** (REG-32).
///
/// Un même compte peut être enseignant dans l'école A et parent dans
/// l'école B : l'espace « parent » n'existe que dans les écoles où le compte
/// a un enfant lié et confirmé, l'espace « enseignant » que dans celles où il
/// est rattaché. Comme Pronote ou VSware (un espace par établissement), mais
/// avec une seule connexion.
class EspaceEcole {
  const EspaceEcole({required this.role, this.etablissementId, this.etablissementNom, this.enfants = 0});

  final RoleRacine role;

  /// Null : espace sans école (compte qui n'a encore ni rattachement ni
  /// enfant lié, administrateur GSG…).
  final String? etablissementId;
  final String? etablissementNom;

  /// Espace parent : nombre d'enfants liés dans cette école.
  final int enfants;

  String get cle => '${role.code}@${etablissementId ?? '-'}';

  /// « Enseignant · École A ».
  String get libelle => etablissementNom == null ? role.libelle : '${role.libelle} · $etablissementNom';

  static EspaceEcole? depuisJson(Map<String, dynamic> json) {
    final role = RoleRacine.depuisCode(json['role'] as String?);
    if (role == null) return null;
    return EspaceEcole(
      role: role,
      etablissementId: json['etablissement_id'] as String?,
      etablissementNom: json['etablissement_nom'] as String?,
      enfants: (json['enfants'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) => other is EspaceEcole && other.cle == cle;

  @override
  int get hashCode => cle.hashCode;
}

/// Copie des espaces pour le hors connexion, purgée à la déconnexion.
final lectureEspacesProvider = Provider<LectureHorsLigne>((ref) => LectureHorsLigne(
      CacheDocumentStore(ref.watch(databaseProvider), 'espaces_hl'),
      ref.watch(fraicheurHorsLigneProvider),
    ));

/// Espaces calculés sur le téléphone, à partir des rattachements et des
/// enfants déjà chargés : repli sans serveur (tests, mode diagnostic) ou si
/// la fonction `mes_espaces` ne répond pas.
List<EspaceEcole> espacesDepuis(List<Etablissement> ecoles, List<({String etablissementId, bool actif})> enfants) {
  final noms = {for (final e in ecoles) e.id: e.nom};
  final espaces = <EspaceEcole>[];
  for (final e in ecoles) {
    final role = RoleRacine.depuisCode(e.roleDansEtablissement);
    if (role != null && role != RoleRacine.parent) {
      espaces.add(EspaceEcole(role: role, etablissementId: e.id, etablissementNom: e.nom));
    }
  }
  final parEcole = <String, int>{};
  for (final r in enfants.where((r) => r.actif)) {
    parEcole[r.etablissementId] = (parEcole[r.etablissementId] ?? 0) + 1;
  }
  for (final entree in parEcole.entries) {
    espaces.add(EspaceEcole(
      role: RoleRacine.parent,
      etablissementId: entree.key,
      etablissementNom: noms[entree.key],
      enfants: entree.value,
    ));
  }
  return espaces;
}

/// Espaces du compte (fonction serveur `mes_espaces`, copie gardée pour le
/// hors connexion ; à défaut, calcul sur le téléphone).
final mesEspacesProvider = FutureProvider<List<EspaceEcole>>((ref) async {
  final profil = await ref.watch(profilProvider.future);
  if (profil == null) return const [];
  Future<List<EspaceEcole>> local() async {
    final ecoles = await ref.watch(mesEtablissementsProvider.future).catchError((_) => const <Etablissement>[]);
    final enfants = await ref.watch(mesEnfantsProvider.future).catchError((_) => const <Never>[]);
    return espacesDepuis(ecoles, [for (final r in enfants) (etablissementId: r.etablissementId, actif: r.estActive)]);
  }

  if (!Env.estConfigure) return local();
  // Recalculés quand les écoles ou les enfants changent (liaison, invitation).
  ref.watch(mesEtablissementsProvider);
  ref.watch(mesEnfantsProvider);
  try {
    return await ref.watch(lectureEspacesProvider).lire(
          type: 'mes_espaces',
          cle: profil.id,
          source: () => ref.read(supabaseClientProvider).rpc('mes_espaces'),
          decoder: (json) => [
            for (final l in (json as List? ?? const []))
              ?EspaceEcole.depuisJson(Map<String, dynamic>.from(l as Map)),
          ],
        );
  } catch (_) {
    return local();
  }
});

/// Espaces proposés dans l'en-tête. Toujours au moins un : le rôle principal
/// du compte, tant qu'il n'a ni rattachement ni enfant lié.
final espacesDisponiblesProvider = Provider<List<EspaceEcole>>((ref) {
  final profil = ref.watch(profilProvider).valueOrNull;
  if (profil == null) return const [];
  final espaces = ref.watch(mesEspacesProvider).valueOrNull ?? const <EspaceEcole>[];
  if (espaces.isNotEmpty) return espaces;
  final racine = profil.roleRacine;
  if (racine == null) return const [];
  final actif = ref.watch(etablissementActifProvider);
  return [EspaceEcole(role: racine, etablissementId: actif?.id, etablissementNom: actif?.nom)];
});

final _storeEspaceProvider = Provider<CacheDocumentStore>(
  (ref) => CacheDocumentStore(ref.watch(databaseProvider), 'preferences_accueil'),
);

/// Espace choisi (clé « rôle@école »), gardé sur l'appareil pour ce compte.
class EspaceChoisiController extends AsyncNotifier<String?> {
  static const _type = 'espace_choisi_v2';

  String? _compte() => ref.read(profilProvider).valueOrNull?.id;

  @override
  Future<String?> build() async {
    ref.watch(profilProvider.select((p) => p.valueOrNull?.id));
    final compte = _compte();
    if (compte == null) return null;
    try {
      final doc = await ref.read(_storeEspaceProvider).lireDocument(_type, compte);
      return doc?['cle'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Choisit un espace. Un espace de personnel ou d'élève d'une autre école
  /// en fait l'école active (le serveur le vérifie) ; un espace parent ne
  /// change pas l'école active : le parent n'est pas membre de l'école.
  Future<void> choisir(EspaceEcole espace) async {
    state = AsyncData(espace.cle);
    final compte = _compte();
    if (compte != null) {
      try {
        await ref.read(_storeEspaceProvider).ecrireDocument(_type, compte, {'cle': espace.cle});
      } catch (_) {}
    }
    final ecole = espace.etablissementId;
    if (espace.role == RoleRacine.parent || ecole == null) return;
    if (ref.read(etablissementActifProvider)?.id == ecole) return;
    await ref.read(authRepositoryProvider).definirEtablissementActif(ecole);
    ref.invalidate(profilProvider);
  }
}

final espaceChoisiProvider = AsyncNotifierProvider<EspaceChoisiController, String?>(EspaceChoisiController.new);

/// Espace utilisé à l'écran : celui choisi s'il existe encore ; sinon le
/// travail dans l'école active d'abord ; sinon le premier.
final espaceUtiliseProvider = Provider<EspaceEcole?>((ref) {
  final espaces = ref.watch(espacesDisponiblesProvider);
  if (espaces.isEmpty) return null;
  final choisi = ref.watch(espaceChoisiProvider).valueOrNull;
  for (final e in espaces) {
    if (e.cle == choisi) return e;
  }
  final actif = ref.watch(etablissementActifProvider)?.id;
  for (final e in espaces) {
    if (e.etablissementId == actif && e.role != RoleRacine.parent) return e;
  }
  return espaces.first;
});

/// Rôle utilisé à l'écran.
final roleUtiliseProvider = Provider<RoleRacine?>((ref) {
  return ref.watch(espaceUtiliseProvider)?.role ?? ref.watch(profilProvider).valueOrNull?.roleRacine;
});

/// École de l'espace parent utilisé : seuls ses enfants dans cette école
/// sont proposés. Null hors espace parent, ou sans école connue.
final ecoleEspaceParentProvider = Provider<String?>((ref) {
  final espace = ref.watch(espaceUtiliseProvider);
  return espace?.role == RoleRacine.parent ? espace?.etablissementId : null;
});

/// Profil tel que l'affichent l'accueil et la barre du bas : rôle de
/// l'espace utilisé.
final profilAfficheProvider = Provider<Profil?>((ref) {
  final profil = ref.watch(profilProvider).valueOrNull;
  if (profil == null) return null;
  final role = ref.watch(roleUtiliseProvider);
  return role == profil.roleRacine ? profil : profil.avecRole(role);
});
