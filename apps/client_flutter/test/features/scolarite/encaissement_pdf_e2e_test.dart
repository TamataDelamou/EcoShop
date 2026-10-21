import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/export_pdf/data/recu_pdf_builder.dart';
import 'package:ecoshop_client/features/scolarite/data/supabase_scolarite_repository.dart';
import 'package:ecoshop_client/features/scolarite/domain/encaissement_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/enums_financier_scolaire.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';

/// Test de bout en bout couvrant la chaîne complète demandée en revue
/// M15quater : `SupabaseScolariteRepository.enregistrerEncaissement()` (le
/// code réellement exécuté par l'écran d'encaissement) -> `construireRecuPdf`
/// à partir de l'objet exact renvoyé par ce même appel — par opposition à des
/// tests séparés sur l'entité et sur le rendu PDF (`encaissement_pdf_builder`
/// n'était jusque-là exercé qu'avec un JSON écrit à la main dans le test).
///
/// Limite assumée et documentée : la table Postgres n'est pas atteinte ici
/// (aucune instance Postgres locale disponible sur ce poste — Docker/Podman
/// bloqués, voir `docs/AUDIT_ECOSHOP_FLUTTER.md`/mémoire de session). Le
/// transport HTTP du `SupabaseClient` est intercepté pour simuler la réponse
/// PostgREST ; en revanche le code métier réellement exécuté (sérialisation
/// `versParamsEnregistrement`, appel de la fonction serveur
/// `enregistrer_encaissement_scolarite`, désérialisation `depuisJson`) est
/// le vrai code de production, pas une
/// doublure. La preuve que le serveur (trigger `encaissements_verifie_tenant`)
/// impose réellement `saisi_par` est apportée séparément, contre une vraie
/// instance Postgres, par `tests/rls/38_m15quater_inscription_encaissement.sql`
/// (assertion 8b).
void main() {
  test(
    'chaîne réelle : enregistrerEncaissement() (code repository de prod) '
    '-> construireRecuPdf() à partir de l\'objet exact renvoyé, '
    'saisi_par transmis par le client jamais utilisé, clé de l\'appareil transmise (idempotence)',
    () async {
      const etablissementId = 'e1';
      const ficheId = 'f1';
      const inscriptionId = 'i1';
      const cleAppareil = '9f0c1d2e-0000-4000-8000-000000000001';
      const saisiParClientBidon = 'p-usurpateur';

      http.Request? requeteInterceptee;

      final client = SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        accessToken: () async => 'test-jwt',
        httpClient: MockClient((request) async {
          requeteInterceptee = request;

          final corps = jsonDecode(request.body) as Map<String, dynamic>;
          // Le serveur répond avec la ligne telle que la fonction
          // `enregistrer_encaissement_scolarite` (migration …1547) et les
          // déclencheurs la produisent : la clé de l'appareil, `saisi_par`
          // imposé, numéro de reçu continu attribué par le serveur.
          final ligneServeur = {
            'id': corps['p_id'],
            'etablissement_id': corps['p_etablissement'],
            'fiche_eleve_id': corps['p_fiche_eleve'],
            'inscription_id': corps['p_inscription'],
            'type_frais': corps['p_type_frais'],
            'montant': corps['p_montant'],
            'moyen_paiement': corps['p_moyen'],
            'reference_paiement': corps['p_reference'],
            'date_paiement': corps['p_date'],
            'saisi_par': 'p-direction-reelle',
            'statut': 'valide',
            'motif_annulation': null,
            'annule_par': null,
            'annule_le': null,
            'created_at': '2026-10-06T09:00:00.000Z',
            'numero_recu': 'SCO-2026-000001',
            'numero_provisoire': null,
            'deja_recu': false,
          };

          return http.Response(
            jsonEncode(ligneServeur),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );

      final repository = SupabaseScolariteRepository(client);

      final encaissementSaisi = EncaissementScolarite(
        id: cleAppareil,
        etablissementId: etablissementId,
        ficheEleveId: ficheId,
        inscriptionId: inscriptionId,
        montant: 400000,
        datePaiement: DateTime(2026, 10, 6),
        saisiPar: saisiParClientBidon,
        moyenPaiement: MoyenPaiement.mobileMoney,
        referencePaiement: 'TXN-42',
      );

      final encaissementEnregistre =
          await repository.enregistrerEncaissement(encaissementSaisi);

      // Preuve que le corps réellement envoyé contient la clé de l'appareil
      // (un renvoi ne crée jamais de doublon) mais jamais `saisi_par`.
      expect(requeteInterceptee!.url.path, endsWith('/rpc/enregistrer_encaissement_scolarite'));
      final corpsEnvoye = jsonDecode(requeteInterceptee!.body) as Map<String, dynamic>;
      expect(corpsEnvoye['p_id'], cleAppareil);
      expect(corpsEnvoye.keys.any((k) => k.contains('saisi_par')), isFalse);

      // Preuve que l'objet réellement utilisé pour le PDF est celui renvoyé
      // par le serveur (via le vrai `depuisJson` du repository), pas celui
      // saisi côté client.
      expect(encaissementEnregistre.id, cleAppareil);
      expect(encaissementEnregistre.numeroRecu, 'SCO-2026-000001');
      expect(encaissementEnregistre.saisiPar, isNot(saisiParClientBidon));
      expect(encaissementEnregistre.saisiPar, 'p-direction-reelle');
      expect(encaissementEnregistre.montant, 400000);

      final fiche = FicheEleve(
        id: ficheId,
        etablissementId: etablissementId,
        matricule: 'GS-00012',
        nom: 'CAMARA',
        prenom: 'Mory',
        dateNaissance: DateTime(2013, 4, 12),
      );
      const etablissement = Etablissement(
        id: etablissementId,
        nom: 'Groupe Scolaire Test',
        slug: 'gs-test',
        ville: 'Conakry',
        deviseCode: 'GNF',
      );

      final octets = await construireRecuPdf(
        encaissement: encaissementEnregistre,
        fiche: fiche,
        etablissement: etablissement,
        variante: AppThemeVariant.francophoneCfa,
      );

      expect(String.fromCharCodes(octets.take(5)), '%PDF-');
      expect(octets.length, greaterThan(500));
    },
  );
}
