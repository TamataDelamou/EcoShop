import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/config/env.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/session_locale.dart';
import '../../auth/domain/profil.dart';
import '../../postes/application/postes_providers.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../transport/application/transport_providers.dart';
import '../domain/fonction.dart';

/// Cours du jour (enseignant : les siens ; élève et parent : la classe).
class CoursDuJour {
  const CoursDuJour({required this.debut, required this.fin, this.matiere, this.classe, this.salle, this.enseignant});

  final String debut;
  final String fin;
  final String? matiere;
  final String? classe;
  final String? salle;
  final String? enseignant;

  factory CoursDuJour.depuisJson(Map<String, dynamic> j) => CoursDuJour(
    debut: (j['heure_debut'] as String).substring(0, 5),
    fin: (j['heure_fin'] as String).substring(0, 5),
    matiere: j['matiere'] as String?,
    classe: j['classe'] as String?,
    salle: j['salle'] as String?,
    enseignant: j['enseignant'] as String?,
  );

  Map<String, dynamic> versJson() =>
      {'heure_debut': debut, 'heure_fin': fin, 'matiere': matiere, 'classe': classe, 'salle': salle, 'enseignant': enseignant};

  /// « 8 h – 10 h ».
  String get creneau => '${_h(debut)} – ${_h(fin)}';
  static String _h(String hhmm) {
    final h = int.parse(hhmm.substring(0, 2));
    final m = hhmm.substring(3, 5);
    return m == '00' ? '$h h' : '$h h $m';
  }

  bool enCours(DateTime maintenant) {
    final t = '${maintenant.hour.toString().padLeft(2, '0')}:${maintenant.minute.toString().padLeft(2, '0')}';
    return debut.compareTo(t) <= 0 && fin.compareTo(t) > 0;
  }

  bool aVenir(DateTime maintenant) {
    final t = '${maintenant.hour.toString().padLeft(2, '0')}:${maintenant.minute.toString().padLeft(2, '0')}';
    return debut.compareTo(t) > 0;
  }
}

/// Accès au serveur pour l'accueil. Surchargé par un double en test.
abstract interface class AccueilRepository {
  Future<Map<String, int>> resume(String etablissementId, {String? ficheId});
  Future<List<CoursDuJour>> aujourdhui(String etablissementId, {String? ficheId});
}

class SupabaseAccueilRepository implements AccueilRepository {
  const SupabaseAccueilRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, int>> resume(String etablissementId, {String? ficheId}) async {
    final r = await _client.rpc<dynamic>('accueil_resume', params: {'p_etablissement': etablissementId, 'p_fiche': ficheId});
    return {for (final e in (r as Map).entries) e.key as String: (e.value as num).toInt()};
  }

  @override
  Future<List<CoursDuJour>> aujourdhui(String etablissementId, {String? ficheId}) async {
    final r = await _client.rpc<dynamic>('mon_aujourdhui', params: {'p_etablissement': etablissementId, 'p_fiche': ficheId});
    return [for (final l in (r as List)) CoursDuJour.depuisJson((l as Map).cast<String, dynamic>())];
  }
}

final accueilRepositoryProvider = Provider<AccueilRepository>(
  (ref) => SupabaseAccueilRepository(ref.watch(supabaseClientProvider)),
);

/// Accueil branché sur le serveur (faux sans configuration et en test).
final accueilEnLigneProvider = Provider<bool>((ref) => Env.estConfigure);

