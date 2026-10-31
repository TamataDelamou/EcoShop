import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../../planification/domain/emploi_du_temps.dart';
import '../../planification/domain/salle.dart';
import '../domain/configuration.dart';

/// Erreur lisible d'une action de configuration.
class ErreurConfiguration implements Exception {
  const ErreurConfiguration(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Mise en route d'un établissement (REG-23) et emploi du temps (REG-24).
///
/// Lectures : réseau d'abord, dernière copie de l'appareil sans réseau
/// ([LectureHorsLigne]). Écritures : actions de bureau de la Direction,
/// faites en ligne (comme les salles) ; un message clair sans réseau. Le
/// calcul de l'emploi du temps, lui, se fait entièrement sur l'appareil.
class ConfigurationRepository {
  ConfigurationRepository(this._client, this._lecture);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;

  Future<T> _ecrire<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurConfiguration(_message(e.message, e.code));
    } on StorageException catch (e) {
      throw ErreurConfiguration(e.message);
    } catch (e) {
      if (estErreurReseau(e)) {
        throw const ErreurConfiguration('Pas de connexion : cette action demande le réseau. Réessayez une fois en ligne.');
      }
      rethrow;
    }
  }

  static String _message(String brut, String? code) {
    final premier = brut.trim().split(RegExp(r'\s+')).first;
    return switch (premier) {
      'ACCES_REFUSE' || 'PERMISSION_REFUSEE' => 'Action réservée à la Direction de l’établissement.',
      'ANNEE_EXISTE_DEJA' => 'Une année porte déjà ce nom.',
      'DATES_INVALIDES' => 'La date de fin doit suivre la date de début.',
      'ANNEE_TROP_LONGUE' => 'Une année scolaire dure au plus 13 mois.',
      'LIBELLE_REQUIS' => 'Donnez un nom à l’année (ex. 2026-2027).',
      'CRENEAU_DEJA_OCCUPE' => 'Un créneau est déjà occupé par une séance verrouillée. Relancez le calcul.',
      'GROUPE_CLASSE_HORS_ANNEE' => 'Ce groupe doit appartenir à une classe de la même année.',
      'NOM_REQUIS' => 'Donnez un nom à la matière.',
      'COEFFICIENT_INVALIDE' => 'Le coefficient doit être supérieur à 0 (0,5 ; 1 ; 2…).',
      'NIVEAU_INCONNU' => 'Niveau inconnu : rattachez d’abord la classe à son niveau.',
      _ when code == '23505' => 'Cet élément existe déjà (même nom ou même code).',
      _ when code == '42501' => 'Action réservée à la Direction de l’établissement.',
      _ => 'Enregistrement impossible : $brut',
    };
  }

  // ----------------------------------------------------------- état

  Future<EtatConfiguration> etat(String etablissementId) => _lecture.lire(
        type: 'etat_configuration',
        cle: etablissementId,
        source: () => _client.rpc<dynamic>('etat_configuration_etablissement', params: {'p_etablissement': etablissementId}),
        decoder: (j) => EtatConfiguration.depuisJson((j as Map).cast<String, dynamic>()),
      );

  // ----------------------------------------------------------- années

  Future<String> creerAnnee({
    required String etablissementId,
    required String libelle,
    required DateTime debut,
    required DateTime fin,
    required String decoupage,
    required bool courante,
    String? reprendreDe,
  }) =>
      _ecrire(() async {
        final id = await _client.rpc<dynamic>('creer_annee_scolaire', params: {
          'p_etablissement': etablissementId,
          'p_libelle': libelle.trim(),
          'p_debut': _date(debut),
          'p_fin': _date(fin),
          'p_decoupage': decoupage,
          'p_courante': courante,
          'p_reprendre_de': reprendreDe,
        });
        return id as String;
      });

  Future<void> definirAnneeCourante(String anneeId) =>
      _ecrire(() => _client.rpc<dynamic>('definir_annee_courante', params: {'p_annee': anneeId}));

  Future<void> modifierPeriode({required String id, required String libelle, required DateTime debut, required DateTime fin}) =>
      _ecrire(() => _client
          .from('periodes_scolaires')
          .update({'libelle': libelle.trim(), 'date_debut': _date(debut), 'date_fin': _date(fin)}).eq('id', id));

  // ----------------------------------------------------------- classes

  Future<void> enregistrerClasse({
    String? id,
    required String etablissementId,
    required String anneeId,
    required String code,
    required String nom,
    String? niveauId,
    String? filiereId,
    int? capacite,
    String? enseignantPrincipalId,
  }) =>
      _ecrire(() async {
        final ligne = {
          'etablissement_id': etablissementId,
          'annee_scolaire_id': anneeId,
          'code': code.trim(),
          'nom': nom.trim(),
          'niveau_id': niveauId,
          'filiere_id': filiereId,
          'capacite': capacite,
          'enseignant_principal_id': enseignantPrincipalId,
        };
        if (id == null) {
          await _client.from('classes').insert(ligne);
        } else {
          await _client.from('classes').update(ligne).eq('id', id);
        }
      });

