import 'package:ecoshop_client/core/sync/sync_engine.dart';
import 'package:ecoshop_client/features/coquille/application/sync_composition.dart';
import 'package:ecoshop_client/features/justificatifs/data/justificatifs_repository.dart';
import 'package:ecoshop_client/features/justificatifs/domain/justificatif.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Justificatif (REG-36)', () {
    test('lecture d’une ligne serveur avec le nom de l’élève', () {
      final j = Justificatif.depuisJson({
        'id': 'j1',
        'etablissement_id': 'e1',
        'fiche_eleve_id': 'f1',
        'date_debut': '2026-10-12',
        'date_fin': '2026-10-14',
        'motif': 'rendez_vous_medical',
        'statut': 'refuse',
        'motif_refus': 'Certificat illisible',
        'fiches_eleves': {'prenom': 'Fanta', 'nom': 'CAMARA'},
      });
      expect(j.motif, MotifJustificatif.rendezVousMedical);
      expect(j.statut, StatutJustificatif.refuse);
      expect(j.motifRefus, 'Certificat illisible');
      expect(j.nomEleve, 'Fanta CAMARA');
    });

    test('codes inconnus : repli prudent', () {
      expect(MotifJustificatif.depuisCode('???'), MotifJustificatif.autre);
      expect(StatutJustificatif.depuisCode(null), StatutJustificatif.depose);
    });

    test('la famille n’envoie jamais le statut ni la décision', () {
      final ligne = Justificatif(
        id: 'j2',
        etablissementId: 'e1',
        ficheEleveId: 'f1',
        dateDebut: DateTime(2026, 3, 5),
        dateFin: DateTime(2026, 3, 5),
        motif: MotifJustificatif.maladie,
        commentaire: '  fièvre  ',
      ).versJsonEcriture();
      expect(ligne['date_debut'], '2026-03-05');
      expect(ligne['motif'], 'maladie');
      expect(ligne['commentaire'], 'fièvre');
      expect(ligne.containsKey('statut'), isFalse);
      expect(ligne.containsKey('motif_refus'), isFalse);
    });

    test('libellés lisibles dans l’état de synchronisation', () {
      expect(
        libelleOperation(const SyncEntree(id: 'a', entite: 'justificatif_depot', operation: 'insert', payload: '{}')),
        'Justificatif d’absence',
      );
      expect(
        libelleOperation(const SyncEntree(id: 'b', entite: 'justificatif_decision', operation: 'rpc', payload: '{}')),
        'Décision sur un justificatif',
      );
      expect(JustificatifsRepository.entites, ['justificatif_depot', 'justificatif_decision']);
    });

    test('messages d’erreur en mots simples', () {
      expect(const ErreurJustificatif('PERIODE_INVALIDE').message, contains('60 jours'));
    });
  });
}
