import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/core/sync/sync_engine.dart';
import 'package:ecoshop_client/features/inscription_en_ligne/data/inscription_hors_ligne_repository.dart';
import 'package:ecoshop_client/features/inscription_en_ligne/data/rejeu_inscriptions.dart';
import 'package:ecoshop_client/features/inscription_en_ligne/domain/inscription_en_ligne.dart';

/// Serveur injoignable, ou joignable selon [enLigne].
class _Serveur implements InscriptionEnLigneRepository {
  bool enLigne = false;
  final List<SaisieDemandeInscription> recues = [];
  final List<String> pieces = [];

  Never _horsLigne() => throw const ErreurInscriptionEnLigne('HORS_CONNEXION');

  @override
  Future<ResultatDemandeInscription> soumettre(SaisieDemandeInscription saisie) async {
    if (!enLigne) _horsLigne();
    recues.add(saisie);
    return ResultatDemandeInscription(id: saisie.id!, numeroDossier: 'INS-2026-00001', statut: StatutDemandeInscription.soumise);
  }

  @override
  Future<void> deposerPiece(String demandeId, PieceAEnvoyer piece) async {
    if (!enLigne) _horsLigne();
    pieces.add('$demandeId/${piece.code}');
  }

  @override
  Future<List<DemandeInscription>> mesDemandes() async => enLigne ? const [] : _horsLigne();

  @override
  Future<StatutDemandeInscription?> traiter(String demandeId, DecisionDossier decision,
          {String? motif, String? niveauId, bool forcer = false}) async =>
      enLigne ? StatutDemandeInscription.acceptee : _horsLigne();

