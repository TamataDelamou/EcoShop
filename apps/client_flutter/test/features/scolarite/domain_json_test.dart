import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/scolarite/domain/affectation_enseignant.dart';
import 'package:ecoshop_client/features/scolarite/domain/annee_scolaire.dart';
import 'package:ecoshop_client/features/scolarite/domain/classe.dart';
import 'package:ecoshop_client/features/scolarite/domain/encaissement_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/enums_financier_scolaire.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/frais_scolarite_config.dart';
import 'package:ecoshop_client/features/scolarite/domain/inscription.dart';
import 'package:ecoshop_client/features/scolarite/domain/palier_paiement_config.dart';
import 'package:ecoshop_client/features/scolarite/domain/solde_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/structure_etablissement.dart';
import 'package:ecoshop_client/features/scolarite/domain/verifications_reinscription.dart';

void main() {
  group('FicheEleve', () {
    test('depuisJson/versJson font un aller-retour fidèle', () {
      final fiche = FicheEleve(
        id: 'f1',
        etablissementId: 'e1',
        matricule: 'MAT-1',
        nom: 'Camara',
        prenom: 'Mariam',
        dateNaissance: DateTime(2014, 6, 12),
        sexe: 'F',
        estSupervise: true,
      );

      final relue = FicheEleve.depuisJson(fiche.versJson());

      expect(relue.nomComplet, 'Mariam Camara');
      expect(relue.estSupervise, isTrue);
      expect(relue.dateNaissance, DateTime(2014, 6, 12));
    });

    test('champs administratifs (M15quater) font un aller-retour fidèle', () {
      final fiche = FicheEleve(
        id: 'f1',
        etablissementId: 'e1',
        matricule: 'MAT-1',
        nom: 'Camara',
        prenom: 'Mariam',
        dateNaissance: DateTime(2014, 6, 12),
        numeroClasse: 12,
        nomPere: 'Ibrahima Camara',
        nomMere: 'Aissatou Bah',
        quartier: 'Almamya',
        personneUrgenceNom: 'Fatoumata Camara',
        personneUrgenceTelephone: '+224620000001',
        redoublant: true,
      );

      final relue = FicheEleve.depuisJson(fiche.versJson());

      expect(relue.numeroClasse, 12);
      expect(relue.nomPere, 'Ibrahima Camara');
      expect(relue.nomMere, 'Aissatou Bah');
      expect(relue.quartier, 'Almamya');
      expect(relue.personneUrgenceNom, 'Fatoumata Camara');
      expect(relue.personneUrgenceTelephone, '+224620000001');
      expect(relue.redoublant, isTrue);
    });

    test('versJsonMiseAJourAdmin n\'expose jamais matricule/profile_id', () {
      final fiche = FicheEleve(
        id: 'f1',
        etablissementId: 'e1',
        matricule: 'MAT-1',
        nom: 'Camara',
        prenom: 'Mariam',
        dateNaissance: DateTime(2014, 6, 12),
        profileId: 'p1',
        quartier: 'Almamya',
      );

      final payload = fiche.versJsonMiseAJourAdmin();

      expect(payload.containsKey('matricule'), isFalse);
      expect(payload.containsKey('profile_id'), isFalse);
      expect(payload['quartier'], 'Almamya');
    });
  });

  group('Inscription', () {
    test('versJsonCache/depuisJson conservent fiche et classe embarquées', () {
      final classe = const Classe(
        id: 'c1',
        etablissementId: 'e1',
        anneeScolaireId: 'a1',
        code: '6EA',
        nom: '6e A',
      );
      final fiche = FicheEleve(
        id: 'f1',
        etablissementId: 'e1',
        matricule: 'MAT-1',
        nom: 'Bah',
        prenom: 'Sekou',
        dateNaissance: DateTime(2013, 1, 1),
      );
      final inscription = Inscription(
        id: 'i1',
        etablissementId: 'e1',
        ficheEleveId: fiche.id,
        classeId: classe.id,
        anneeScolaireId: 'a1',
        dateInscription: DateTime(2026, 9, 1),
        fiche: fiche,
        classe: classe,
      );

      final relue = Inscription.depuisJson(inscription.versJsonCache());

      expect(relue.fiche?.nomComplet, 'Sekou Bah');
      expect(relue.classe?.nom, '6e A');
    });

    test('statut boursier (M15quater) fait un aller-retour fidèle', () {
      final inscription = Inscription(
        id: 'i1',
        etablissementId: 'e1',
        ficheEleveId: 'f1',
        classeId: 'c1',
        anneeScolaireId: 'a1',
        dateInscription: DateTime(2026, 9, 1),
        boursier: true,
        boursierModifiePar: 'p-direction',
        boursierModifieLe: DateTime(2026, 9, 15, 10, 30),
      );

      final relue = Inscription.depuisJson(inscription.versJsonCache());

      expect(relue.boursier, isTrue);
      expect(relue.boursierModifiePar, 'p-direction');
      expect(relue.boursierModifieLe, DateTime(2026, 9, 15, 10, 30));
    });
  });

  group('EncaissementScolarite', () {
    test('versJsonCreation n\'expose jamais saisi_par/statut (imposés serveur)', () {
      final encaissement = EncaissementScolarite(
        id: 'enc1',
        etablissementId: 'e1',
        ficheEleveId: 'f1',
        inscriptionId: 'i1',
        montant: 250000,
        datePaiement: DateTime(2026, 10, 6),
        saisiPar: 'ignore-moi',
      );

      final payload = encaissement.versJsonCreation();

      expect(payload.containsKey('saisi_par'), isFalse);
      expect(payload.containsKey('statut'), isFalse);
      expect(payload.containsKey('id'), isFalse);
      expect(payload['montant'], 250000);
    });

    test('versJsonCache/depuisJson font un aller-retour fidèle, y compris l\'annulation', () {
      final encaissement = EncaissementScolarite(
        id: 'enc1',
        etablissementId: 'e1',
        ficheEleveId: 'f1',
        inscriptionId: 'i1',
        montant: 250000,
        datePaiement: DateTime(2026, 10, 6),
        saisiPar: 'p-direction',
        typeFrais: TypeFraisScolaire.scolarite,
        moyenPaiement: MoyenPaiement.mobileMoney,
        referencePaiement: 'TXN-001',
        statut: StatutEncaissement.annule,
        motifAnnulation: 'Doublon de saisie',
        annulePar: 'p-direction',
        annuleLe: DateTime(2026, 10, 7, 9),
      );

      final relue = EncaissementScolarite.depuisJson(encaissement.versJsonCache());

      expect(relue.saisiPar, 'p-direction');
      expect(relue.montant, 250000);
      expect(relue.moyenPaiement, MoyenPaiement.mobileMoney);
      expect(relue.referencePaiement, 'TXN-001');
      expect(relue.statut, StatutEncaissement.annule);
      expect(relue.estValide, isFalse);
      expect(relue.motifAnnulation, 'Doublon de saisie');
      expect(relue.annulePar, 'p-direction');
      expect(relue.annuleLe, DateTime(2026, 10, 7, 9));
    });
  });

  group('FraisScolariteConfig', () {
    test('versJsonEcriture/depuisJson font un aller-retour fidèle', () {
      const config = FraisScolariteConfig(
        id: 'fc1',
        etablissementId: 'e1',
        anneeScolaireId: 'a1',
        niveauId: 'n1',
        montantAnnuel: 1200000,
        fraisInscription: 50000,
      );

      final payload = config.versJsonEcriture()..['id'] = config.id;
      final relue = FraisScolariteConfig.depuisJson(payload);

      expect(relue.montantAnnuel, 1200000);
      expect(relue.fraisInscription, 50000);
      expect(relue.estTarifParDefaut, isFalse);
    });

    test('estTarifParDefaut est vrai quand niveauId est absent', () {
      const config = FraisScolariteConfig(
        id: 'fc1',
        etablissementId: 'e1',
        anneeScolaireId: 'a1',
        montantAnnuel: 1000000,
      );

      expect(config.estTarifParDefaut, isTrue);
    });
  });

  group('PalierPaiementConfig', () {
    test('versJsonEcriture/depuisJson font un aller-retour fidèle', () {
      final palier = PalierPaiementConfig(
        id: 'pp1',
        etablissementId: 'e1',
        anneeScolaireId: 'a1',
        nom: 'Tranche 1',
        pourcentage: 40,
        ordre: 1,
        dateLimite: DateTime(2026, 11, 1),
      );

      final payload = palier.versJsonEcriture()..['id'] = palier.id;
      final relue = PalierPaiementConfig.depuisJson(payload);

      expect(relue.nom, 'Tranche 1');
      expect(relue.pourcentage, 40);
      expect(relue.ordre, 1);
      expect(relue.dateLimite, DateTime(2026, 11, 1));
    });
  });

  group('SoldeScolarite', () {
    test('estSolde est vrai quand le solde est nul ou négatif', () {
      const soldePositif = SoldeScolarite(montantDu: 1000000, montantPaye: 400000, solde: 600000);
      const soldeAcquitte = SoldeScolarite(montantDu: 1000000, montantPaye: 1000000, solde: 0);
      const soldeTropPaye = SoldeScolarite(montantDu: 1000000, montantPaye: 1100000, solde: -100000);

      expect(soldePositif.estSolde, isFalse);
      expect(soldeAcquitte.estSolde, isTrue);
      expect(soldeTropPaye.estSolde, isTrue);
    });
  });

  group('VerificationsReinscription', () {
    test('aDesAlertes est vrai si impayé ou sanction active', () {
      const aucune = VerificationsReinscription(impaye: false, sanctionActive: false, boursierPrecedent: true);
      const avecImpaye = VerificationsReinscription(impaye: true, sanctionActive: false, boursierPrecedent: false);

      expect(aucune.aDesAlertes, isFalse);
      expect(avecImpaye.aDesAlertes, isTrue);
    });
  });

  group('AffectationEnseignant', () {
    test('versJsonCache/depuisJsonCache conservent noms et classe', () {
      const affectation = AffectationEnseignant(
        id: 'aff1',
        etablissementId: 'e1',
        anneeScolaireId: 'a1',
        enseignantProfileId: 'p1',
        classeId: 'c1',
        nomEnseignant: 'Fatou Sow',
        nomMatiere: 'Mathématiques',
        classe: Classe(
          id: 'c1',
          etablissementId: 'e1',
          anneeScolaireId: 'a1',
          code: '6EA',
          nom: '6e A',
        ),
      );

      final relue = AffectationEnseignant.depuisJsonCache(affectation.versJsonCache());

      expect(relue.nomEnseignant, 'Fatou Sow');
      expect(relue.nomMatiere, 'Mathématiques');
      expect(relue.classe?.nom, '6e A');
    });
  });

  group('StructureEtablissement', () {
    test('anneeCourante retombe sur la première année si aucune n\'est marquée courante', () {
      final structure = StructureEtablissement(
        unites: const [],
        anneesScolaires: [
          AnneeScolaire(
            id: 'a1',
            etablissementId: 'e1',
            libelle: '2025-2026',
            dateDebut: DateTime(2025, 9, 1),
            dateFin: DateTime(2026, 7, 1),
          ),
          AnneeScolaire(
            id: 'a2',
            etablissementId: 'e1',
            libelle: '2026-2027',
            dateDebut: DateTime(2026, 9, 1),
            dateFin: DateTime(2027, 7, 1),
          ),
        ],
        classes: const [],
        periodes: const [],
      );

      expect(structure.anneeCourante?.id, 'a1');
    });

    test('anneeCourante retient l\'année marquée courante même si elle n\'est pas la première', () {
      final structure = StructureEtablissement(
        unites: const [],
        anneesScolaires: [
          AnneeScolaire(
            id: 'a1',
            etablissementId: 'e1',
            libelle: '2025-2026',
            dateDebut: DateTime(2025, 9, 1),
            dateFin: DateTime(2026, 7, 1),
          ),
          AnneeScolaire(
            id: 'a2',
            etablissementId: 'e1',
            libelle: '2026-2027',
            dateDebut: DateTime(2026, 9, 1),
            dateFin: DateTime(2027, 7, 1),
            courante: true,
          ),
        ],
        classes: const [],
        periodes: const [],
      );

      expect(structure.anneeCourante?.id, 'a2');
    });
  });
}
