import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/classement.dart';
import '../domain/examen.dart';
import '../domain/examen_national.dart';
import '../domain/maitrise.dart';
import '../domain/quiz.dart';

/// Niveau de révision d'un élève (classe de son inscription).
class NiveauRevision {
  const NiveauRevision({required this.niveauId, this.filiereId, required this.nom, this.grade = 7});

  final String niveauId;
  final String? filiereId;
  final String nom;
  final int grade;

  /// CP1 à CE2 et préscolaire (cahier 9.6).
  bool get petitesClasses => grade <= 4;
}

class ErreurRevision implements Exception {
  const ErreurRevision(this.code);

  final String code;

  String get message => switch (code) {
        'HORS_LIGNE' => 'Pas de réseau : les questions se téléchargent une première fois avec le réseau, ensuite tout marche sans.',
        'SANS_CLASSE' => 'L’élève n’est pas encore inscrit dans une classe : les révisions suivent le niveau de sa classe.',
        'PERMISSION_REFUSEE' => 'Seuls l’élève et ses parents reliés peuvent réviser ici.',
        _ => 'Révisions indisponibles pour le moment. Réessayez.',
      };

  @override
  String toString() => code;
}

/// Révisions (REG-37 lot R2), hors connexion d'abord : le paquet du niveau
/// reste sur l'appareil et n'est retéléchargé que s'il a changé ; les quiz
/// faits sans réseau partent au retour, une seule fois.
class RevisionRepository {
  RevisionRepository(this._client, this._copies, this._lecture, this._file);

  final SupabaseClient _client;
  final CacheDocumentStore _copies;
  final LectureHorsLigne _lecture;
  final DriftSyncRepository _file;

  static const entiteTentative = 'tentative_revision';
  static const entiteSignalement = 'signalement_question';
  static const entites = [entiteTentative, entiteSignalement];

  Future<NiveauRevision> niveau(String ficheId) async {
    Map<String, dynamic>? ligne;
    try {
      ligne = await _lecture.lire(
        type: 'niveau',
        cle: ficheId,
        source: () async {
          final r = await _client.rpc<dynamic>('niveau_revision_fiche', params: {'p_fiche': ficheId});
          return (r as List?)?.firstOrNull;
        },
        decoder: (json) => (json as Map?)?.cast<String, dynamic>(),
      );
    } catch (e) {
      throw _traduire(e);
    }
    if (ligne == null || ligne['niveau_id'] == null) throw const ErreurRevision('SANS_CLASSE');
    return NiveauRevision(
      niveauId: ligne['niveau_id'] as String,
      filiereId: ligne['filiere_id'] as String?,
      nom: '${ligne['niveau_nom'] ?? ''}',
      grade: (ligne['grade'] as num?)?.toInt() ?? 7,
    );
  }

  /// Paquet du niveau : copie de l'appareil, actualisée si l'empreinte a
  /// changé. Sans réseau, la copie suffit.
  Future<PaquetRevision> paquet(NiveauRevision n, {bool actualiser = true}) async {
    final cle = '${n.niveauId}|${n.filiereId ?? ''}';
    final copie = await _copies.lireDocument('paquet', cle);
    final local = copie == null ? null : PaquetRevision.depuisJson(copie);
    if (!actualiser && local != null) return local;
    try {
      final r = await _client.rpc<dynamic>('paquet_revision', params: {
        'p_niveau': n.niveauId,
        'p_filiere': n.filiereId,
        'p_empreinte': local?.empreinte,
      }).timeout(const Duration(seconds: 20));
      final json = (r as Map).cast<String, dynamic>();
      if (json['inchange'] == true && local != null) return local;
      await _copies.ecrireDocument('paquet', cle, json);
      return PaquetRevision.depuisJson(json);
    } catch (e) {
      if (local != null && (estErreurReseau(e) || e is! PostgrestException)) return local;
      throw _traduire(e);
    }
  }

