import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/bibliotheque.dart';

/// Bibliothèque physique (M17), d'abord hors connexion.
///
/// Le guichet garde sur l'appareil exemplaires, cartes des élèves et prêts
/// en cours : prêter et reprendre un livre marchent sans réseau, avec les
/// mêmes contrôles qu'au serveur (exemplaire déjà prêté, limite d'emprunts).
/// Chaque geste part tout de suite ou attend le réseau avec sa clé et son
/// heure réelle ; le serveur tranche si deux guichets ont prêté le même
/// exemplaire (le second prêt est refusé et expliqué dans le bandeau).
class SupabaseBibliothequeRepository implements BibliothequeRepository {
  SupabaseBibliothequeRepository(this._client, this._file, this._store, [this._lecture, http.Client? web])
      : _web = web ?? http.Client();

  final SupabaseClient _client;
  final DriftSyncRepository _file;
  final CacheDocumentStore _store;
  final LectureHorsLigne? _lecture;
  final http.Client _web;
  final Uuid _uuid = const Uuid();

  static const entitePret = 'bibliotheque_pret';
  static const entiteRetour = 'bibliotheque_retour';
  static const entites = [entitePret, entiteRetour];
  static const _typeGuichet = 'guichet_local';
  static const _delai = Duration(seconds: 6);

