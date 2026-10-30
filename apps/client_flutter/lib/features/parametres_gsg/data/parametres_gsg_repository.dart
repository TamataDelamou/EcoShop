import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../domain/parametre_global.dart';

/// Paramètres globaux (REG-36). Lecture possible sans réseau (copie de
/// l'appareil) ; modification en ligne seulement : un réglage de plateforme
/// touche toutes les écoles, on ne le rejoue pas en différé.
class ParametresGsgRepository {
  ParametresGsgRepository(this._client, this._lecture);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;

  Future<List<ParametreGlobal>> lister() => _lecture.lire(
        type: 'liste',
        cle: 'tous',
        source: () => _client.from('parametres_globaux').select().order('cle'),
        decoder: (json) => [
          for (final l in (json as List?) ?? const []) ParametreGlobal.depuisJson((l as Map).cast<String, dynamic>()),
        ],
      );

  Future<List<ChangementParametre>> historique(String cle) async {
    final lignes = await _client
        .from('historique_parametres_globaux')
        .select('ancienne_valeur, nouvelle_valeur, modifie_le')
        .eq('cle', cle)
        .order('modifie_le', ascending: false)
        .limit(20);
    return [for (final l in lignes) ChangementParametre.depuisJson(l)];
  }

  Future<ParametreGlobal> definir(String cle, Map<String, dynamic> valeur) async {
    try {
      final ligne = await _client.rpc<dynamic>('definir_parametre_global', params: {'p_cle': cle, 'p_valeur': valeur});
      return ParametreGlobal.depuisJson((ligne as Map).cast<String, dynamic>());
    } catch (e) {
      throw traduire(e);
    }
  }

  static ErreurParametre traduire(Object e) {
    if (e is ErreurParametre) return e;
    if (estErreurReseau(e)) return const ErreurParametre('HORS_LIGNE');
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurParametre(premier);
      if (e.code == '42501') return const ErreurParametre('PERMISSION_REFUSEE');
    }
    return const ErreurParametre('ERREUR_SERVEUR');
  }
}
