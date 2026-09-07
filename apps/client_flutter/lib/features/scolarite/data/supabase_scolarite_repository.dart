import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/affectation_enseignant.dart';
import '../domain/annee_scolaire.dart';
import '../domain/classe.dart';
import '../domain/enums_scolarite.dart';
import '../domain/fiche_eleve.dart';
import '../domain/inscription.dart';
import '../domain/periode_scolaire.dart';
import '../domain/relation_parent_eleve.dart';
import '../domain/scolarite_repository.dart';
import '../domain/structure_etablissement.dart';
import '../domain/unite_operationnelle.dart';

/// Implémentation Supabase du port [ScolariteRepository] (M5).
///
/// Aucune RPC pour les lectures : RLS restreint déjà chaque table à ce que
/// l'appelant a le droit de voir (`classe_visible`, `fiche_visible`…) — un
/// filtre client serait redondant et potentiellement trompeur si les deux
/// divergent (même convention que le module référentiel, M4).
class SupabaseScolariteRepository implements ScolariteRepository {
  const SupabaseScolariteRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<StructureEtablissement> structureEtablissement(
    String etablissementId, {
    String? anneeScolaireId,
  }) {
    return _executer(() async {
      final unitesFut = _client
          .from('unites_operationnelles')
          .select()
          .eq('etablissement_id', etablissementId)
          .isFilter('deleted_at', null)
          .order('nom');
      final anneesFut = _client
          .from('annees_scolaires')
          .select()
          .eq('etablissement_id', etablissementId)
          .order('date_debut', ascending: false);

      final resultats = await Future.wait([unitesFut, anneesFut]);
      final unites = resultats[0]
          .map((l) => UniteOperationnelle.depuisJson(l))
          .toList(growable: false);
      final annees = resultats[1]
          .map((l) => AnneeScolaire.depuisJson(l))
          .toList(growable: false);

      final anneeCible = anneeScolaireId ??
          annees.where((a) => a.courante).map((a) => a.id).firstOrNull ??
          (annees.isEmpty ? null : annees.first.id);

      if (anneeCible == null) {
        return StructureEtablissement(
          unites: unites,
          anneesScolaires: annees,
          classes: const [],
          periodes: const [],
        );
      }

      final classesFut = _client
          .from('classes')
          .select()
          .eq('annee_scolaire_id', anneeCible)
          .isFilter('deleted_at', null)
          .order('nom');
      final periodesFut = _client
          .from('periodes_scolaires')
          .select()
          .eq('annee_scolaire_id', anneeCible)
          .isFilter('deleted_at', null)
          .order('ordre');

      final resultatsAnnee = await Future.wait([classesFut, periodesFut]);

      return StructureEtablissement(
        unites: unites,
        anneesScolaires: annees,
        classes: resultatsAnnee[0].map((l) => Classe.depuisJson(l)).toList(growable: false),
        periodes: resultatsAnnee[1]
            .map((l) => PeriodeScolaire.depuisJson(l))
            .toList(growable: false),
      );
    });
  }

  @override
  Future<List<Inscription>> inscriptionsDeClasse(String classeId) {
    return _executer(() async {
      final lignes = await _client
          .from('inscriptions')
          .select('*, fiches_eleves(*)')
          .eq('classe_id', classeId)
          .isFilter('deleted_at', null);
      final inscriptions =
          lignes.map((l) => Inscription.depuisJson(l)).toList();
      inscriptions.sort((a, b) {
        final nomA = a.fiche?.nomComplet ?? '';
        final nomB = b.fiche?.nomComplet ?? '';
        return nomA.compareTo(nomB);
      });
      return inscriptions;
    });
  }

  @override
  Future<List<Inscription>> inscriptionsDeFiche(String ficheEleveId) {
    return _executer(() async {
      final lignes = await _client
          .from('inscriptions')
          .select('*, classes(*)')
          .eq('fiche_eleve_id', ficheEleveId)
          .isFilter('deleted_at', null)
          .order('date_inscription', ascending: false);
      return lignes.map((l) => Inscription.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<FicheEleve?> maFiche() {
    return _executer(() async {
      final utilisateur = _client.auth.currentUser;
      if (utilisateur == null) return null;

      final ligne = await _client
          .from('fiches_eleves')
          .select()
          .eq('profile_id', utilisateur.id)
          .maybeSingle();
      return ligne == null ? null : FicheEleve.depuisJson(ligne);
    });
  }

  @override
  Future<List<AffectationEnseignant>> affectationsDeClasse(String classeId) {
    return _executer(() async {
      final lignes = await _client
          .from('affectations_enseignants')
          .select('*, profiles(prenom, nom), programmes_matieres(nom)')
          .eq('classe_id', classeId)
          .isFilter('deleted_at', null);
      return lignes
          .map((l) => AffectationEnseignant.depuisJson(l))
          .toList(growable: false);
    });
  }

  @override
  Future<List<AffectationEnseignant>> mesAffectations() {
    return _executer(() async {
      final utilisateur = _client.auth.currentUser;
      if (utilisateur == null) return const [];

      final lignes = await _client
          .from('affectations_enseignants')
          .select('*, profiles(prenom, nom), programmes_matieres(nom), classes(*)')
          .eq('enseignant_profile_id', utilisateur.id)
          .isFilter('deleted_at', null);
      return lignes
          .map((l) => AffectationEnseignant.depuisJson(l))
          .toList(growable: false);
    });
  }

  @override
  Future<List<RelationParentEleve>> mesEnfants() {
    return _executer(() async {
      final utilisateur = _client.auth.currentUser;
      if (utilisateur == null) return const [];

      final lignes = await _client
          .from('relations_parent_eleve')
          .select('*, fiches_eleves(*)')
          .eq('parent_profile_id', utilisateur.id)
          .isFilter('deleted_at', null);
      return lignes
          .map((l) => RelationParentEleve.depuisJson(l))
          .toList(growable: false);
    });
  }

  @override
  Future<FicheEleve?> ficheEleve(String ficheId) {
    return _executer(() async {
      final ligne = await _client
          .from('fiches_eleves')
          .select()
          .eq('id', ficheId)
          .maybeSingle();
      return ligne == null ? null : FicheEleve.depuisJson(ligne);
    });
  }

  @override
  Future<String> lierEnfant({
    required String matricule,
    required DateTime dateNaissance,
    TypeRelationParentale type = TypeRelationParentale.parent,
  }) {
    return _executer(() async {
      final id = await _client.rpc<String>(
        'lier_parent_a_fiche',
        params: {
          'p_matricule': matricule.trim(),
          'p_date_naissance': _formatDateIso(dateNaissance),
          'p_type': type.code,
        },
      );
      return id;
    });
  }

  static String _formatDateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurScolarite(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