  // -------------------------------------------------------------------------
  // Outils
  // -------------------------------------------------------------------------
  static ErreurBibliotheque _traduire(Object e) {
    if (e is ErreurBibliotheque) return e;
    if (e is PostgrestException) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) return ErreurBibliotheque(premier);
      if (e.code == '42501') return const ErreurBibliotheque('ACCES_REFUSE');
      return ErreurBibliotheque(e.code ?? 'ERREUR_SERVEUR');
    }
    if (estErreurReseau(e)) return const ErreurBibliotheque('HORS_CONNEXION');
    return ErreurBibliotheque(e.toString());
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      throw _traduire(e);
    }
  }

  Future<T> _lire<T>(String type, String cle, Future<Object?> Function() source, T Function(Object?) decoder) {
    final lecture = _lecture;
    if (lecture == null) return _executer(() async => decoder(await source()));
    return _executer(() => lecture.lire(type: type, cle: cle, source: source, decoder: decoder));
  }

  Future<Object?> _rpc(String nom, [Map<String, dynamic>? params, Duration delai = const Duration(seconds: 15)]) =>
      _client.rpc<dynamic>(nom, params: params).timeout(delai);

  static String _maintenant() => DateTime.now().toUtc().toIso8601String();

  Future<void> _garderGuichet(String etablissementId, DonneesGuichet d) =>
      _store.ecrireDocument(_typeGuichet, etablissementId, d.versJson());

  // -------------------------------------------------------------------------
  // Catalogue, emprunts de l'élève, réservation
  // -------------------------------------------------------------------------
  @override
  Future<List<Livre>> catalogue(String etablissementId, {String? texte}) => _lire(
        'catalogue',
        '$etablissementId/${texte ?? ''}',
        () => _rpc('catalogue_bibliotheque', {'p_etablissement': etablissementId, 'p_texte': texte}),
        (json) => [for (final l in (json as List?) ?? const []) Livre.depuisJson((l as Map).cast<String, dynamic>())],
      );

  @override
  Future<({List<EmpruntEleve> emprunts, List<ReservationEleve> reservations})> empruntsEleve(String ficheEleveId) => _lire(
        'emprunts_eleve',
        ficheEleveId,
        () => _rpc('emprunts_eleve', {'p_fiche': ficheEleveId}),
        (json) {
          final j = (json as Map).cast<String, dynamic>();
          return (
            emprunts: [for (final e in (j['emprunts'] as List?) ?? const []) EmpruntEleve.depuisJson((e as Map).cast<String, dynamic>())],
            reservations: [
              for (final r in (j['reservations'] as List?) ?? const []) ReservationEleve.depuisJson((r as Map).cast<String, dynamic>()),
            ],
          );
        },
      );

  @override
  Future<void> reserver(String livreId, String ficheEleveId) =>
      _executer(() => _rpc('reserver_livre', {'p_livre': livreId, 'p_fiche': ficheEleveId}));

  // -------------------------------------------------------------------------
  // Catalogue (gestion)
  // -------------------------------------------------------------------------
  @override
  Future<String> enregistrerLivre(String etablissementId, SaisieLivre s, {String? id, int nouveauxExemplaires = 0}) =>
      _executer(() async {
        final cle = id ?? _uuid.v4();
        await _rpc('enregistrer_livre', {
          'p_id': cle,
          'p_etablissement': etablissementId,
          'p_titre': s.titre,
          'p_auteurs': s.auteurs,
          'p_isbn': s.isbn,
          'p_editeur': s.editeur,
          'p_annee': s.annee,
          'p_categorie': s.categorie,
          'p_niveau': s.niveau,
          'p_cote': s.cote,
          'p_resume': s.resume,
          'p_nouveaux_exemplaires': nouveauxExemplaires,
        });
        // Les nouveaux exemplaires doivent être connus du guichet sans réseau.
        await guichet(etablissementId).catchError((Object _) => const DonneesGuichet(
              parametres: ParametresBibliotheque(),
              exemplaires: [],
              lecteurs: [],
              emprunts: [],
            ));
        return cle;
      });

  /// Fiche préremplie depuis l'ISBN (Open Library, gratuit) ; `null` si le
  /// livre est inconnu ou sans réseau — la saisie reste possible à la main.
  @override
  Future<SaisieLivre?> rechercherIsbn(String isbn) async {
    final propre = isbn.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');
    if (propre.length != 10 && propre.length != 13) return null;
    try {
      final reponse = await _web
          .get(Uri.parse('https://openlibrary.org/api/books?bibkeys=ISBN:$propre&format=json&jscmd=data'))
          .timeout(const Duration(seconds: 8));
      if (reponse.statusCode != 200) return null;
      final j = (jsonDecode(reponse.body) as Map)['ISBN:$propre'] as Map?;
      if (j == null) return null;
      String? noms(Object? liste) {
        final n = [for (final a in (liste as List?) ?? const []) (a as Map)['name'] as String?].whereType<String>().join(', ');
        return n.isEmpty ? null : n;
      }

      final annee = RegExp(r'(1[4-9]|20)\d{2}').firstMatch(j['publish_date'] as String? ?? '')?.group(0);
      final titre = [j['title'] as String?, j['subtitle'] as String?].whereType<String>().join(' : ');
      if (titre.isEmpty) return null;
      return SaisieLivre(
        titre: titre,
        auteurs: noms(j['authors']),
        isbn: propre,
        editeur: noms(j['publishers']),
        annee: annee == null ? null : int.parse(annee),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ExemplaireGuichet>> exemplairesDuLivre(String etablissementId, String livreId) async {
    final d = await guichet(etablissementId);
    return d.exemplaires.where((e) => e.livreId == livreId).toList()..sort((a, b) => a.code.compareTo(b.code));
  }

  // -------------------------------------------------------------------------
  // Guichet
  // -------------------------------------------------------------------------
  @override
  Future<DonneesGuichet> guichet(String etablissementId, {bool rafraichir = true}) async {
    final garde = await _store.lireDocument(_typeGuichet, etablissementId);
    final local = garde == null ? null : DonneesGuichet.depuisJson(garde);
    if (!rafraichir && local != null) return local;
    try {
      final json = await _executer(() => _rpc('guichet_bibliotheque', {'p_etablissement': etablissementId}));
      final serveur = DonneesGuichet.depuisJson((json as Map).cast<String, dynamic>());
      // Prêts et retours faits sans réseau, pas encore reçus : gardés.
      final attente = await _file.entreesEnAttente();
      final pretsAttente = [for (final e in local?.emprunts ?? const <EmpruntGuichet>[]) if (e.enAttenteEnvoi) e];
      final retoursAttente = {
        for (final e in attente)
          if (e.entite == entiteRetour) ((jsonDecode(e.payload) as Map)['params'] as Map)['p_code'] as String,
      };
      final fusion = serveur.avecEmprunts([
        for (final e in serveur.emprunts)
          if (!retoursAttente.contains(serveur.exemplaires.where((x) => x.id == e.exemplaireId).firstOrNull?.code)) e,
        for (final e in pretsAttente)
          if (serveur.empruntDe(e.exemplaireId) == null) e,
      ]);
      await _garderGuichet(etablissementId, fusion);
      return fusion;
    } on ErreurBibliotheque catch (e) {
      if (e.code != 'HORS_CONNEXION' || local == null) rethrow;
      return local;
    }
  }

  @override
  Future<ResultatGuichet> preter({required String etablissementId, required LecteurGuichet lecteur, required String code}) async {
    var d = await guichet(etablissementId, rafraichir: false);
    final ex = d.exemplaire(code);
    if (ex == null) {
      return ResultatGuichet(statut: StatutGuichet.refuse, titre: code, message: const ErreurBibliotheque('EXEMPLAIRE_INCONNU').messageUtilisateur);
    }
    if (ex.retire) {
      return ResultatGuichet(statut: StatutGuichet.refuse, titre: ex.titre, message: const ErreurBibliotheque('EXEMPLAIRE_RETIRE').messageUtilisateur);
    }
    if (d.empruntDe(ex.id) != null) {
      return ResultatGuichet(statut: StatutGuichet.refuse, titre: ex.titre, message: const ErreurBibliotheque('EXEMPLAIRE_DEJA_PRETE').messageUtilisateur);
    }
    if (d.empruntsDe(lecteur.ficheEleveId).length >= d.parametres.maxEmprunts) {
      return ResultatGuichet(statut: StatutGuichet.refuse, titre: ex.titre, message: const ErreurBibliotheque('LIMITE_EMPRUNTS').messageUtilisateur);
    }

    final id = _uuid.v4();
    final params = {
      'p_id': id,
      'p_etablissement': etablissementId,
      'p_fiche': lecteur.ficheEleveId,
      'p_code': code,
      'p_le': _maintenant(),
    };
    DateTime echeance;
    var enAttente = false;
    try {
      final r = await _executer(() => _rpc('preter_exemplaire', params, _delai));
      echeance = DateTime.parse((r as Map)['echeance'] as String);
    } on ErreurBibliotheque catch (e) {
      if (e.code != 'HORS_CONNEXION') {
        return ResultatGuichet(statut: StatutGuichet.refuse, titre: ex.titre, message: e.messageUtilisateur, lecteur: lecteur);
      }
      await _file.enfiler(SyncEntree(
        id: id,
        entite: entitePret,
        operation: 'rpc',
        payload: jsonEncode({'rpc': 'preter_exemplaire', 'params': params, 'titre': ex.titre}),
      ));
      final aujourdHui = DateTime.now();
      echeance = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day + d.parametres.dureePretJours);
      enAttente = true;
    }
    d = d.avecEmprunts([
      ...d.emprunts,
      EmpruntGuichet(id: id, exemplaireId: ex.id, ficheEleveId: lecteur.ficheEleveId, echeance: echeance, enAttenteEnvoi: enAttente),
    ]);
    await _garderGuichet(etablissementId, d);
    return ResultatGuichet(
      statut: enAttente ? StatutGuichet.enAttenteEnvoi : StatutGuichet.prete,
      titre: ex.titre,
      echeance: echeance,
      lecteur: lecteur,
    );
  }

  @override
  Future<ResultatGuichet> rendre({required String etablissementId, required String code}) async {
    var d = await guichet(etablissementId, rafraichir: false);
    final ex = d.exemplaire(code);
    final titre = ex?.titre ?? code;
    final emprunt = ex == null ? null : d.empruntDe(ex.id);
    final lecteur = emprunt == null ? null : d.lecteur(emprunt.ficheEleveId);
    try {
      final r = (await _executer(() => _rpc('rendre_exemplaire', {
                'p_etablissement': etablissementId,
                'p_code': code,
                'p_le': _maintenant(),
              }, _delai)) as Map)
          .cast<String, dynamic>();
      if (ex != null) {
        d = d.avecEmprunts([for (final e in d.emprunts) if (e.exemplaireId != ex.id) e]);
        await _garderGuichet(etablissementId, d);
      }
      if (r['statut'] == 'pas_emprunte') {
        return ResultatGuichet(statut: StatutGuichet.pasEmprunte, titre: r['titre'] as String? ?? titre);
      }
      return ResultatGuichet(
        statut: StatutGuichet.rendu,
        titre: r['titre'] as String? ?? titre,
        lecteur: lecteur ?? d.lecteur(r['fiche_eleve_id'] as String? ?? ''),
        reserve: r['reserve'] == true,
        enRetard: r['en_retard'] == true,
      );
    } on ErreurBibliotheque catch (e) {
      if (e.code != 'HORS_CONNEXION') return ResultatGuichet(statut: StatutGuichet.refuse, titre: titre, message: e.messageUtilisateur);
    }
    if (ex == null) {
      return ResultatGuichet(statut: StatutGuichet.refuse, titre: code, message: const ErreurBibliotheque('EXEMPLAIRE_INCONNU').messageUtilisateur);
    }
    await _file.enfiler(SyncEntree(
      id: 'retour:${ex.id}:${DateTime.now().millisecondsSinceEpoch}',
      entite: entiteRetour,
      operation: 'rpc',
      payload: jsonEncode({
        'rpc': 'rendre_exemplaire',
        'params': {'p_etablissement': etablissementId, 'p_code': code, 'p_le': _maintenant()},
        'titre': ex.titre,
      }),
    ));
    d = d.avecEmprunts([for (final e in d.emprunts) if (e.exemplaireId != ex.id) e]);
    await _garderGuichet(etablissementId, d);
    return ResultatGuichet(
      statut: StatutGuichet.enAttenteEnvoi,
      titre: ex.titre,
      lecteur: lecteur,
      enRetard: emprunt != null && DateTime.now().isAfter(emprunt.echeance.add(const Duration(days: 1))),
    );
  }

  @override
  Future<DateTime> renouveler(String empruntId) => _executer(() async {
        final r = await _rpc('renouveler_emprunt', {'p_emprunt': empruntId});
        return DateTime.parse(r as String);
      });

  @override
  Future<void> declarerPerdu(String empruntId) => _executer(() => _rpc('declarer_emprunt_perdu', {'p_emprunt': empruntId}));

  @override
  Future<TableauBibliotheque> tableau(String etablissementId) => _lire(
        'tableau_bibliotheque',
        etablissementId,
        () => _rpc('tableau_bibliotheque', {'p_etablissement': etablissementId}),
        (json) => TableauBibliotheque.depuisJson((json as Map).cast<String, dynamic>()),
      );

  @override
  Future<void> enregistrerParametres(String etablissementId, ParametresBibliotheque p) =>
      _executer(() => _rpc('enregistrer_parametres_bibliotheque', {
            'p_etablissement': etablissementId,
            'p_duree': p.dureePretJours,
            'p_max': p.maxEmprunts,
            'p_renouvellements': p.renouvellementsMax,
            'p_delai_perte': p.delaiPerteJours,
            'p_relances': p.relances,
          }));

  @override
  Future<void> commencerInventaire(String etablissementId) =>
      _executer(() => _rpc('commencer_inventaire_bibliotheque', {'p_etablissement': etablissementId}));

  @override
  Future<String?> inventorier(String etablissementId, String code) => _executer(() async {
        final r = (await _rpc('inventorier_exemplaire', {'p_etablissement': etablissementId, 'p_code': code}) as Map)
            .cast<String, dynamic>();
        return r['statut'] == 'vu' ? r['titre'] as String? : null;
      });
}

/// Rejoue au serveur les prêts et retours faits sans réseau, dans l'ordre.
class RejeuBibliotheque {
  const RejeuBibliotheque(this._client);

  final SupabaseClient _client;

  Future<void> rejouer(SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      await _client.rpc<dynamic>(p['rpc'] as String, params: (p['params'] as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      final metier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier);
      if (metier || e.code == '42501' || e.code == '23505' || e.code == '23514') {
        final code = metier ? premier : 'ACCES_REFUSE';
        throw RejetDefinitif(code, ErreurBibliotheque(code).messageUtilisateur);
      }
      rethrow;
    }
  }

  static String libelle(SyncEntree entree) {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    final titre = p['titre'] as String? ?? '';
    return entree.entite == SupabaseBibliothequeRepository.entitePret ? 'Prêt de « $titre »' : 'Retour de « $titre »';
  }
}
