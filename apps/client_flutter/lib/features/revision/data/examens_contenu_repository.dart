import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/question.dart';

/// Examen du référentiel, vu par l'Administrateur de contenu.
class ExamenReferentiel {
  const ExamenReferentiel({required this.id, required this.paysCode, required this.code, required this.nom, this.cycle});

  final String id;
  final String paysCode;
  final String code;
  final String nom;
  final String? cycle;
}

class SessionExamenContenu {
  const SessionExamenContenu({required this.id, required this.annee, required this.dateDebut});

  final String id;
  final int annee;
  final DateTime dateDebut;
}

class EpreuveContenu {
  const EpreuveContenu({
    this.id,
    required this.libelle,
    required this.matiereCode,
    required this.dureeMin,
    required this.coefficient,
    this.questionsBlanc = 20,
    this.ordre = 0,
  });

  final String? id;
  final String libelle;
  final String matiereCode;
  final int dureeMin;
  final double coefficient;
  final int questionsBlanc;
  final int ordre;
}

enum DroitDiffusion {
  aVerifier('a_verifier', 'À vérifier'),
  sourceOfficielle('source_officielle', 'Source officielle'),
  licence('licence', 'Licence explicite'),
  domainePublic('domaine_public', 'Domaine public administratif');

  const DroitDiffusion(this.code, this.libelle);

  final String code;
  final String libelle;

  static DroitDiffusion depuisCode(String? c) =>
      values.firstWhere((d) => d.code == c, orElse: () => DroitDiffusion.aVerifier);
}

class AnnaleContenu {
  const AnnaleContenu({
    required this.id,
    required this.annee,
    required this.titre,
    required this.source,
    this.session = 'normale',
    this.droit = DroitDiffusion.aVerifier,
    this.statut = StatutContenu.brouillon,
    this.epreuveId,
    this.sujetChemin,
    this.corrigeChemin,
  });

  final String id;
  final int annee;
  final String titre;
  final String source;
  final String session;
  final DroitDiffusion droit;
  final StatutContenu statut;
  final String? epreuveId;
  final String? sujetChemin;
  final String? corrigeChemin;
}

class ErreurExamensContenu implements Exception {
  const ErreurExamensContenu(this.code);

  final String code;

  String get message => switch (code) {
        'DROIT_DIFFUSION_A_VERIFIER' =>
          'Établissez d’abord le droit de diffusion (source officielle, licence ou domaine public).',
        'ANNALE_VIDE' => 'Ajoutez un sujet ou des questions avant de publier.',
        'SOURCE_REQUISE' => 'Indiquez la source de l’annale.',
        'EPREUVE_REQUISE' => 'Choisissez d’abord l’épreuve de l’annale, puis enregistrez.',
        'PERMISSION_REFUSEE' => 'Réservé à l’Administrateur de contenu pédagogique.',
        'HORS_LIGNE' => 'Pas de réseau : cette action se fait en ligne.',
        'FICHIER_TROP_LOURD' => 'Fichier trop lourd (10 Mo au plus).',
        _ => 'Action impossible pour le moment. Réessayez.',
      };
}

/// Examens, sessions, épreuves et annales (REG-38), côté Administrateur de
/// contenu ; en ligne seulement.
class ExamensContenuRepository {
  ExamensContenuRepository(this._client);

  final SupabaseClient _client;