  @override
  Future<String?> finaliserAuGuichet(String demandeId, {String? classeId, double? montant, String moyen = 'especes'}) async =>
      enLigne ? 'inscription-1' : _horsLigne();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late DriftSyncRepository file;
  late _Serveur serveur;
  late InscriptionHorsLigneRepository depot;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    file = DriftSyncRepository(db);
    serveur = _Serveur();
    depot = InscriptionHorsLigneRepository(serveur, file, CacheDocumentStore(db, 'inscriptions_hl'), () async => 'b7c1e2f3-0000');
  });

  tearDown(() => db.close());

  SaisieDemandeInscription nouvelle() => SaisieDemandeInscription(
        campagneId: 'k1',
        type: 'nouvelle',
        nom: 'KOUROUMA',
        prenom: 'Sékou',
        dateNaissance: DateTime(2014, 9, 1),
        niveauId: 'n6e',
        libelleEcole: 'Collège Emmaüs',
        libelleNiveau: '6e',
        niveauIsced: 2,
        piecesRequises: const [PieceRequise(code: 'acte_naissance', libelle: 'Acte de naissance')],
      );

  test('demande sans réseau : numéro provisoire par appareil, clé de l\'appareil, date de saisie', () async {
    final r1 = await depot.soumettre(nouvelle());
    final r2 = await depot.soumettre(nouvelle());

    expect(r1.enAttenteEnvoi, isTrue);
    expect(r1.numeroDossier, 'PROV-B7C1-0001');
    expect(r2.numeroDossier, 'PROV-B7C1-0002');
    final entree = (await file.entreesEnAttente()).first;
    expect(entree.entite, InscriptionHorsLigneRepository.entiteDemande);
    final params = jsonDecode(entree.payload) as Map<String, dynamic>;
    expect(params['p_id'], r1.id, reason: 'la clé rend l\'envoi idempotent au serveur');
    expect(params['p_numero_provisoire'], 'PROV-B7C1-0001');
    expect(params['p_saisi_le'], isNotNull, reason: 'la date de saisie fait foi pour la date limite');
    expect((params['p_donnees'] as Map)['date_naissance'], '2014-09-01');
  });

  test('le dossier apparaît tout de suite dans « Mes dossiers », avec ses pièces en attente', () async {
    final r = await depot.soumettre(nouvelle());
    await depot.deposerPiece(r.id, PieceAEnvoyer(code: 'acte_naissance', octets: Uint8List.fromList([1, 2, 3])));

    final dossiers = await depot.mesDemandes();
    final d = dossiers.single;
    expect(d.enAttenteEnvoi, isTrue);
    expect(d.nomComplet, 'Sékou KOUROUMA');
    expect(d.etablissementNom, 'Collège Emmaüs');
    expect(d.numeroDossier, 'PROV-B7C1-0001');
    expect(d.pieces['acte_naissance'], '', reason: 'pièce présente, encore sur le téléphone');
    expect(d.piecesManquantes, isEmpty);

    final ordre = [for (final e in await file.entreesEnAttente()) e.entite];
    expect(ordre, [InscriptionHorsLigneRepository.entiteDemande, InscriptionHorsLigneRepository.entitePiece],
        reason: 'la pièce part après son dossier');
  });

  test('avec réseau : envoi direct, avec la clé de l\'appareil', () async {
    serveur.enLigne = true;
    final r = await depot.soumettre(nouvelle());
    expect(r.enAttenteEnvoi, isFalse);
    expect(serveur.recues.single.id, isNotNull);
    expect(await file.entreesEnAttente(), isEmpty);
  });

  test('pièce d\'un dossier encore sur le téléphone : elle le suit, même si le réseau revient', () async {
    final r = await depot.soumettre(nouvelle());
    serveur.enLigne = true;
    await depot.deposerPiece(r.id, PieceAEnvoyer(code: 'bulletin', octets: Uint8List.fromList([9])));
    expect(serveur.pieces, isEmpty, reason: 'le serveur ne connaît pas encore le dossier');
    expect((await file.entreesEnAttente()).last.entite, InscriptionHorsLigneRepository.entitePiece);
  });

  test('retirer un dossier jamais parti : retiré de la file avec ses pièces', () async {
    final r = await depot.soumettre(nouvelle());
    await depot.deposerPiece(r.id, PieceAEnvoyer(code: 'acte_naissance', octets: Uint8List.fromList([1])));
    await depot.retirer(r.id);
    expect(await file.entreesEnAttente(), isEmpty);
  });

  test('Direction sans réseau : décision et espèces au guichet gardées pour plus tard', () async {
    await expectLater(
      depot.traiter('d1', DecisionDossier.refuser),
      throwsA(isA<ErreurInscriptionEnLigne>().having((e) => e.code, 'code', 'MOTIF_OBLIGATOIRE')),
    );
    expect(await depot.traiter('d1', DecisionDossier.accepter), isNull);
    expect(await depot.finaliserAuGuichet('d2', montant: 100000), isNull);
    expect(await depot.dossiersAvecActionEnAttente(), {'d1', 'd2'});
  });

  test('refus au rejeu : libellé lisible', () {
    const entree = SyncEntree(
      id: 'x',
      entite: InscriptionHorsLigneRepository.entiteDemande,
      operation: 'upsert',
      payload: '{"p_numero_provisoire":"PROV-B7C1-0001","_affichage":{"prenom":"Sékou","nom":"KOUROUMA","type":"nouvelle"}}',
    );
    expect(RejeuInscriptions.libelle(entree), "Demande d'inscription de Sékou KOUROUMA (dossier PROV-B7C1-0001)");
    expect(const ErreurInscriptionEnLigne('CAMPAGNE_TERMINEE').messageUtilisateur, contains('date limite'));
  });

  test('pièces : code dérivé du libellé, pièces attendues selon le cycle', () {
    expect(PieceRequise.codeDepuisLibelle("Photo d'identité"), 'photo_d_identite');
    const pieces = [
      PieceRequise(code: 'acte', libelle: 'Acte'),
      PieceRequise(code: 'bepc', libelle: 'Relevé du CEPE', iscedMin: 2),
    ];
    final primaire = DemandeInscription.depuisJson({
      'id': 'd',
      'etablissement_id': 'e',
      'campagne_id': 'k',
      'numero_dossier': 'INS-1',
      'nom': 'A',
      'prenom': 'B',
      'niveau_id': 'n',
      'niveau_isced': 1,
      'pieces_requises': [for (final p in pieces) p.versJson()],
    });
    expect([for (final p in primaire.piecesAttendues) p.code], ['acte']);
    expect(primaire.piecesManquantes.single.code, 'acte');
  });
}