  Future<Map<String, TraceQuestion>> traces(String ficheId) async {
    final doc = await _copies.lireDocument('traces', ficheId) ?? const {};
    return {
      for (final e in doc.entries)
        if (e.value is Map) e.key: TraceQuestion.depuisJson((e.value as Map).cast<String, dynamic>()),
    };
  }

  /// Termine (ou abandonne) un quiz : traces de l'appareil mises à jour,
  /// puis envoi ; sans réseau, gardé et envoyé au retour. Vrai si reçu.
  Future<bool> enregistrer(SessionQuiz s, {required bool termine}) async {
    final fin = DateTime.now();
    final anciennes = await traces(s.ficheId);
    for (final r in s.reponses) {
      final t = anciennes[r.question.id];
      anciennes[r.question.id] =
          TraceQuestion(vues: (t?.vues ?? 0) + 1, dernierScore: r.correction.score, derniereFois: fin);
    }
    await _copies.ecrireDocument('traces', s.ficheId, {for (final e in anciennes.entries) e.key: e.value.versJson()});
    if (s.reponses.isEmpty && !termine) return true; // rien à compter
    final tentative = s.versTentative(termine: termine, fin: fin);
    try {
      await _client.rpc<dynamic>('enregistrer_tentative_revision', params: {'p_tentative': tentative});
      return true;
    } catch (e) {
      if (!estErreurReseau(e)) throw _traduire(e);
    }
    await _file.enfiler(SyncEntree(
      id: '$entiteTentative:${s.id}',
      entite: entiteTentative,
      operation: 'rpc',
      payload: jsonEncode(tentative),
    ));
    return false;
  }

  /// Remet un examen blanc : traces mises à jour, envoi ou mise en file.
  Future<bool> enregistrerExamen(SessionExamen e) async {
    final fin = e.remisLe ?? DateTime.now();
    final anciennes = await traces(e.ficheId);
    for (var i = 0; i < e.questions.length; i++) {
      final q = e.questions[i];
      final t = anciennes[q.id];
      anciennes[q.id] = TraceQuestion(vues: (t?.vues ?? 0) + 1, dernierScore: e.corrections[i].score, derniereFois: fin);
    }
    await _copies.ecrireDocument('traces', e.ficheId, {for (final x in anciennes.entries) x.key: x.value.versJson()});
    final tentative = e.versTentative();
    try {
      await _client.rpc<dynamic>('enregistrer_tentative_revision', params: {'p_tentative': tentative});
      return true;
    } catch (err) {
      if (!estErreurReseau(err)) throw _traduire(err);
    }
    await _file.enfiler(SyncEntree(
      id: '$entiteTentative:${e.id}',
      entite: entiteTentative,
      operation: 'rpc',
      payload: jsonEncode(tentative),
    ));
    return false;
  }

  /// Classement de la semaine (classe ou école) ; copie de l'appareil
  /// sans réseau.
  Future<ClassementRevision> classement(String ficheId, {String echelle = 'classe'}) async {
    try {
      return await _lecture.lire(
        type: 'classement',
        cle: '$ficheId|$echelle',
        source: () => _client.rpc<dynamic>('classement_revision', params: {'p_fiche': ficheId, 'p_echelle': echelle}),
        decoder: (json) => ClassementRevision.depuisJson(((json as Map?) ?? const {}).cast<String, dynamic>()),
      );
    } catch (e) {
      throw _traduire(e);
    }
  }

  /// Apparaître ou non dans le classement (l'élève ou son parent).
  Future<void> definirClassementVisible(String ficheId, bool visible) async {
    try {
      await _client.rpc<dynamic>('definir_classement_visible', params: {'p_fiche': ficheId, 'p_visible': visible});
    } catch (e) {
      throw _traduire(e);
    }
  }

