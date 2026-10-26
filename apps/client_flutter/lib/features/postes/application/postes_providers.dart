import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/config/env.dart';
import '../../auth/application/auth_providers.dart';
import '../data/postes_repository.dart';

final postesRepositoryProvider = Provider<PostesRepository>(
  (ref) => SupabasePostesRepository(ref.watch(supabaseClientProvider)),
);

final postesEtablissementProvider = FutureProvider.autoDispose.family<List<Poste>, String>(
  (ref, etab) => ref.watch(postesRepositoryProvider).postes(etab),
);

final modelesPostesProvider = FutureProvider.autoDispose<List<ModelePoste>>(
  (ref) => ref.watch(postesRepositoryProvider).modeles(),
);

final catalogueDroitsProvider = FutureProvider.autoDispose<List<DroitCatalogue>>(
  (ref) => ref.watch(postesRepositoryProvider).catalogue(),
);

final personnelEtablissementProvider = FutureProvider.autoDispose.family<List<MembrePersonnel>, String>(
  (ref, etab) => ref.watch(postesRepositoryProvider).personnel(etab),
);

/// Droits du poste de l'appelant dans l'établissement actif (menus du
/// personnel). Le serveur reste seul juge : un menu affiché à tort ne donne
/// rien, un refus s'affiche.
final mesPermissionsProvider = FutureProvider<Set<String>>((ref) async {
  if (!Env.estConfigure) return const {};
  final etab = ref.watch(etablissementActifProvider)?.id;
  if (etab == null) return const {};
  try {
    return await ref.watch(postesRepositoryProvider).mesPermissions(etab);
  } catch (_) {
    return const {};
  }
});

/// Libellés des domaines du catalogue, en français simple.
String libelleDomaine(String domaine) => switch (domaine) {
  'scolarite' => 'Scolarité',
  'comptabilite' => 'Comptabilité',
  'etablissement' => 'École et personnel',
  'planification' => 'Emploi du temps',
  'rapports' => 'Rapports',
  'rh' => 'Ressources humaines',
  'portail' => 'Portail',
  'bibliotheque' => 'Bibliothèque',
  'transport' => 'Transport',
  'communication' || 'comm' => 'Communication',
  'audit' => 'Journal d’audit',
  _ => domaine,
};
