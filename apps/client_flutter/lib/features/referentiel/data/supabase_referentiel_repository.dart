import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/arborescence_niveau.dart';
import '../domain/arborescence_pays.dart';
import '../domain/cycle_educatif.dart';
import '../domain/examen_national.dart';
import '../domain/filiere_educative.dart';
import '../domain/niveau_educatif.dart';
import '../domain/paquet_referentiel.dart';
import '../domain/pays_pedagogique.dart';
import '../domain/programme_matiere.dart';
import '../domain/programme_officiel.dart';
import '../domain/referentiel_repository.dart';
import '../domain/systeme_educatif.dart';

/// Implémentation Supabase du port [ReferentielRepository] (M4).
///
/// Aucune RPC n'existe pour ce module (contrat M04 §3) : les lectures passent
/// directement par PostgREST, RLS restreignant déjà chaque table aux lignes
/// publiées/déployées — aucun filtre `statut` côté client n'est nécessaire
/// ni suffisant (même convention que [SupabaseAuthRepository.mesEtablissements]).
class SupabaseReferentielRepository implements ReferentielRepository {
  const SupabaseReferentielRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<SystemeEducatif>> systemesEducatifs() {
    return _executer(() async {
      final lignes =
          await _client.from('systemes_educatifs').select().order('nom');
      return lignes
          .map((l) => SystemeEducatif.depuisJson(l))
          .toList(growable: false);
    });
  }

  @override
  Future<List<PaysPedagogique>> paysPedagogiques() {
    return _executer(() async {
      final lignes =
          await _client.from('pays_pedagogiques').select().order('nom');
      return lignes
          .map((l) => PaysPedagogique.depuisJson(l))
          .toList(growable: false);
    });
  }

  @override
  Future<ArborescencePays> arborescencePays(String paysCode) {
    return _executer(() async {
      final cyclesFut = _client
          .from('cycles_educatifs')
          .select()
          .eq('pays_code', paysCode)
          .order('ordre');
      final niveauxFut = _client
          .from('niveaux_educatifs')
          .select()
          .eq('pays_code', paysCode)
          .order('ordre');
      final examensFut = _client
          .from('examens_nationaux')
          .select()
          .eq('pays_code', paysCode)
          .order('nom');

      final resultats =
          await Future.wait([cyclesFut, niveauxFut, examensFut]);

      return ArborescencePays(
        cycles: (resultats[0])
            .map((l) => CycleEducatif.depuisJson(l))
            .toList(growable: false),
        niveaux: (resultats[1])
            .map((l) => NiveauEducatif.depuisJson(l))
            .toList(growable: false),
        examens: (resultats[2])
            .map((l) => ExamenNational.depuisJson(l))
            .toList(growable: false),
      );
    });
  }

  @override
  Future<ArborescenceNiveau> arborescenceNiveau(String niveauId) {
    return _executer(() async {
      final filieresFut = _client
          .from('filieres_educatives')
          .select()
          .eq('niveau_id', niveauId)
          .order('nom');
      final programmesFut = _client
          .from('programmes_officiels')
          .select()
          .eq('niveau_id', niveauId)
          .order('nom');

      final resultats = await Future.wait([filieresFut, programmesFut]);
      final filieres = (resultats[0])
          .map((l) => FiliereEducative.depuisJson(l))
          .toList(growable: false);
      final programmes = (resultats[1])
          .map((l) => ProgrammeOfficiel.depuisJson(l))
          .toList(growable: false);

      if (programmes.isEmpty) {
        return ArborescenceNiveau(
          filieres: filieres,
          programmes: programmes,
          matieres: const [],
        );
      }

      final idsProgrammes = programmes.map((p) => p.id).toList(growable: false);
      final lignesMatieres = await _client
          .from('programmes_matieres')
          .select()
          .inFilter('programme_id', idsProgrammes)
          .order('ordre');

      return ArborescenceNiveau(
        filieres: filieres,
        programmes: programmes,
        matieres: lignesMatieres
            .map((l) => ProgrammeMatiere.depuisJson(l))
            .toList(growable: false),
      );
    });
  }

  @override
  Future<List<PaquetReferentiel>> paquetsDisponibles({
    required String paysCode,
    String? niveauId,
  }) {
    return _executer(() async {
      var requete =
          _client.from('paquets_referentiel').select().eq('pays_code', paysCode);
      if (niveauId != null) {
        requete = requete.eq('niveau_id', niveauId);
      }
      final lignes = await requete.order('version', ascending: false);
      return lignes
          .map((l) => PaquetReferentiel.depuisJson(l))
          .toList(growable: false);
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurReferentiel(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
