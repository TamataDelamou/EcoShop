import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/securite/gardien_actions_sensibles.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/rejeu_telephone.dart';
import '../domain/telephone_profil.dart';
import 'auth_providers.dart';

/// L'étape « Votre numéro » revient après ce délai si on l'a passée.
const delaiRappelTelephone = Duration(days: 30);

const _typeStore = 'telephone_profil';

final _storeTelephoneProvider = Provider<CacheDocumentStore>(
  (ref) => CacheDocumentStore(ref.watch(databaseProvider), 'preferences'),
);

/// Numéro du compte connecté : serveur d'abord, dernier connu sans réseau.
final telephoneProfilProvider = FutureProvider<TelephoneProfil?>((ref) async {
  final profil = await ref.watch(profilProvider.future);
  if (profil == null) return null;
  final store = ref.watch(_storeTelephoneProvider);
  final local = await store.lireDocument(_typeStore, profil.id);
  final gardee = local?['numero'] == null ? null : TelephoneProfil.depuisJson(local!);
  if (gardee != null && gardee.enAttenteEnvoi) return gardee;
  try {
    final serveur = await ref.watch(authRepositoryProvider).monTelephone();
    if (serveur != null) {
      await store.ecrireDocument(_typeStore, profil.id, {...?local, ...serveur.versJson()});
    }
    return serveur ?? gardee;
  } catch (e) {
    if (estErreurReseau(e)) return gardee;
    rethrow;
  }
});

/// Vrai quand l'étape « Votre numéro » doit s'afficher après la connexion :
/// compte sans numéro, sauf l'élève, et pas passée depuis moins de 30 jours.
/// Jamais bloquante sans réseau (on ne sait pas : on ne la montre pas).
final etapeTelephoneProvider =
    AsyncNotifierProvider<EtapeTelephoneNotifier, bool>(EtapeTelephoneNotifier.new);

class EtapeTelephoneNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final profil = await ref.watch(profilProvider.future);
    if (profil == null || profil.roleRacine == null || profil.roleRacine == RoleRacine.eleve) return false;

    final local = await ref.watch(_storeTelephoneProvider).lireDocument(_typeStore, profil.id);
    if (local?['numero'] != null) return false;
    final passeLe = DateTime.tryParse(local?['passe_le'] as String? ?? '');
    if (passeLe != null && DateTime.now().difference(passeLe) < delaiRappelTelephone) return false;

    try {
      return await ref.watch(telephoneProfilProvider.future) == null;
    } catch (_) {
      return false;
    }
  }

  /// Enregistre le numéro (E.164). Sans réseau, il est gardé et part au
  /// retour de la connexion. Les refus du serveur remontent en [ErreurAuth].
  Future<TelephoneProfil> enregistrer(String telephone) async {
    final profil = ref.read(profilProvider).valueOrNull;
    if (profil == null) throw StateError('Aucun compte connecté');
    // Changer un numéro déjà déclaré : action sensible (REG-18).
    final actuel = ref.read(telephoneProfilProvider).valueOrNull;
    if (actuel != null && actuel.numero != telephone) {
      await exigerCodeSecret('Changer de numéro de téléphone');
    }
    final store = ref.read(_storeTelephoneProvider);

    TelephoneProfil resultat;
    try {
      resultat = await ref.read(authRepositoryProvider).declarerTelephone(telephone);
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
      await ref.read(syncRepositoryProvider).enfiler(RejeuTelephone.entree(const Uuid().v4(), telephone));
      resultat = TelephoneProfil(numero: telephone, enAttenteEnvoi: true);
    }
    await store.ecrireDocument(_typeStore, profil.id, resultat.versJson());
    ref.invalidate(telephoneProfilProvider);
    state = const AsyncData(false);
    return resultat;
  }

  /// « Plus tard » : l'étape reviendra dans 30 jours.
  Future<void> passer() async {
    final profil = ref.read(profilProvider).valueOrNull;
    if (profil != null) {
      final store = ref.read(_storeTelephoneProvider);
      final local = await store.lireDocument(_typeStore, profil.id) ?? const {};
      await store.ecrireDocument(_typeStore, profil.id, {...local, 'passe_le': DateTime.now().toIso8601String()});
    }
    state = const AsyncData(false);
  }
}

/// Personnes de l'école dont le numéro attend d'être confirmé.
final telephonesAConfirmerProvider =
    FutureProvider.autoDispose.family<List<TelephoneAConfirmer>, String>((ref, etablissementId) {
  return ref.watch(authRepositoryProvider).telephonesAConfirmer(etablissementId);
});