/// Ce que l'accueil sait du compte (jamais bloquant : chaque morceau
/// manquant masque seulement les pastilles qui en dépendent).
final contexteAccueilProvider = Provider<ContexteAccueil?>((ref) {
  final profil = ref.watch(profilProvider).valueOrNull;
  if (profil == null) return null;
  final enLigne = ref.watch(accueilEnLigneProvider);
  final role = profil.roleRacine;
  T? lire<T>(T? Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  return ContexteAccueil(
    profil: profil,
    etablissement: ref.watch(etablissementActifProvider),
    droits: role?.code == 'personnel' ? ref.watch(mesPermissionsProvider).valueOrNull ?? const {} : const {},
    enfant: role?.code == 'parent' ? lire(() => ref.watch(enfantActifProvider)) : null,
    maFiche: role?.code == 'eleve' ? lire(() => ref.watch(maFicheProvider).valueOrNull) : null,
    anneeId: enLigne ? lire(() => ref.watch(structureEtablissementProvider(null)).valueOrNull?.anneeCourante?.id) : null,
    chauffeur: enLigne && role?.code != 'eleve' && role?.code != 'admin_gsg'
        ? (lire(() => ref.watch(mesCircuitsChauffeurProvider).valueOrNull) ?? const []).isNotEmpty
        : false,
  );
});

String _cle(Profil p, String etab, String? fiche) => '${p.id}.$etab.${fiche ?? '-'}';

/// Compteurs « À faire » et badges : dernière valeur connue d'abord (hors
/// connexion), serveur relu en arrière-plan. Jamais d'erreur : vide.
final resumeAccueilProvider = FutureProvider<Map<String, int>>((ref) async {
  final c = ref.watch(contexteAccueilProvider);
  if (c == null || c.etablissement == null || !ref.watch(accueilEnLigneProvider)) return const {};
  final fiche = c.parent ? c.enfant?.id : null;
  try {
    return await lireAvecCopieLocale<Map<String, int>>(
      ref,
      type: 'accueil_resume',
      compteId: _cle(c.profil, c.etablissement!.id, fiche),
      serveur: () => ref.read(accueilRepositoryProvider).resume(c.etablissement!.id, ficheId: fiche),
      versJson: (m) => m,
      depuisJson: (j) => {for (final e in ((j as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt()},
    );
  } catch (_) {
    return const {};
  }
});

final aujourdhuiProvider = FutureProvider<List<CoursDuJour>>((ref) async {
  final c = ref.watch(contexteAccueilProvider);
  if (c == null || c.etablissement == null || !ref.watch(accueilEnLigneProvider)) return const [];
  if (!(c.enseignant || c.eleve || c.parent)) return const [];
  final fiche = c.parent ? c.enfant?.id : null;
  if (c.parent && fiche == null) return const [];
  try {
    return await lireAvecCopieLocale<List<CoursDuJour>>(
      ref,
      type: 'accueil_aujourdhui',
      compteId: '${_cle(c.profil, c.etablissement!.id, fiche)}.${DateTime.now().weekday}',
      serveur: () => ref.read(accueilRepositoryProvider).aujourdhui(c.etablissement!.id, ficheId: fiche),
      versJson: (l) => [for (final x in l) x.versJson()],
      depuisJson: (j) => [for (final x in (j as List? ?? const [])) CoursDuJour.depuisJson((x as Map).cast<String, dynamic>())],
    );
  } catch (_) {
    return const [];
  }
});

/// Raccourcis : gardés sur l'appareil, hors de la copie de session (qui est
/// effacée à la déconnexion).
final storeRaccourcisProvider = Provider<CacheDocumentStore>(
  (ref) => CacheDocumentStore(ref.watch(databaseProvider), 'preferences_accueil'),
);

/// Mes raccourcis (direction, personnel) : quatre pastilles épinglées,
/// gardées sur l'appareil.
class RaccourcisController extends AsyncNotifier<List<String>> {
  static const parDefaut = ['encaissements', 'annonces', 'relances', 'rapports'];
  static const _type = 'raccourcis_accueil';

  String? get _compte => ref.read(profilProvider).valueOrNull?.id;

  @override
  Future<List<String>> build() async {
    final compte = ref.watch(profilProvider.select((p) => p.valueOrNull?.id));
    if (compte == null) return parDefaut;
    try {
      final doc = await ref.read(storeRaccourcisProvider).lireDocument(_type, compte);
      final liste = (doc?['ids'] as List?)?.cast<String>();
      return liste ?? parDefaut;
    } catch (_) {
      return parDefaut;
    }
  }

  Future<void> remplacer(List<String> ids) async {
    final liste = ids.take(4).toList();
    state = AsyncData(liste);
    final compte = _compte;
    if (compte == null) return;
    try {
      await ref.read(storeRaccourcisProvider).ecrireDocument(_type, compte, {'ids': liste});
    } catch (_) {}
  }
}

final raccourcisProvider = AsyncNotifierProvider<RaccourcisController, List<String>>(RaccourcisController.new);