  /// Bilan de la semaine, en mots simples (le même que la notification du
  /// dimanche) ; null sans réseau ni copie.
  Future<String?> bilan(String ficheId) async {
    try {
      return await _lecture.lire(
        type: 'bilan',
        cle: ficheId,
        source: () => _client.rpc<dynamic>('bilan_revision', params: {'p_fiche': ficheId}),
        decoder: (json) => json is String ? json : null,
      );
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- lot R4

  Future<T> _lireR4<T>(String type, String cle, Future<Object?> Function() source, T Function(Object?) decoder) async {
    try {
      return await _lecture.lire(type: type, cle: cle, source: source, decoder: decoder);
    } catch (e) {
      throw _traduire(e);
    }
  }

  Future<ProfilMaitrise> profil(String ficheId) => _lireR4('profil', ficheId,
      () => _client.rpc<dynamic>('profil_maitrise', params: {'p_fiche': ficheId}), ProfilMaitrise.depuisJson);

  Future<RevisionsDuJour> revisionsDuJour(String ficheId, {int limite = 20}) => _lireR4(
        'repetition',
        '$ficheId|$limite',
        () => _client.rpc<dynamic>('revisions_du_jour', params: {'p_fiche': ficheId, 'p_limite': limite}),
        (json) => RevisionsDuJour.depuisJson(((json as Map?) ?? const {}).cast<String, dynamic>()),
      );

  Future<PlanRevision?> plan(String ficheId) => _lireR4(
        'plan',
        ficheId,
        () => _client.from('plans_revision').select().eq('fiche_eleve_id', ficheId).maybeSingle(),
        (json) => json == null ? null : PlanRevision.depuisJson((json as Map).cast<String, dynamic>()),
      );

  Future<Map<String, num>> coefficients(List<String> matieres) => _lireR4(
        'coefficients',
        (List.of(matieres)..sort()).join(','),
        () => _client.rpc<dynamic>('coefficients_matieres', params: {'p_matieres': matieres}),
        (json) => {for (final e in ((json as Map?) ?? const {}).entries) '${e.key}': (e.value as num?) ?? 1},
      );

  Future<void> definirPlan(String ficheId, PlanRevision p) async {
    try {
      await _client.rpc<dynamic>('definir_plan_revision', params: {
        'p_fiche': ficheId,
        'p_titre': p.titre,
        'p_echeance': '${p.echeance.year.toString().padLeft(4, '0')}-${p.echeance.month.toString().padLeft(2, '0')}-'
            '${p.echeance.day.toString().padLeft(2, '0')}',
        'p_matieres': p.matieres,
        'p_questions_par_jour': p.questionsParJour,
      });
    } catch (e) {
      throw _traduire(e);
    }
  }

  Future<void> supprimerPlan(String ficheId) async {
    try {
      await _client.rpc<dynamic>('supprimer_plan_revision', params: {'p_fiche': ficheId});
    } catch (e) {
      throw _traduire(e);
    }
  }

  /// Espaces de préparation aux examens nationaux de l'élève (REG-38).
  Future<List<EspaceExamen>> espacesExamens(String ficheId) => _lireR4('espaces_examens', ficheId,
      () => _client.rpc<dynamic>('espaces_preparation', params: {'p_fiche': ficheId}), EspaceExamen.liste);

  /// Fin de primaire : remise automatique de la copie à la fin du temps.
  Future<void> definirChronoStrict(String ficheId, bool strict) async {
    try {
      await _client.rpc<dynamic>('definir_chrono_strict', params: {'p_fiche': ficheId, 'p_strict': strict});
    } catch (e) {
      throw _traduire(e);
    }
  }

  /// Lien temporaire vers un sujet ou un corrigé d'annale.
  Future<Uri> lienAnnale(String chemin) async {
    try {
      return Uri.parse(await _client.storage.from('annales').createSignedUrl(chemin, 3600));
    } catch (e) {
      throw _traduire(e);
    }
  }

  /// Enseignant ou direction : classes suivies et maîtrise d'une classe.
  Future<List<({String id, String nom, int eleves})>> classesSuivies(String etablissementId) => _lireR4(
        'classes_suivi',
        etablissementId,
        () => _client.rpc<dynamic>('classes_suivi_revision', params: {'p_etablissement': etablissementId}),
        (json) => [
          for (final l in (json as List?) ?? const [])
            (
              id: '${(l as Map)['classe_id']}',
              nom: '${l['nom'] ?? ''}',
              eleves: (l['eleves'] as num?)?.toInt() ?? 0,
            ),
        ],
      );

  Future<MaitriseClasse> maitriseClasse(String classeId) => _lireR4('maitrise_classe', classeId,
      () => _client.rpc<dynamic>('maitrise_classe', params: {'p_classe': classeId}),
      (json) => MaitriseClasse.depuisJson(((json as Map?) ?? const {}).cast<String, dynamic>()));

  /// Résumé des révisions (élève ou parent), quiz de cet appareil compris.
  Future<ResumeRevision> resume(String ficheId, {int jours = 30, PaquetRevision? paquet}) async {
    ResumeRevision serveur;
    try {
      serveur = await _lecture.lire(
        type: 'resume',
        cle: '$ficheId|$jours',
        source: () => _client.rpc<dynamic>('resume_revision', params: {'p_fiche': ficheId, 'p_jours': jours}),
        decoder: (json) => ResumeRevision.depuisJson(((json as Map?) ?? const {}).cast<String, dynamic>()),
      );
    } catch (e) {
      if (!estErreurReseau(e)) throw _traduire(e);
      serveur = ResumeRevision(jours: jours);
    }
    final enAttente = [
      for (final e in await _file.entreesEnAttente())
        if (e.entite == entiteTentative) jsonDecode(e.payload) as Map<String, dynamic>,
    ].where((t) => t['fiche_eleve_id'] == ficheId).toList();
    return serveur.avecEnAttente(enAttente, {for (final q in paquet?.questions ?? const <QuestionQuiz>[]) q.id: q});
  }

  /// Signaler une question (cahier 10.3) ; sans réseau, envoyé au retour.
  Future<void> signaler(String questionId, String motif, {String? commentaire}) async {
    final params = {'p_question': questionId, 'p_motif': motif, 'p_commentaire': commentaire};
    try {
      await _client.rpc<dynamic>('signaler_question', params: params);
      return;
    } catch (e) {
      if (!estErreurReseau(e)) throw _traduire(e);
    }
    await _file.enfiler(SyncEntree(
      id: '$entiteSignalement:$questionId',
      entite: entiteSignalement,
      operation: 'rpc',
      payload: jsonEncode(params),
    ));
  }

  Future<Uri> lienMedia(String chemin) async =>
      Uri.parse(await _client.storage.from('questions-medias').createSignedUrl(chemin, 3600));

  static ErreurRevision _traduire(Object e) {
    if (e is ErreurRevision) return e;
    if (estErreurReseau(e)) return const ErreurRevision('HORS_LIGNE');
    if (e is PostgrestException && (e.code == '42501' || e.message.contains('PERMISSION_REFUSEE'))) {
      return const ErreurRevision('PERMISSION_REFUSEE');
    }
    return const ErreurRevision('ERREUR_SERVEUR');
  }

  /// Rejeu au retour du réseau.
  static Future<void> rejouer(SupabaseClient client, SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      if (entree.entite == entiteTentative) {
        await client.rpc<dynamic>('enregistrer_tentative_revision', params: {'p_tentative': p});
      } else {
        await client.rpc<dynamic>('signaler_question', params: p);
      }
    } catch (e) {
      if (estErreurReseau(e)) rethrow;
      final erreur = _traduire(e);
      throw RejetDefinitif(erreur.code, erreur.message);
    }
  }

  static String libelle(SyncEntree entree) =>
      entree.entite == entiteTentative ? 'Quiz de révision' : 'Signalement d’une question';
}
