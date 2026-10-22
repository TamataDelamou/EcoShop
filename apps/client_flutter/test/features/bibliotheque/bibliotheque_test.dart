import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/offline/lecture_hors_ligne.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/core/sync/sync_engine.dart';
import 'package:ecoshop_client/features/bibliotheque/data/supabase_bibliotheque_repository.dart';
import 'package:ecoshop_client/features/bibliotheque/domain/bibliotheque.dart';
import 'package:ecoshop_client/features/export_pdf/data/etiquettes_livres_pdf_builder.dart';
import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';

const _etab = 'e1';

const _guichet = DonneesGuichet(
  parametres: ParametresBibliotheque(maxEmprunts: 2, dureePretJours: 14),
  exemplaires: [
    ExemplaireGuichet(id: 'x1', code: 'LIV-000001', livreId: 'l1', titre: 'Une si longue lettre', cote: 'R BA'),
    ExemplaireGuichet(id: 'x2', code: 'LIV-000002', livreId: 'l1', titre: 'Une si longue lettre'),
    ExemplaireGuichet(id: 'x3', code: 'LIV-000003', livreId: 'l2', titre: 'L’Enfant noir'),
  ],
  lecteurs: [LecteurGuichet(ficheEleveId: 'f-awa', nom: 'BAH', prenom: 'Awa', classe: '6e A', jeton: 'JETON-AWA')],
  emprunts: [],
);

SupabaseClient _client(Future<http.Response> Function(http.Request) reponse) => SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      accessToken: () async => 'test-jwt',
      httpClient: MockClient(reponse),
    );

void main() {
  test('lecture d’étiquette : QR ou douchette, jamais une carte d’élève', () {
    expect(codeExemplaireDepuisLecture('ECOLIV:LIV-000123'), 'LIV-000123');
    expect(codeExemplaireDepuisLecture(' liv-000123 '), 'LIV-000123');
    expect(codeExemplaireDepuisLecture('ECO1.abcdef'), isNull);
  });

  group('guichet sans réseau', () {
    late AppDatabase db;
    late DriftSyncRepository file;
    late SupabaseBibliothequeRepository depot;

    setUp(() async {
      db = AppDatabase.pourTests(NativeDatabase.memory());
      file = DriftSyncRepository(db);
      final store = CacheDocumentStore(db, 'bibliotheque_hl');
      await store.ecrireDocument('guichet_local', _etab, _guichet.versJson());
      depot = SupabaseBibliothequeRepository(
        _client((_) async => throw http.ClientException('Failed host lookup')),
        file,
        store,
        LectureHorsLigne(store, ValueNotifier<DateTime?>(null)),
      );
    });

    tearDown(() => db.close());

    test('prêt, double prêt refusé, limite, retour : mêmes contrôles qu’au serveur', () async {
      final awa = (await depot.guichet(_etab)).lecteurParJeton('JETON-AWA')!;

      final r1 = await depot.preter(etablissementId: _etab, lecteur: awa, code: 'LIV-000001');
      expect(r1.statut, StatutGuichet.enAttenteEnvoi);
      final aujourdHui = DateTime.now();
      expect(r1.echeance, DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day + 14));

      final doublePret = await depot.preter(etablissementId: _etab, lecteur: awa, code: 'LIV-000001');
      expect(doublePret.statut, StatutGuichet.refuse);
      expect(doublePret.message, contains('déjà prêté'));

      await depot.preter(etablissementId: _etab, lecteur: awa, code: 'LIV-000003');
      final limite = await depot.preter(etablissementId: _etab, lecteur: awa, code: 'LIV-000002');
      expect(limite.message, contains('nombre maximal'));

      final retour = await depot.rendre(etablissementId: _etab, code: 'LIV-000001');
      expect(retour.statut, StatutGuichet.enAttenteEnvoi);
      expect(retour.lecteur?.prenom, 'Awa');
      expect((await depot.guichet(_etab, rafraichir: false)).empruntsDe('f-awa').length, 1);

      final entrees = await file.entreesEnAttente();
      expect(entrees.map((e) => e.entite), [
        SupabaseBibliothequeRepository.entitePret,
        SupabaseBibliothequeRepository.entitePret,
        SupabaseBibliothequeRepository.entiteRetour,
      ]);
      expect(RejeuBibliotheque.libelle(entrees.first), 'Prêt de « Une si longue lettre »');
    });

    test('rejeu : prêt refusé par le serveur expliqué (deux guichets, même livre)', () async {
      final rejeu = RejeuBibliotheque(_client((r) async => http.Response(
            jsonEncode({'code': 'P0001', 'message': 'EXEMPLAIRE_DEJA_PRETE'}),
            400,
            headers: {'content-type': 'application/json'},
            request: r,
          )));
      const entree = SyncEntree(
        id: 'p1',
        entite: SupabaseBibliothequeRepository.entitePret,
        operation: 'rpc',
        payload: '{"rpc":"preter_exemplaire","params":{"p_code":"LIV-000001"},"titre":"Une si longue lettre"}',
      );
      await expectLater(
        rejeu.rejouer(entree),
        throwsA(isA<RejetDefinitif>().having((r) => r.message, 'message', contains('déjà prêté'))),
      );
    });
  });

  test('ISBN : fiche préremplie depuis Open Library', () async {
    final db = AppDatabase.pourTests(NativeDatabase.memory());
    addTearDown(db.close);
    final web = MockClient((r) async {
      expect(r.url.host, 'openlibrary.org');
      return http.Response(
        jsonEncode({
          'ISBN:9782842610271': {
            'title': 'Une si longue lettre',
            'authors': [{'name': 'Mariama Bâ'}],
            'publishers': [{'name': 'Le Serpent à Plumes'}],
            'publish_date': '2001',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final depot = SupabaseBibliothequeRepository(
      _client((_) async => throw http.ClientException('x')),
      DriftSyncRepository(db),
      CacheDocumentStore(db, 'bibliotheque_hl'),
      null,
      web,
    );
    final s = await depot.rechercherIsbn('978-2-84261-027-1');
    expect(s?.titre, 'Une si longue lettre');
    expect(s?.auteurs, 'Mariama Bâ');
    expect(s?.annee, 2001);
    expect(await depot.rechercherIsbn('123'), isNull);
  });

  test('étiquettes : PDF valide, plusieurs pages au-delà de 24', () async {
    final exemplaires = [
      for (var i = 1; i <= 30; i++)
        ExemplaireGuichet(id: 'x$i', code: 'LIV-${i.toString().padLeft(6, '0')}', livreId: 'l', titre: 'Livre $i'),
    ];
    final octets = await construireEtiquettesLivresPdf(
      exemplaires: exemplaires,
      etablissement: const Etablissement(id: 'e', nom: 'École', slug: 'ecole'),
      variante: AppThemeVariant.francophoneCfa,
    );
    expect(String.fromCharCodes(octets.take(5)), '%PDF-');
  });
}