  Future<T> _f<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      throw ErreurExamensContenu(RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)
          ? premier
          : e.code == '42501'
              ? 'PERMISSION_REFUSEE'
              : 'ERREUR_SERVEUR');
    } on StorageException catch (e) {
      throw ErreurExamensContenu(e.statusCode == '413' ? 'FICHIER_TROP_LOURD' : 'ERREUR_SERVEUR');
    } on ErreurExamensContenu {
      rethrow;
    } catch (_) {
      throw const ErreurExamensContenu('HORS_LIGNE');
    }
  }

  Future<List<ExamenReferentiel>> examens() => _f(() async {
        final l = await _client
            .from('examens_nationaux')
            .select('id, pays_code, code, nom, cycles_educatifs(nom)')
            .order('pays_code')
            .order('code');
        return [
          for (final x in l)
            ExamenReferentiel(
              id: x['id'] as String,
              paysCode: '${x['pays_code']}',
              code: '${x['code']}',
              nom: '${x['nom']}',
              cycle: (x['cycles_educatifs'] as Map?)?['nom'] as String?,
            ),
        ];
      });

  Future<List<SessionExamenContenu>> sessions(String examenId) => _f(() async {
        final l = await _client.from('sessions_examen').select().eq('examen_id', examenId).order('annee', ascending: false);
        return [
          for (final s in l)
            SessionExamenContenu(id: s['id'] as String, annee: s['annee'] as int, dateDebut: DateTime.parse('${s['date_debut']}')),
        ];
      });

  Future<void> ajouterSession(String examenId, DateTime date) => _f(() => _client.from('sessions_examen').upsert({
        'examen_id': examenId,
        'annee': date.year,
        'date_debut': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      }, onConflict: 'examen_id,annee'));

  Future<void> supprimerSession(String id) => _f(() => _client.from('sessions_examen').delete().eq('id', id));

  Future<List<EpreuveContenu>> epreuves(String examenId) => _f(() async {
        final l = await _client.from('epreuves_examen').select().eq('examen_id', examenId).order('ordre').order('libelle');
        return [
          for (final e in l)
            EpreuveContenu(
              id: e['id'] as String,
              libelle: '${e['libelle']}',
              matiereCode: '${e['matiere_code']}',
              dureeMin: e['duree_min'] as int,
              coefficient: (e['coefficient'] as num).toDouble(),
              questionsBlanc: e['questions_blanc'] as int,
              ordre: e['ordre'] as int,
            ),
        ];
      });

  Future<void> enregistrerEpreuve(String examenId, EpreuveContenu e) => _f(() async {
        final ligne = {
          'examen_id': examenId,
          'libelle': e.libelle.trim(),
          'matiere_code': e.matiereCode.trim().toUpperCase(),
          'duree_min': e.dureeMin,
          'coefficient': e.coefficient,
          'questions_blanc': e.questionsBlanc,
          'ordre': e.ordre,
        };
        if (e.id == null) {
          await _client.from('epreuves_examen').insert(ligne);
        } else {
          await _client.from('epreuves_examen').update(ligne).eq('id', e.id!);
        }
      });

  Future<void> supprimerEpreuve(String id) => _f(() => _client.from('epreuves_examen').delete().eq('id', id));

  Future<List<AnnaleContenu>> annales(String examenId) => _f(() async {
        final l = await _client.from('annales').select().eq('examen_id', examenId).order('annee', ascending: false);
        return [
          for (final a in l)
            AnnaleContenu(
              id: a['id'] as String,
              annee: a['annee'] as int,
              titre: '${a['titre']}',
              source: '${a['source']}',
              session: '${a['session']}',
              droit: DroitDiffusion.depuisCode(a['droit'] as String?),
              statut: StatutContenu.depuisCode(a['statut'] as String?),
              epreuveId: a['epreuve_id'] as String?,
              sujetChemin: a['sujet_chemin'] as String?,
              corrigeChemin: a['corrige_chemin'] as String?,
            ),
        ];
      });

  Future<void> enregistrerAnnale(String examenId, AnnaleContenu a) => _f(() => _client.rpc<dynamic>('enregistrer_annale', params: {
        'p_id': a.id,
        'p_examen': examenId,
        'p_annee': a.annee,
        'p_titre': a.titre,
        'p_source': a.source,
        'p_droit': a.droit.code,
        'p_session': a.session,
        'p_epreuve': a.epreuveId,
        'p_sujet_chemin': a.sujetChemin,
        'p_corrige_chemin': a.corrigeChemin,
      }));

  Future<void> changerStatutAnnale(String id, String action) =>
      _f(() => _client.rpc<dynamic>('changer_statut_annale', params: {'p_id': id, 'p_action': action}));

  /// Choisit un PDF ou une image sur l'appareil et l'envoie ; renvoie son
  /// chemin, ou null si l'utilisateur annule.
  Future<String?> choisirEtEnvoyer(String dossier) async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp']);
    if (f == null) return null;
    final Uint8List octets = await f.readAsBytes();
    if (octets.length > 10 * 1024 * 1024) throw const ErreurExamensContenu('FICHIER_TROP_LOURD');
    final ext = (f.extension ?? 'pdf').toLowerCase();
    final chemin = '$dossier/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _f(() => _client.storage.from('annales').uploadBinary(
          chemin,
          octets,
          fileOptions: FileOptions(
            contentType: switch (ext) {
              'png' => 'image/png',
              'webp' => 'image/webp',
              'jpg' || 'jpeg' => 'image/jpeg',
              _ => 'application/pdf',
            },
            upsert: true,
          ),
        ));
    return chemin;
  }

  Future<Uri> lien(String chemin) => _f(() async => Uri.parse(await _client.storage.from('annales').createSignedUrl(chemin, 3600)));

  /// Version interactive : questions de la banque, dans l'ordre.
  Future<List<String>> questionsAnnale(String annaleId) => _f(() async {
        final l = await _client.from('annales_questions').select('question_id').eq('annale_id', annaleId).order('ordre');
        return [for (final q in l) '${q['question_id']}'];
      });

  Future<void> definirQuestionsAnnale(String annaleId, List<String> ids) => _f(() async {
        await _client.from('annales_questions').delete().eq('annale_id', annaleId);
        if (ids.isEmpty) return;
        await _client.from('annales_questions').insert([
          for (final (i, id) in ids.indexed) {'annale_id': annaleId, 'question_id': id, 'ordre': i},
        ]);
      });

  /// Questions publiées des matières dont le code correspond à l'épreuve,
  /// pour composer la version interactive.
  Future<List<({String id, String enonce, String matiere})>> questionsPubliees(String paysCode, String matiereCode) => _f(() async {
        final l = await _client
            .from('questions')
            .select('id, version_publiee, questions_versions(version, enonce), programmes_matieres!inner(code, nom, programmes_officiels!inner(pays_code))')
            .eq('programmes_matieres.code', matiereCode.toUpperCase())
            .eq('programmes_matieres.programmes_officiels.pays_code', paysCode)
            .not('version_publiee', 'is', null)
            .limit(300);
        return [
          for (final q in l)
            (
              id: q['id'] as String,
              enonce: '${((q['questions_versions'] as List?) ?? const []).cast<Map>().where((v) => v['version'] == q['version_publiee']).firstOrNull?['enonce'] ?? ''}',
              matiere: '${(q['programmes_matieres'] as Map?)?['nom'] ?? ''}',
            ),
        ];
      });
}