  /// Plusieurs classes d'un même niveau d'un coup (« 6e A, 6e B, 6e C »).
  Future<void> creerClasses(List<Map<String, dynamic>> lignes) =>
      _ecrire(() => _client.from('classes').insert(lignes));

  /// Retrait logique : jamais de suppression d'une donnée pédagogique.
  Future<void> retirerClasse(String id) => _ecrire(() => _client
      .from('classes')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String(), 'actif': false}).eq('id', id));

  // ----------------------------------------------------------- groupes

  Future<List<GroupePedagogique>> groupes(String anneeId) => _lecture.lire(
        type: 'groupes',
        cle: anneeId,
        source: () async {
          final lignes = await _client
              .from('groupes_pedagogiques')
              .select('*, groupes_membres(count)')
              .eq('annee_scolaire_id', anneeId)
              .isFilter('deleted_at', null)
              .order('nom');
          return [for (final l in lignes) GroupePedagogique.depuisJson(l).versJson()];
        },
        decoder: (j) => [
          for (final x in (j as List)) GroupePedagogique.depuisJson((x as Map).cast<String, dynamic>()),
        ],
      );

  Future<void> enregistrerGroupe(GroupePedagogique g) =>
      _ecrire(() => _client.from('groupes_pedagogiques').upsert(g.versJsonEcriture(), onConflict: 'id'));

  Future<void> retirerGroupe(String id) => _ecrire(() => _client
      .from('groupes_pedagogiques')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id));

  Future<Set<String>> membresGroupe(String groupeId) => _lecture.lire(
        type: 'membres_groupe',
        cle: groupeId,
        source: () async {
          final lignes = await _client.from('groupes_membres').select('fiche_eleve_id').eq('groupe_id', groupeId);
          return [for (final l in lignes) l['fiche_eleve_id'] as String];
        },
        decoder: (j) => {for (final x in (j as List)) x as String},
      );

  Future<void> definirMembresGroupe({
    required String groupeId,
    required String etablissementId,
    required Set<String> fiches,
  }) =>
      _ecrire(() async {
        await _client.from('groupes_membres').delete().eq('groupe_id', groupeId);
        if (fiches.isEmpty) return;
        await _client.from('groupes_membres').insert([
          for (final f in fiches) {'groupe_id': groupeId, 'fiche_eleve_id': f, 'etablissement_id': etablissementId},
        ]);
      });

  // ----------------------------------------------------------- personnel

  // Patience longue : la copie de l'appareil ne précède plus la réponse du
  // serveur après 3 s. Un enseignant qui venait d'accepter son invitation
  // manquait dans « Cours et enseignants » sur un réseau mobile lent
  // (retour du porteur de projet, 2026-10-31).
  Future<List<MembrePersonnel>> personnel(String etablissementId) => _lecture.lire(
        type: 'personnel',
        cle: etablissementId,
        patience: const Duration(seconds: 15),
        source: () async {
          final lignes = await _client.rpc<dynamic>('membres_personnel', params: {'p_etablissement': etablissementId});
          return [for (final l in lignes as List) MembrePersonnel.depuisJson((l as Map).cast<String, dynamic>()).versJson()];
        },
        decoder: (j) => [
          for (final x in (j as List)) MembrePersonnel.depuisJson((x as Map).cast<String, dynamic>()),
        ],
      );

  // ----------------------------------------------------------- programmes de l'école (REG-33)

  /// Programmes de l'école, avec leurs matières (RLS : membres de l'école).
  Future<List<ProgrammeEcole>> programmesEcole(String etablissementId) => _lecture.lire(
        type: 'programmes_ecole',
        cle: etablissementId,
        source: () async {
          final lignes = await _client
              .from('programmes_officiels')
              .select('*, programmes_matieres(*)')
              .eq('etablissement_id', etablissementId)
              .neq('statut', 'archive');
          return [for (final l in lignes) ProgrammeEcole.depuisJson(l).versJson()];
        },
        decoder: (j) => [
          for (final x in (j as List)) ProgrammeEcole.depuisJson((x as Map).cast<String, dynamic>()),
        ],
      );

  /// Programme de l'école pour un niveau et une série : créé à la demande,
  /// copie du programme national s'il existe.
  Future<String> adopterProgramme({required String etablissementId, required String niveauId, String? filiereId}) =>
      _ecrire(() async => (await _client.rpc('adopter_programme_ecole', params: {
            'p_etablissement': etablissementId,
            'p_niveau': niveauId,
            'p_filiere': filiereId,
          })) as String);

  Future<void> enregistrerMatiere({
    required String programmeId,
    required String nom,
    double? coefficient,
    int? volumeAnnuel,
    String nature = 'tronc_commun',
    String? matiereId,
  }) =>
      _ecrire(() => _client.rpc('enregistrer_matiere_ecole', params: {
            'p_programme': programmeId,
            'p_nom': nom,
            'p_coefficient': coefficient,
            'p_volume_annuel': volumeAnnuel,
            'p_nature': nature,
            'p_matiere': matiereId,
          }));

  Future<void> retirerMatiere(String matiereId) =>
      _ecrire(() => _client.rpc('retirer_matiere_ecole', params: {'p_matiere': matiereId}));

  // ----------------------------------------------------------- affectations

  Future<List<AffectationCours>> affectations(String anneeId) => _lecture.lire(
        type: 'affectations',
        cle: anneeId,
        source: () async {
          final lignes = await _client
              .from('affectations_enseignants')
              .select('*, profiles(prenom, nom), programmes_matieres(nom, coefficient)')
              .eq('annee_scolaire_id', anneeId)
              .isFilter('deleted_at', null);
          return [for (final l in lignes) AffectationCours.depuisJson(l).versJson()];
        },
        decoder: (j) => [
          for (final x in (j as List)) AffectationCours.depuisJson((x as Map).cast<String, dynamic>()),
        ],
      );

  Future<void> enregistrerAffectation(AffectationCours a) =>
      _ecrire(() => _client.from('affectations_enseignants').upsert(a.versJsonEcriture(), onConflict: 'id'));

  Future<void> retirerAffectation(String id) => _ecrire(() => _client
      .from('affectations_enseignants')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id));

  // ----------------------------------------------------------- salles

  Future<void> enregistrerSalle({String? id, required String etablissementId, required String code, String nom = '', int? capacite}) =>
      _ecrire(() async {
        final ligne = {'etablissement_id': etablissementId, 'code': code.trim(), 'nom': nom.trim(), 'capacite': capacite};
        if (id == null) {
          await _client.from('salles').insert(ligne);
        } else {
          await _client.from('salles').update(ligne).eq('id', id);
        }
      });

  Future<void> retirerSalle(Salle salle) => _ecrire(() => _client
      .from('salles')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String(), 'actif': false}).eq('id', salle.id));

  // ----------------------------------------------------------- grille

  Future<GrilleHoraire?> grille(String anneeId) => _lecture.lire(
        type: 'grille_horaire',
        cle: anneeId,
        source: () => _client.from('grilles_horaires').select().eq('annee_scolaire_id', anneeId).maybeSingle(),
        decoder: (j) => j == null ? null : GrilleHoraire.depuisJson((j as Map).cast<String, dynamic>()),
      );

  Future<void> enregistrerGrille(GrilleHoraire g) => _ecrire(() {
        final ligne = g.versJson()..remove('id');
        return _client.from('grilles_horaires').upsert(ligne, onConflict: 'annee_scolaire_id');
      });

  // ----------------------------------------------------------- indisponibilités

  Future<List<Indisponibilite>> indisponibilites(String anneeId) => _lecture.lire(
        type: 'indisponibilites',
        cle: anneeId,
        source: () async {
          final lignes = await _client
              .from('contraintes_emploi')
              .select()
              .eq('annee_scolaire_id', anneeId)
              .isFilter('deleted_at', null)
              .neq('type', 'preference');
          return [for (final l in lignes) Indisponibilite.depuisJson(l).versJson()];
        },
        decoder: (j) => [
          for (final x in (j as List)) Indisponibilite.depuisJson((x as Map).cast<String, dynamic>()),
        ],
      );

  Future<void> enregistrerIndisponibilite(Indisponibilite i) =>
      _ecrire(() => _client.from('contraintes_emploi').upsert(i.versJson(), onConflict: 'id'));

  Future<void> retirerIndisponibilite(String id) => _ecrire(() => _client
      .from('contraintes_emploi')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id));

  // ----------------------------------------------------------- séances

  /// Toutes les séances de l'année (vue de la Direction).
  Future<List<EmploiDuTemps>> seancesAnnee(String anneeId) => _lecture.lire(
        type: 'seances_annee',
        cle: anneeId,
        source: () async {
          final lignes = await _client
              .from('emplois_du_temps')
              .select('*, profiles(prenom, nom), programmes_matieres(nom), salles(code), classes(nom)')
              .eq('annee_scolaire_id', anneeId)
              .isFilter('deleted_at', null)
              .order('jour_semaine')
              .order('heure_debut');
          return [for (final l in lignes) EmploiDuTemps.depuisJson(l).versJsonCache()];
        },
        decoder: (j) => [
          for (final x in (j as List)) EmploiDuTemps.depuisJsonCache((x as Map).cast<String, dynamic>()),
        ],
      );

  Future<int> enregistrerEmploiGenere({
    required String etablissementId,
    required String anneeId,
    required List<Map<String, dynamic>> seances,
    String? deviceId,
  }) =>
      _ecrire(() async {
        final n = await _client.rpc<dynamic>('enregistrer_emploi_genere', params: {
          'p_etablissement': etablissementId,
          'p_annee': anneeId,
          'p_seances': seances,
          'p_device_id': deviceId,
        });
        return (n as num).toInt();
      });

  Future<void> verrouillerSeance(String id, bool verrou) =>
      _ecrire(() => _client.from('emplois_du_temps').update({'verrouille': verrou}).eq('id', id));

  Future<void> retirerSeance(String id) => _ecrire(() => _client
      .from('emplois_du_temps')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String(), 'modifie_le': DateTime.now().toUtc().toIso8601String()})
      .eq('id', id));

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
