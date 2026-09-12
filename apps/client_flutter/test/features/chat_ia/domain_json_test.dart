import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/features/chat_ia/domain/detail_eleve_pseudonymise.dart';
import 'package:ecoshop_client/features/chat_ia/domain/message_chat_ia.dart';
import 'package:ecoshop_client/features/chat_ia/domain/persona_ia.dart';

void main() {
  group('MessageChatIa', () {
    test('depuisJson lit les colonnes réelles de ai_messages', () {
      final message = MessageChatIa.depuisJson({
        'id': 'm1',
        'conversation_id': 'c1',
        'sender': 'assistant',
        'content': 'Bonjour !',
        'created_at': '2026-03-01T00:00:00Z',
      });

      expect(message.estAssistant, isTrue);
      expect(message.content, 'Bonjour !');
    });

    test('estAssistant est faux pour un message utilisateur', () {
      final message = MessageChatIa.depuisJson({
        'id': 'm2',
        'conversation_id': 'c1',
        'sender': 'user',
        'content': 'Bonjour',
        'created_at': '2026-03-01T00:00:00Z',
      });

      expect(message.estAssistant, isFalse);
    });
  });

  group('DetailElevePseudonymise', () {
    test('depuisMapping lit le mapping pseudonyme -> identité sans jamais deviner un champ', () {
      final detail = DetailElevePseudonymise.depuisMapping({
        'Élève A': {'matricule': 'MAT001', 'nom': 'Dupont', 'prenom': 'Jean', 'classeId': 'cl1'},
        'Élève B': {'matricule': 'MAT002', 'nom': 'Martin', 'prenom': 'Alice', 'classeId': null},
      });

      expect(detail, hasLength(2));
      expect(detail.first.pseudonyme, 'Élève A');
      expect(detail.first.matricule, 'MAT001');
      expect(detail.first.prenom, 'Jean');
    });

    test('depuisMapping renvoie une liste vide si le mapping est absent (conversation non groundée)', () {
      expect(DetailElevePseudonymise.depuisMapping(null), isEmpty);
      expect(DetailElevePseudonymise.depuisMapping(const {}), isEmpty);
    });
  });

  group('PersonaIa', () {
    test('depuisRoleRacine ne résout que les 3 rôles couverts par M16', () {
      expect(PersonaIa.depuisRoleRacine(RoleRacine.eleve), PersonaIa.eleve);
      expect(PersonaIa.depuisRoleRacine(RoleRacine.enseignant), PersonaIa.enseignant);
      expect(PersonaIa.depuisRoleRacine(RoleRacine.direction), PersonaIa.direction);
    });

    test('depuisRoleRacine renvoie null pour parent/vendeur/fondateur — pas de persona IA pour eux', () {
      expect(PersonaIa.depuisRoleRacine(RoleRacine.parent), isNull);
      expect(PersonaIa.depuisRoleRacine(RoleRacine.vendeur), isNull);
      expect(PersonaIa.depuisRoleRacine(null), isNull);
    });

    test('libelle correspond exactement à libelleAssistantPour côté serveur', () {
      expect(PersonaIa.eleve.libelle, 'Tuteur-IA');
      expect(PersonaIa.enseignant.libelle, 'Prof-Assistant');
      expect(PersonaIa.direction.libelle, 'Directeur-Adviser');
    });
  });
}
