import 'dart:convert';

import 'package:ecoshop_client/core/sync/entites_differees.dart';
import 'package:ecoshop_client/core/sync/sync_engine.dart';
import 'package:ecoshop_client/features/coquille/application/rejeu_actions_differees.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// REG-35 lot 4 — rejeu des opérations faites sans réseau : exactement une
/// fois, jamais d'écrasement d'une décision prise entre-temps, refus visibles.
class _Serveur {
  bool enLigne = true;

  /// Table → id → ligne.
  final tables = <String, Map<String, Map<String, dynamic>>>{};

  /// Réponse d'erreur imposée à la prochaine écriture (code SQL, message).
  (String, String)? erreur;

  SupabaseClient client() => SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit),
        httpClient: MockClient((requete) async {
          if (!enLigne) throw http.ClientException('Failed host lookup');
          final table = requete.url.pathSegments.last;
          final lignes = tables.putIfAbsent(table, () => {});
          final q = requete.url.queryParameters;
          String? valeur(String col, String op) {
            final v = q[col];
            return v != null && v.startsWith('$op.') ? v.substring(op.length + 1) : null;
          }

          http.Response json(Object? corps, [int statut = 200]) => http.Response(jsonEncode(corps), statut,
              headers: {'content-type': 'application/json'}, request: requete);

          if (requete.method != 'GET' && erreur != null) {
            final (code, message) = erreur!;
            erreur = null;
            return json({'code': code, 'message': message, 'details': null, 'hint': null}, code == '42501' ? 403 : 409);
          }

          switch (requete.method) {
            case 'POST':
              final ligne = (jsonDecode(requete.body) as Map).cast<String, dynamic>();
              if (lignes.containsKey(ligne['id'])) {
                return json({'code': '23505', 'message': 'duplicate key value', 'details': null, 'hint': null}, 409);
              }
              lignes[ligne['id'] as String] = ligne;
              return json(null, 201);
            case 'PATCH':
              final id = valeur('id', 'eq')!;
              final ligne = lignes[id];
              final dans = valeur('statut', 'in');
              final permis = dans == null ||
                  dans.replaceAll(RegExp(r'[()"]'), '').split(',').contains(ligne?['statut']);
              final vide = q.containsKey('publie_le') || q.containsKey('validee_le');
              final nulOk = !vide || (ligne != null && ligne[q.containsKey('publie_le') ? 'publie_le' : 'validee_le'] == null);
              if (ligne != null && permis && nulOk) {
                ligne.addAll((jsonDecode(requete.body) as Map).cast<String, dynamic>());
                return json([
                  {'id': id},
                ]);
              }
              return json(<Object>[]);
            case 'DELETE':
              lignes.remove(valeur('id', 'eq'));
              return json(null, 204);
            case 'GET':
              final ligne = lignes[valeur('id', 'eq')];
              return ligne == null ? json(<Object>[]) : json(ligne);
          }
          return json(null, 400);
        }),
      );
}

SyncEntree _entree(String entite, Map<String, dynamic> corps) => SyncEntree(
      id: EntitesDifferees.identifiant(entite, corps['id'] as String),
      entite: entite,
      operation: 'update',
      payload: jsonEncode(corps),
    );

void main() {
  late _Serveur serveur;
  late RejeuActionsDifferees rejeu;

  setUp(() {
    serveur = _Serveur();
    rejeu = RejeuActionsDifferees(serveur.client());
  });

  group('création : exactement une fois', () {
    test('rejouée deux fois, l\'évaluation n\'est créée qu\'une fois', () async {
      final e = _entree(EntitesDifferees.evaluationCreation, {'id': 'ev1', 'libelle': 'Devoir 1'});
      await rejeu.rejouer(e);
      await rejeu.rejouer(e); // réponse perdue puis rejeu : 23505 = déjà fait
      expect(serveur.tables['evaluations']!.length, 1);
    });

    test('une sanction proposée sans réseau garde son identifiant', () async {
      await rejeu.rejouer(_entree(EntitesDifferees.sanctionProposition, {'id': 's1', 'statut': 'proposee'}));
      expect(serveur.tables['sanctions']!.keys, ['s1']);
    });
  });

  group('décision : jamais d\'écrasement silencieux', () {
    setUp(() {
      serveur.tables['conges'] = {
        'c1': {'id': 'c1', 'statut': 'demande'},
      };
    });

    Map<String, dynamic> decision(String statut) =>
        {'id': 'c1', 'statut': statut, 'valide_par': 'dir', 'date_validation': '2026-10-30T09:00:00Z'};

    test('appliquée si le congé est encore demandé', () async {
      await rejeu.rejouer(_entree(EntitesDifferees.congeDecision, decision('valide')));
      expect(serveur.tables['conges']!['c1']!['statut'], 'valide');
    });

    test('déjà refusé par quelqu\'un d\'autre : refus visible, rien d\'écrasé', () async {
      serveur.tables['conges']!['c1']!['statut'] = 'refuse';
      await expectLater(
        rejeu.rejouer(_entree(EntitesDifferees.congeDecision, decision('valide'))),
        throwsA(isA<RejetDefinitif>().having((r) => r.code, 'code', 'CONGE_DEJA_TRAITE')),
      );
      expect(serveur.tables['conges']!['c1']!['statut'], 'refuse');
    });

    test('même décision déjà prise : rien à faire', () async {
      serveur.tables['conges']!['c1']!['statut'] = 'valide';
      await rejeu.rejouer(_entree(EntitesDifferees.congeDecision, decision('valide')));
    });

    test('sanction : « exécutée » seulement depuis « notifiée »', () async {
      serveur.tables['sanctions'] = {
        's1': {'id': 's1', 'statut': 'annulee'},
      };
      await expectLater(
        rejeu.rejouer(_entree(EntitesDifferees.sanctionStatut, {'id': 's1', 'statut': 'executee'})),
        throwsA(isA<RejetDefinitif>().having((r) => r.code, 'code', 'SANCTION_DEJA_TRAITEE')),
      );
    });
  });

  group('refus et pannes', () {
    test('droits retirés : refus définitif, montré à l\'utilisateur', () async {
      serveur.erreur = ('42501', 'new row violates row-level security policy');
      await expectLater(
        rejeu.rejouer(_entree(EntitesDifferees.inscriptionBoursier, {'id': 'i1', 'boursier': true})),
        throwsA(isA<RejetDefinitif>().having((r) => r.code, 'code', 'PERMISSION_REFUSEE')),
      );
    });

    test('panne de réseau : pas un refus, l\'opération sera retentée', () async {
      serveur.enLigne = false;
      await expectLater(
        rejeu.rejouer(_entree(EntitesDifferees.progressionStatut, {'id': 'p1', 'statut': 'realisee'})),
        throwsA(isNot(isA<RejetDefinitif>())),
      );
    });

    test('chaque opération a un libellé lisible dans le journal des refus', () {
      for (final entite in RejeuActionsDifferees.entites) {
        expect(RejeuActionsDifferees.libelle(_entree(entite, {'id': 'x'})), isNot('Opération'));
      }
    });
  });
}
