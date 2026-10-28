import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../annonces/presentation/ecran_annonces.dart';
import '../../annonces/presentation/ecran_annonces_direction.dart';
import '../../appareil/presentation/ecran_debloquer_code.dart';
import '../../auth/presentation/ecran_telephones_a_confirmer.dart';
import '../../bibliotheque/presentation/ecran_bibliotheque.dart';
import '../../bibliotheque/presentation/ecran_bibliotheque_famille.dart';
import '../../cahier_liaison/presentation/ecran_eleves_liaison.dart';
import '../../chat_ia/domain/persona_ia.dart';
import '../../chat_ia/presentation/ecran_chat_ia.dart';
import '../../communication/presentation/ecran_tableau_bord_communication.dart';
import '../../configuration/presentation/ecran_affectations.dart';
import '../../configuration/presentation/ecran_annees_scolaires.dart';
import '../../configuration/presentation/ecran_classes_configuration.dart';
import '../../configuration/presentation/ecran_configuration_etablissement.dart';
import '../../configuration/presentation/ecran_emploi_du_temps_automatique.dart';
import '../../configuration/presentation/ecran_groupes.dart';
import '../../configuration/presentation/ecran_programme_etablissement.dart';
import '../../configuration/presentation/ecran_salles_configuration.dart';
import '../../comptabilite/presentation/ecran_comptabilite.dart';
import '../../creation_etablissement/presentation/ecran_demande_etablissement.dart';
import '../../creation_etablissement/presentation/ecran_validation_etablissements_gsg.dart';
import '../../ecoles_gsg/presentation/ecran_ecoles_gsg.dart';
import '../../inscription_en_ligne/presentation/ecran_campagne_inscription.dart';
import '../../inscription_en_ligne/presentation/ecran_inscriptions_famille.dart';
import '../../invitations/presentation/ecran_invitations_etablissement.dart';
import '../../liaisons_comptes/presentation/ecran_liaisons_comptes.dart';
import '../../marketplace/presentation/ecran_marketplace.dart';
import '../../notes/presentation/ecran_carnet_notes.dart';
import '../../notes/presentation/ecran_evaluations_classe.dart';
import '../../paiement_mobile/presentation/ecran_orange_money_etablissement.dart';
import '../../parent_ia/presentation/ecran_parent_ia_activation.dart';
import '../../parent_ia/presentation/ecran_parent_ia_historique.dart';
import '../../planification/presentation/ecran_agenda_evenements.dart';
import '../../planification/presentation/ecran_choix_classe.dart';
import '../../planification/presentation/ecran_conflits_emploi.dart';
import '../../planification/presentation/ecran_emploi_du_temps.dart';
import '../../planification/presentation/ecran_planification_classe.dart';
import '../../planification/presentation/ecran_progression_pedagogique.dart';
import '../../planification/presentation/ecran_salles.dart';
import '../../pointage/presentation/ecran_credits_sms.dart';
import '../../pointage/presentation/ecran_credits_sms_gsg.dart';
import '../../pointage/presentation/ecran_portail.dart';
import '../../pointage/presentation/ecran_presence_jour.dart';
import '../../pointage/presentation/ecran_relances_impayes.dart';
import '../../postes/presentation/ecran_postes.dart';
import '../../rapports/presentation/ecran_rapports.dart';
import '../../rapports/presentation/ecran_tableau_bord_rapports.dart';
import '../../referentiel/presentation/ecran_pays_pedagogiques.dart';
import '../../reseau/presentation/ecran_mes_reseaux.dart';
import '../../reseau/presentation/ecran_reseaux_gsg.dart';
import '../../rh_personnel/application/rh_providers.dart';
import '../../rh_personnel/presentation/ecran_annuaire_personnel.dart';
import '../../rh_personnel/presentation/ecran_fiche_employe.dart';
import '../../rh_personnel/presentation/ecran_tableau_bord_rh.dart';
import '../../scan_exercice/presentation/ecran_scan_exercice.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/presentation/ecran_cahier_encaissements.dart';
import '../../scolarite/presentation/ecran_creation_inscription.dart';
import '../../scolarite/presentation/ecran_fiche_eleve.dart';
import '../../scolarite/presentation/ecran_parametres_financiers.dart';
import '../../scolarite/presentation/ecran_reinscription.dart';
import '../../scolarite/presentation/ecran_scolarite.dart';
import '../../scolarite/presentation/ecran_structure_etablissement.dart';
import '../../themes/presentation/ecran_identite_visuelle.dart';
import '../../transport/presentation/ecran_suivi_transport.dart';
import '../../transport/presentation/ecran_transport_chauffeur.dart';
import '../../transport/presentation/ecran_transport_direction.dart';
import '../../validation_marketplace/presentation/ecran_agrement_vendeurs_etablissement.dart';
import '../../validation_marketplace/presentation/ecran_validation_vendeurs_gsg.dart';
import '../../vie_scolaire/presentation/ecran_alertes_decrochage.dart';
import '../../vie_scolaire/presentation/ecran_appel_classe.dart';
import 'fonction.dart';

void _aller(BuildContext context, Widget ecran) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));

void _choisirClasse(BuildContext context, String titre, Widget Function(dynamic classe) suite) => _aller(
  context,
  EcranChoixClasse(titre: titre, onSelectionner: (ctx, classe) => _aller(ctx, suite(classe))),
);

Future<void> _emploiFiche(BuildContext context, WidgetRef ref, String ficheId, String titre) async {
  final inscriptions = await ref.read(inscriptionsDeFicheProvider(ficheId).future);
  if (inscriptions.isEmpty || !context.mounted) return;
  final i = inscriptions.first;
  _aller(context, EcranPlanificationClasse(classeId: i.classeId, anneeId: i.anneeScolaireId, titre: titre));
}

Future<void> _dossierRh(BuildContext context, WidgetRef ref, ContexteAccueil c) async {
  final employe = await ref.read(monEmployeProvider(c.profil.id).future);
  if (!context.mounted) return;
  if (employe == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun dossier RH associé à ce compte.')));
    return;
  }
  _aller(context, EcranFicheEmploye(employe: employe));
}

const _vie = 'Vie de l’école';
const _eleves = 'Élèves';
const _finances = 'Finances';
const _personnel = 'Personnel';
const _organisation = 'Organisation';
const _etablissement = 'Établissement';
const _tout = 'Tout EcoShop';
const _plateforme = 'Plateforme GSG';

bool _familleAvecFiche(ContexteAccueil c) => (c.parent || c.eleve) && c.fiche != null;

/// Toutes les fonctions, dans l'ordre des maquettes (REG-21). Chaque
/// condition reprend celle de l'ancienne entrée de « Mon profil ».
final List<Fonction> catalogueFonctions = [
  // ---------------------------------------------------------------- familles
  Fonction(
    id: 'annonces', libelle: 'Annonces', icone: Icons.campaign_outlined, teinte: Teinte.orange, groupe: _vie,
    motsCles: ['message', 'information', 'circulaire', 'publier'], badge: 'annonces_non_lues', libelleBadge: 'nouvelle',
    ancienne: 'Annonces de l’école',
    visible: (c) => c.role != RoleRacine.adminGsg && c.role != RoleRacine.adminContenu,
    ouvrir: (context, ref, c) => _aller(context,
        // Direction, ou poste qui publie les annonces (REG-26).
        c.ecole && c.peut(['communication.annonce.publier'])
            ? EcranAnnoncesDirection(etablissementId: c.etablissement!.id)
            : const EcranAnnonces()),
  ),
  Fonction(
    id: 'cahier_liaison', libelle: 'Cahier de liaison', icone: Icons.menu_book_outlined, teinte: Teinte.violet,
    groupe: _vie, motsCles: ['mot', 'parents', 'écrire', 'signer'], badge: 'cahier_non_lu', libelleBadge: 'nouveau mot',
    ancienne: 'Cahier de liaison',
    visible: (c) => c.parent || (c.ecole && (c.enseignant || c.peut(['scolarite.liaison.ecrire']))),
    ouvrir: (context, ref, c) => _aller(context,
        c.parent ? const EcranElevesLiaison() : EcranElevesLiaison(etablissementId: c.etablissement!.id, direction: c.direction)),
  ),
  Fonction(
    id: 'emploi_du_temps', libelle: 'Emploi du temps', icone: Icons.calendar_view_week_outlined, teinte: Teinte.bleu,
    groupe: _tout, motsCles: ['cours', 'horaire', 'semaine'],
    ancienne: 'Emploi du temps de mon enfant / Mon emploi du temps',
    visible: (c) => _familleAvecFiche(c) || (c.enseignant && c.ecole && c.anneeId != null),
    ouvrir: (context, ref, c) {
      if (c.enseignant) {
        _aller(context, EcranEmploiEnseignant(
            enseignantProfileId: c.profil.id, etablissementId: c.etablissement!.id, anneeId: c.anneeId!));
      } else {
        _emploiFiche(context, ref, c.fiche!.id, c.fiche!.nomComplet);
      }
    },
  ),
  Fonction(
    id: 'notes_bulletins', libelle: 'Notes et bulletins', icone: Icons.grade_outlined, teinte: Teinte.vert,
    groupe: _tout, motsCles: ['note', 'bulletin', 'moyenne', 'résultats'], badge: 'nouvelles_notes', libelleBadge: 'nouvelle note',
    ancienne: 'onglet Scolarité › Notes & bulletins',
    visible: _familleAvecFiche,
    ouvrir: (context, ref, c) => _aller(context, EcranCarnetNotes(fiche: c.fiche!)),
  ),
  Fonction(
    id: 'scolarite', libelle: 'Scolarité', icone: Icons.school_outlined, teinte: Teinte.sarcelle, groupe: _tout,
    motsCles: ['fiche', 'paiement', 'solde', 'vie scolaire', 'absences'], badge: 'tranches_a_payer',
    libelleBadge: 'tranche à payer', ancienne: 'onglet Scolarité',
    visible: _familleAvecFiche,
    ouvrir: (context, ref, c) => _aller(context, EcranFicheEleve(fiche: c.fiche!)),
  ),
  Fonction(
    id: 'bus', libelle: 'Bus', icone: Icons.directions_bus_outlined, teinte: Teinte.jaune, groupe: _tout,
    motsCles: ['transport', 'car', 'ramassage'], ancienne: 'Bus de (enfant)',
    visible: _familleAvecFiche,
    ouvrir: (context, ref, c) =>
        _aller(context, EcranSuiviTransport(ficheEleveId: c.fiche!.id, prenom: c.fiche!.prenom)),
  ),
  Fonction(
    id: 'scan_exercice', libelle: 'Scan-Exercice', icone: Icons.document_scanner_outlined, teinte: Teinte.violet,
    groupe: _tout, motsCles: ['exercice', 'photo', 'aide', 'devoir'], ancienne: 'Scan-Exercice',
    visible: (c) => c.eleve && c.maFiche != null && c.ecole,
    ouvrir: (context, ref, c) =>
        _aller(context, EcranScanExercice(etablissementId: c.etablissement!.id, ficheEleveId: c.maFiche!.id)),
  ),
  Fonction(
    id: 'parent_ia', libelle: 'Parent IA', icone: Icons.phonelink_lock_outlined, teinte: Teinte.rose, groupe: _tout,
    motsCles: ['écran', 'limite', 'temps'], ancienne: 'PARENT IA',
    visible: _familleAvecFiche,
    ouvrir: (context, ref, c) => _aller(context, c.eleve
        ? EcranParentIaActivation(ficheEleveId: c.fiche!.id)
        : EcranParentIaHistorique(ficheEleveId: c.fiche!.id, nomEleve: c.fiche!.nomComplet)),
  ),
  Fonction(
    id: 'inscriptions_famille', libelle: 'Inscriptions', icone: Icons.how_to_reg_outlined, teinte: Teinte.bleu,
    groupe: _tout, motsCles: ['réinscription', 'dossier', 'inscrire'], ancienne: 'Inscriptions et réinscriptions',
    visible: (c) => c.parent || c.eleve,
    ouvrir: (context, ref, c) => _aller(context, const EcranInscriptionsFamille()),
  ),
  Fonction(
    id: 'bibliotheque_famille', libelle: 'Bibliothèque', icone: Icons.local_library_outlined, teinte: Teinte.sarcelle,
    groupe: _tout, motsCles: ['livre', 'emprunt', 'prêt'], badge: 'livres_a_rendre', libelleBadge: 'livre à rendre',
    ancienne: 'Bibliothèque (famille)',
    visible: _familleAvecFiche,
    ouvrir: (context, ref, c) => _aller(context, EcranBibliothequeFamille(
        etablissementId: c.fiche!.etablissementId, ficheEleveId: c.fiche!.id, prenom: c.fiche!.prenom)),
  ),
  Fonction(
    id: 'mes_rapports', libelle: 'Mes rapports', icone: Icons.summarize_outlined, teinte: Teinte.gris, groupe: _tout,
    motsCles: ['bulletin', 'relevé', 'télécharger', 'pdf'], ancienne: 'Rapports de mon enfant / Mes rapports',
    visible: _familleAvecFiche,
    ouvrir: (context, ref, c) => _aller(context, EcranMesRapports(ficheEleveId: c.fiche!.id)),
  ),
  // ---------------------------------------------------------------- enseignants
  Fonction(
    id: 'faire_appel', libelle: 'Faire l’appel', icone: Icons.fact_check_outlined, teinte: Teinte.vert, groupe: _vie,
    motsCles: ['présence', 'absence', 'appel', 'retard'], badge: 'appels_a_faire', libelleBadge: 'appel à faire',
    ancienne: '(nouveau raccourci : classe › appel)',
    visible: (c) => c.enseignant && c.ecole,
    ouvrir: (context, ref, c) => _choisirClasse(context, 'Faire l’appel', (classe) => EcranAppelClasse(classe: classe)),
  ),
  Fonction(
    id: 'notes_enseignant', libelle: 'Notes', icone: Icons.grade_outlined, teinte: Teinte.bleu, groupe: _vie,
    motsCles: ['évaluation', 'devoir', 'saisir', 'contrôle'], badge: 'notes_a_saisir', libelleBadge: 'évaluation à compléter',
    ancienne: '(nouveau raccourci : classe › évaluations)',
    visible: (c) => c.enseignant && c.ecole,
    ouvrir: (context, ref, c) =>
        _choisirClasse(context, 'Notes', (classe) => EcranEvaluationsClasse(classe: classe)),
  ),
  Fonction(
    id: 'mes_classes', libelle: 'Mes classes', icone: Icons.class_outlined, teinte: Teinte.sarcelle, groupe: _vie,
    motsCles: ['classe', 'élèves'], ancienne: 'onglet Scolarité (enseignant)',
    visible: (c) => c.enseignant,
    ouvrir: (context, ref, c) => _aller(context,
        Scaffold(appBar: AppBar(title: const Text('Mes classes')), body: EcranScolarite(profil: c.profil))),
  ),
  Fonction(
    id: 'progression', libelle: 'Progression', icone: Icons.timeline_outlined, teinte: Teinte.violet, groupe: _vie,
    motsCles: ['programme', 'chapitre', 'avancement'], ancienne: 'Classes — emploi du temps & progression',
    visible: (c) => c.enseignant && c.ecole && c.anneeId != null,
    ouvrir: (context, ref, c) => _choisirClasse(context, 'Progression', (classe) => EcranProgressionPedagogique(
        etablissementId: c.etablissement!.id, classeId: classe.id as String, anneeId: c.anneeId!)),
  ),
  // ---------------------------------------------------------------- vie de l'école
  Fonction(
    id: 'presence_portail', libelle: 'Présence au portail', icone: Icons.fact_check_outlined, teinte: Teinte.vert,
    groupe: _vie, motsCles: ['arrivée', 'absents', 'retards', 'cartes', 'imprimer'], ancienne: 'Présence au portail',
    visible: (c) => c.ecole && c.peut(['scolarite.presence.gerer']),
    ouvrir: (context, ref, c) => _aller(context, EcranPresenceJour(etablissement: c.etablissement!)),
  ),
  Fonction(
    id: 'portail_scanner', libelle: 'Scanner au portail', icone: Icons.qr_code_scanner, teinte: Teinte.gris, groupe: _vie,
    motsCles: ['carte', 'qr', 'entrée', 'scanner'], ancienne: 'Portail : scanner les cartes',
    visible: (c) => c.ecole && (c.enseignant || c.peut(['portail.scanner', 'scolarite.presence.gerer'])),
    ouvrir: (context, ref, c) => _aller(context, EcranPortail(etablissementId: c.etablissement!.id)),
  ),
  Fonction(
    id: 'alertes_decrochage', libelle: 'Alertes décrochage', icone: Icons.warning_amber_outlined, teinte: Teinte.rose,
    groupe: _vie, motsCles: ['risque', 'décrochage', 'abandon'], badge: 'alertes_ouvertes', libelleBadge: 'alerte',
    ancienne: 'Alertes de décrochage',
    visible: (c) => c.ecole && c.direction,
    ouvrir: (context, ref, c) => _aller(context, EcranAlertesDecrochage(etablissementId: c.etablissement!.id)),
  ),
  Fonction(
    id: 'communication', libelle: 'Lecture des messages', icone: Icons.insights_outlined, teinte: Teinte.orange,
    groupe: _vie, motsCles: ['communication', 'modèles', 'statistiques'], ancienne: 'Tableau de bord communication',
    visible: (c) => c.ecole && c.direction,
    ouvrir: (context, ref, c) => _aller(context, EcranTableauBordCommunication(etablissementId: c.etablissement!.id)),
  ),
  // ---------------------------------------------------------------- élèves
  Fonction(
    id: 'inscriptions_en_ligne', libelle: 'Inscriptions en ligne', icone: Icons.how_to_reg_outlined, teinte: Teinte.bleu,
    groupe: _eleves, motsCles: ['campagne', 'dossier', 'places'], badge: 'dossiers_inscription', libelleBadge: 'dossier',
    ancienne: 'Inscriptions en ligne',
    visible: (c) => c.ecole && c.peut(['scolarite.inscription.gerer']),
    ouvrir: (context, ref, c) => _aller(context,
        EcranCampagneInscription(etablissementId: c.etablissement!.id, devise: c.etablissement!.deviseCode)),
  ),
  Fonction(
    id: 'nouvelle_inscription', libelle: 'Nouvelle inscription', icone: Icons.person_add_alt_1_outlined,
    teinte: Teinte.vert, groupe: _eleves, motsCles: ['inscrire', 'élève', 'fiche'], ancienne: 'Nouvelle inscription',
    visible: (c) => c.direction,
    ouvrir: (context, ref, c) => _aller(context, const EcranCreationInscription()),
  ),
  Fonction(
    id: 'reinscription', libelle: 'Réinscription', icone: Icons.autorenew_outlined, teinte: Teinte.sarcelle,
    groupe: _eleves, motsCles: ['réinscrire', 'année suivante'], ancienne: 'Réinscription',
    visible: (c) => c.direction,
    ouvrir: (context, ref, c) => _aller(context, const EcranReinscription()),
  ),
  Fonction(
    id: 'comptes_lies', libelle: 'Comptes liés', icone: Icons.link_outlined, teinte: Teinte.violet, groupe: _eleves,
    motsCles: ['liaison', 'parent', 'demande', 'valider'], badge: 'liaisons_a_valider', libelleBadge: 'demande',
    ancienne: 'Comptes liés aux élèves',
    visible: (c) => c.ecole && c.direction,
    ouvrir: (context, ref, c) => _aller(context, EcranLiaisonsComptes(etablissementId: c.etablissement!.id)),
  ),
  // ---------------------------------------------------------------- finances
  Fonction(
    id: 'encaissements', libelle: 'Encaissements', icone: Icons.receipt_long_outlined, teinte: Teinte.vert,
    groupe: _finances, motsCles: ['reçu', 'caisse', 'paiement', 'scolarité', 'encaisser'],
    ancienne: 'Cahier des encaissements',
    visible: (c) => c.ecole && c.peut(['scolarite.encaissement.gerer', 'scolarite.encaissement.lire']),
    ouvrir: (context, ref, c) => _aller(context, EcranCahierEncaissements(etablissementId: c.etablissement!.id)),
  ),
  Fonction(
    id: 'relances', libelle: 'Relances', icone: Icons.campaign_outlined, teinte: Teinte.orange, groupe: _finances,
    motsCles: ['impayés', 'retard', 'rappel', 'sms'], badge: 'familles_en_retard', libelleBadge: 'famille en retard',
    ancienne: 'Relancer les impayés',
    visible: (c) => c.ecole && c.direction,
    ouvrir: (context, ref, c) => _aller(context,
        EcranRelancesImpayes(etablissementId: c.etablissement!.id, devise: c.etablissement!.deviseCode)),
  ),
  Fonction(
    id: 'comptabilite', libelle: 'Comptabilité', icone: Icons.calculate_outlined, teinte: Teinte.bleu, groupe: _finances,
    motsCles: ['journal', 'grand livre', 'balance', 'pièce', 'clôture'], ancienne: 'Comptabilité',
    visible: (c) => c.ecole && c.peut(['comptabilite.lire']),
    ouvrir: (context, ref, c) => _aller(context,
        EcranComptabilite(etablissementId: c.etablissement!.id, devise: c.etablissement!.deviseCode)),
  ),
  Fonction(
    id: 'orange_money', libelle: 'Orange Money', icone: Icons.phone_iphone_rounded, teinte: Teinte.orange,
    groupe: _finances, motsCles: ['paiement en ligne', 'mobile money'], ancienne: 'Paiement Orange Money',
    visible: (c) => c.ecole && c.peut(['paiement.mobile.gerer']),
    ouvrir: (context, ref, c) => _aller(context,
        EcranOrangeMoneyEtablissement(etablissementId: c.etablissement!.id, devise: c.etablissement!.deviseCode)),
  ),
  Fonction(
    id: 'parametres_financiers', libelle: 'Paramètres', icone: Icons.request_quote_outlined, teinte: Teinte.gris,
    groupe: _finances, motsCles: ['tarif', 'frais', 'échéance', 'tranche'], ancienne: 'Paramètres financiers',
    visible: (c) => c.ecole && c.direction && c.anneeId != null,
    ouvrir: (context, ref, c) => _aller(context,
        EcranParametresFinanciers(etablissementId: c.etablissement!.id, anneeScolaireId: c.anneeId!)),
  ),
  Fonction(
    id: 'credits_sms', libelle: 'Crédits SMS', icone: Icons.sms_outlined, teinte: Teinte.jaune, groupe: _finances,
    motsCles: ['sms', 'pack', 'acheter'], ancienne: '(depuis Présence au portail)',
    visible: (c) => c.ecole && c.peut(['sms.credits.acheter']),
    ouvrir: (context, ref, c) => _aller(context,
        EcranCreditsSms(etablissementId: c.etablissement!.id, devise: c.etablissement!.deviseCode)),
  ),
  Fonction(
    id: 'vendeurs_ecole', libelle: 'Vendeurs', icone: Icons.storefront_outlined, teinte: Teinte.sarcelle,
    groupe: _finances, motsCles: ['marketplace', 'agrément', 'boutique'], ancienne: 'Vendeurs marketplace',
    visible: (c) => c.ecole && c.peut(['boutique.vendeur.agreer']),
    ouvrir: (context, ref, c) =>
        _aller(context, EcranAgrementVendeursEtablissement(etablissementId: c.etablissement!.id)),
  ),
  // ---------------------------------------------------------------- personnel
  Fonction(
    id: 'invitations_personnel', libelle: 'Invitations', icone: Icons.person_add_alt_1_outlined, teinte: Teinte.bleu,
    groupe: _personnel, motsCles: ['inviter', 'enseignant', 'personnel', 'vendeur'], ancienne: 'Invitations du personnel',
    visible: (c) => c.ecole && c.direction,
    ouvrir: (context, ref, c) => _aller(context, EcranInvitationsEtablissement(etablissementId: c.etablissement!.id)),
  ),
  Fonction(
    id: 'personnel_rh', libelle: 'Personnel et RH', icone: Icons.badge_outlined, teinte: Teinte.violet,
    groupe: _personnel, motsCles: ['contrat', 'congé', 'annuaire', 'employé'], ancienne: 'Personnel & RH',
    visible: (c) => c.ecole && c.direction,
    ouvrir: (context, ref, c) => _aller(context, EcranAnnuairePersonnel(etablissementId: c.etablissement!.id)),
  ),
  Fonction(
    id: 'postes', libelle: 'Postes', icone: Icons.admin_panel_settings_outlined, teinte: Teinte.gris, groupe: _personnel,
    motsCles: ['poste', 'droits', 'rôle', 'caissier', 'secrétaire'], ancienne: 'Personnel et postes',
    visible: (c) => c.ecole && c.direction,
    ouvrir: (context, ref, c) => _aller(context, EcranPersonnel(etablissementId: c.etablissement!.id)),
  ),
  Fonction(
    id: 'tableau_rh', libelle: 'Tableau RH', icone: Icons.insights_outlined, teinte: Teinte.sarcelle, groupe: _personnel,
    motsCles: ['effectifs', 'remplaçant'], ancienne: 'Tableau de bord RH',
    visible: (c) => c.ecole && c.direction,
    ouvrir: (context, ref, c) => _aller(context, EcranTableauBordRh(etablissementId: c.etablissement!.id)),
  ),
  Fonction(
    id: 'numeros_a_confirmer', libelle: 'Numéros à confirmer', icone: Icons.verified_user_outlined,
    teinte: Teinte.orange, groupe: _personnel, motsCles: ['téléphone', 'confirmer', 'numéro'],
    badge: 'numeros_a_confirmer', libelleBadge: 'numéro', ancienne: 'Numéros à confirmer',
    visible: (c) => c.ecole && c.direction,
    ouvrir: (context, ref, c) => _aller(context, EcranTelephonesAConfirmer(etablissementId: c.etablissement!.id)),
  ),
  Fonction(
    id: 'debloquer_code', libelle: 'Débloquer un code', icone: Icons.lock_open_outlined, teinte: Teinte.rose,
    groupe: _personnel, motsCles: ['code oublié', 'bloqué', 'déblocage'], ancienne: 'Débloquer le code d’une personne',
    visible: (c) => c.ecole && c.peut(['securite.code.debloquer']),
    ouvrir: (context, ref, c) => _aller(context, EcranDebloquerCode(etablissementId: c.etablissement!.id)),
  ),
  Fonction(
    id: 'dossier_rh', libelle: 'Mon dossier RH', icone: Icons.folder_shared_outlined, teinte: Teinte.gris,
    groupe: _personnel, motsCles: ['contrat', 'congé', 'paie'], ancienne: 'Mon dossier RH',
    visible: (c) => c.enseignant || c.direction || c.personnel,
    ouvrir: _dossierRh,
  ),
  // ---------------------------------------------------------------- organisation
  // Mise en route (REG-23) : chaque étape a aussi sa pastille.
  Fonction(
    id: 'annees_scolaires', libelle: 'Années scolaires', icone: Icons.event_note_outlined, teinte: Teinte.vert,
    groupe: _organisation, motsCles: ['année', 'rentrée', 'trimestre', 'semestre', 'période', 'créer'],
    visible: (c) => c.ecole && c.peut(['etablissement.annee.gerer']),
    ouvrir: (context, ref, c) => _aller(context, EcranAnneesScolaires(etablissement: c.etablissement!)),
  ),
  Fonction(
    id: 'classes_config', libelle: 'Classes', icone: Icons.class_outlined, teinte: Teinte.sarcelle,
    groupe: _organisation, motsCles: ['classe', 'créer', 'niveau', 'série', 'section'],
    visible: (c) => c.ecole && c.anneeId != null && c.peut(['scolarite.classe.gerer']),
    ouvrir: (context, ref, c) => _aller(context, EcranClassesConfiguration(etablissement: c.etablissement!, anneeId: c.anneeId!)),
  ),
  Fonction(
    id: 'groupes', libelle: 'Groupes', icone: Icons.groups_2_outlined, teinte: Teinte.violet,
    groupe: _organisation, motsCles: ['groupe', 'demi-classe', 'langue', 'option', 'TP'],
    visible: (c) => c.ecole && c.anneeId != null && c.peut(['scolarite.classe.gerer']),
    ouvrir: (context, ref, c) => _aller(context, EcranGroupes(etablissement: c.etablissement!, anneeId: c.anneeId!)),
  ),
  Fonction(
    id: 'cours_enseignants', libelle: 'Cours et enseignants', icone: Icons.co_present_outlined, teinte: Teinte.orange,
    groupe: _organisation, motsCles: ['affectation', 'matière', 'enseignant', 'heures', 'volume'],
    visible: (c) => c.ecole && c.anneeId != null && c.peut(['rh.enseignant.affecter']),
    ouvrir: (context, ref, c) => _aller(context, EcranAffectations(etablissement: c.etablissement!, anneeId: c.anneeId!)),
  ),
  Fonction(
    id: 'emploi_automatique', libelle: 'Emploi du temps automatique', icone: Icons.auto_awesome_outlined,
    teinte: Teinte.bleu, groupe: _organisation,
    motsCles: ['emploi du temps', 'horaire', 'générer', 'calculer', 'grille', 'indisponibilité'],
    visible: (c) => c.ecole && c.anneeId != null && c.peut(['planification.generer']),
    ouvrir: (context, ref, c) =>
        _aller(context, EcranEmploiDuTempsAutomatique(etablissement: c.etablissement!, anneeId: c.anneeId!)),
  ),
  Fonction(
    id: 'programme_ecole', libelle: 'Programme officiel', icone: Icons.menu_book_outlined, teinte: Teinte.gris,
    groupe: _organisation, motsCles: ['programme', 'matière', 'coefficient', 'référentiel', 'curriculum'],
    visible: (c) => c.ecole && (c.direction || c.enseignant || c.personnel),
    ouvrir: (context, ref, c) => _aller(context, EcranProgrammeEtablissement(etablissement: c.etablissement!)),
  ),
  Fonction(
    id: 'classes_emploi', libelle: 'Classes et emploi du temps', icone: Icons.class_outlined, teinte: Teinte.bleu,
    groupe: _organisation, motsCles: ['classe', 'horaire', 'progression'], ancienne: 'Classes — emploi du temps & progression',
    visible: (c) => c.direction && c.ecole && c.anneeId != null,
    ouvrir: (context, ref, c) => _choisirClasse(context, 'Choisir une classe', (classe) => EcranPlanificationClasse(
        classeId: classe.id as String, anneeId: c.anneeId!, titre: classe.nom as String,
        etablissementId: c.etablissement!.id, peutVoirProgression: true)),
  ),
  Fonction(
    id: 'salles', libelle: 'Salles', icone: Icons.meeting_room_outlined, teinte: Teinte.gris, groupe: _organisation,
    motsCles: ['salle', 'occupation'], ancienne: 'Salles',
    visible: (c) => (c.direction || c.enseignant) && c.ecole && c.anneeId != null,
    // Direction : ajouter, modifier les salles (REG-23) ; enseignant : occupation.
    ouvrir: (context, ref, c) => _aller(context, c.direction
        ? EcranSallesConfiguration(etablissement: c.etablissement!)
        : EcranSalles(etablissementId: c.etablissement!.id, anneeId: c.anneeId!)),
  ),
  Fonction(
    id: 'agenda_ecole', libelle: 'Agenda de l’école', icone: Icons.event_outlined, teinte: Teinte.orange,
    groupe: _organisation, motsCles: ['événement', 'réunion', 'examen'], ancienne: 'Agenda de l’établissement',
    visible: (c) => (c.direction || c.enseignant) && c.ecole && c.anneeId != null,
    ouvrir: (context, ref, c) => _aller(context, EcranAgendaEvenements(
        etablissementId: c.etablissement!.id, anneeId: c.anneeId!, peutCreer: c.direction)),
  ),
  Fonction(
    id: 'conflits', libelle: 'Conflits d’occupation', icone: Icons.rule_outlined, teinte: Teinte.rose,
    groupe: _organisation, motsCles: ['double réservation', 'conflit'], ancienne: 'Conflits d’occupation',
    visible: (c) => c.direction && c.ecole && c.anneeId != null,
    ouvrir: (context, ref, c) =>
        _aller(context, EcranConflitsEmploi(etablissementId: c.etablissement!.id, anneeId: c.anneeId!)),
  ),
  Fonction(
    id: 'bibliotheque', libelle: 'Bibliothèque', icone: Icons.local_library_outlined, teinte: Teinte.sarcelle,
    groupe: _organisation, motsCles: ['livre', 'prêt', 'retour', 'catalogue'], ancienne: 'Bibliothèque (gestion)',
    visible: (c) => c.ecole && c.peut(['bibliotheque.gerer']),
    ouvrir: (context, ref, c) => _aller(context, EcranBibliotheque(etablissement: c.etablissement!)),
  ),
  Fonction(
    id: 'transport', libelle: 'Transport', icone: Icons.directions_bus_outlined, teinte: Teinte.jaune,
    groupe: _organisation, motsCles: ['circuit', 'arrêt', 'chauffeur', 'bus'], ancienne: 'Transport scolaire',
    visible: (c) => c.ecole && c.peut(['transport.gerer']),
    ouvrir: (context, ref, c) => _aller(context,
        EcranTransportDirection(etablissementId: c.etablissement!.id, devise: c.etablissement!.deviseCode)),
  ),
  Fonction(
    id: 'conduire_circuit', libelle: 'Conduire mon circuit', icone: Icons.airport_shuttle_outlined,
    teinte: Teinte.jaune, groupe: _organisation, motsCles: ['trajet', 'bus', 'scanner'], ancienne: 'Conduire mon circuit',
    visible: (c) => c.chauffeur,
    ouvrir: (context, ref, c) => _aller(context, const EcranTransportChauffeur()),
  ),
  Fonction(
    id: 'structures', libelle: 'Structures', icone: Icons.apartment_outlined, teinte: Teinte.gris, groupe: _organisation,
    motsCles: ['campus', 'année', 'période', 'classes', 'annuaire'], ancienne: 'Structures & annuaire (et onglet Scolarité de la direction)',
    visible: (c) => c.direction || c.enseignant,
    ouvrir: (context, ref, c) => _aller(context, const EcranStructureEtablissement()),
  ),
  // ---------------------------------------------------------------- établissement
  Fonction(
    id: 'configuration', libelle: 'Configurer l’école', icone: Icons.checklist_rtl_rounded, teinte: Teinte.vert,
    groupe: _etablissement,
    motsCles: ['configuration', 'mise en route', 'paramétrer', 'année', 'classe', 'frais', 'démarrer'],
    visible: (c) => c.direction && c.ecole,
    ouvrir: (context, ref, c) => _aller(context, EcranConfigurationEtablissement(etablissement: c.etablissement!)),
  ),
  Fonction(
    id: 'identite_visuelle', libelle: 'Identité visuelle', icone: Icons.palette_outlined, teinte: Teinte.violet,
    groupe: _etablissement, motsCles: ['logo', 'couleur', 'slogan', 'devise'], ancienne: 'Identité visuelle',
    visible: (c) => c.direction && c.ecole,
    ouvrir: (context, ref, c) => _aller(context, EcranIdentiteVisuelle(etablissement: c.etablissement!)),
  ),
  Fonction(
    id: 'rapports', libelle: 'Rapports', icone: Icons.query_stats_outlined, teinte: Teinte.bleu, groupe: _etablissement,
    motsCles: ['statistiques', 'indicateurs', 'classes en difficulté'], ancienne: 'Rapports & statistiques',
    visible: (c) => c.ecole && (c.enseignant || c.peut(['rapports.consulter', 'rapports.generer', 'rapports.administrer'])),
    ouvrir: (context, ref, c) => _aller(context, EcranTableauBordRapports(etablissementId: c.etablissement!.id)),
  ),
  Fonction(
    id: 'reseau', libelle: 'Réseau', icone: Icons.hub_outlined, teinte: Teinte.sarcelle, groupe: _etablissement,
    motsCles: ['réseau', 'circulaire', 'écoles'], ancienne: 'Réseau d’établissements',
    visible: (c) => !c.eleve && c.role != RoleRacine.adminGsg && c.role != RoleRacine.fondateurReseau,
    ouvrir: (context, ref, c) => _aller(context, const EcranMesReseaux()),
  ),
  Fonction(
    id: 'ouvrir_etablissement', libelle: 'Ouvrir un établissement', icone: Icons.add_business_outlined,
    teinte: Teinte.vert, groupe: _etablissement, motsCles: ['nouvelle école', 'demande'],
    ancienne: 'Ouvrir un nouvel établissement',
    visible: (c) => c.direction && c.anneeId != null,
    ouvrir: (context, ref, c) => _aller(context, const EcranDemandeEtablissement()),
  ),
  // ---------------------------------------------------------------- pour tous
  Fonction(
    id: 'assistant_ia', libelle: 'Assistant IA', icone: Icons.auto_awesome_outlined, teinte: Teinte.violet,
    groupe: _tout, motsCles: ['ia', 'question', 'conseil', 'tuteur'], ancienne: '(assistant IA du rôle)',
    visible: (c) => c.ecole && PersonaIa.depuisRoleRacine(c.role) != null,
    ouvrir: (context, ref, c) => _aller(context,
        EcranChatIa(etablissementId: c.etablissement!.id, persona: PersonaIa.depuisRoleRacine(c.role)!)),
  ),
  Fonction(
    id: 'boutique', libelle: 'Boutique', icone: Icons.storefront_outlined, teinte: Teinte.jaune, groupe: _tout,
    motsCles: ['acheter', 'fournitures', 'commande'], ancienne: 'onglet Boutique',
    visible: (c) => c.role != RoleRacine.vendeur && c.role != RoleRacine.adminGsg && c.role != RoleRacine.adminContenu,
    ouvrir: (context, ref, c) => _aller(context, EcranMarketplace(profil: c.profil)),
  ),
  Fonction(
    id: 'referentiel', libelle: 'Programmes officiels', icone: Icons.public_outlined, teinte: Teinte.gris, groupe: _tout,
    motsCles: ['référentiel', 'cedeao', 'programme'], ancienne: 'Référentiel pédagogique CEDEAO',
    // Direction : « Programme officiel » de son pays (Organisation) ;
    // Administrateur GSG : pastille de la plateforme.
    visible: (c) =>
        c.role != RoleRacine.adminContenu &&
        c.role != RoleRacine.adminGsg &&
        !(c.ecole && (c.direction || c.enseignant || c.personnel)),
    ouvrir: (context, ref, c) => _aller(context, const EcranPaysPedagogiques()),
  ),
  // ---------------------------------------------------------------- plateforme GSG
  Fonction(
    id: 'gsg_ecoles', libelle: 'Écoles', icone: Icons.school_outlined, teinte: Teinte.bleu, groupe: _plateforme,
    motsCles: ['écoles confirmées', 'tableau de bord', 'élèves', 'utilisation', 'établissements'],
    visible: (c) => c.role == RoleRacine.adminGsg,
    ouvrir: (context, ref, c) => _aller(context, const EcranEcolesGsg()),
  ),
  Fonction(
    id: 'gsg_referentiel', libelle: 'Programmes officiels', icone: Icons.public_outlined, teinte: Teinte.gris,
    groupe: _plateforme, motsCles: ['référentiel', 'programme', 'matière', 'coefficient', 'pays'],
    visible: (c) => c.role == RoleRacine.adminGsg,
    ouvrir: (context, ref, c) => _aller(context, const EcranPaysPedagogiques()),
  ),
  Fonction(
    id: 'gsg_etablissements', libelle: 'Demandes d’établissement', icone: Icons.add_business_outlined,
    teinte: Teinte.vert, groupe: _plateforme, ancienne: 'Demandes d’établissement',
    visible: (c) => c.role == RoleRacine.adminGsg,
    ouvrir: (context, ref, c) => _aller(context, const EcranValidationEtablissementsGsg()),
  ),
  Fonction(
    id: 'gsg_reseaux', libelle: 'Réseaux', icone: Icons.hub_outlined, teinte: Teinte.sarcelle, groupe: _plateforme,
    ancienne: 'Réseaux d’établissements (GSG)',
    visible: (c) => c.role == RoleRacine.adminGsg,
    ouvrir: (context, ref, c) => _aller(context, const EcranReseauxGsg()),
  ),
  Fonction(
    id: 'gsg_sms', libelle: 'Crédits SMS des écoles', icone: Icons.sms_outlined, teinte: Teinte.jaune, groupe: _plateforme,
    ancienne: 'Crédits SMS des écoles',
    visible: (c) => c.role == RoleRacine.adminGsg,
    ouvrir: (context, ref, c) => _aller(context, const EcranCreditsSmsGsg()),
  ),
  Fonction(
    id: 'gsg_vendeurs', libelle: 'Validation des vendeurs', icone: Icons.verified_user_outlined, teinte: Teinte.bleu,
    groupe: _plateforme, ancienne: 'Validation des vendeurs',
    visible: (c) => c.role == RoleRacine.adminGsg,
    ouvrir: (context, ref, c) => _aller(context, const EcranValidationVendeursGsg()),
  ),
  Fonction(
    id: 'gsg_debloquer', libelle: 'Débloquer un code', icone: Icons.lock_open_outlined, teinte: Teinte.rose,
    groupe: _plateforme, motsCles: ['direction', 'fondateur', 'code'], ancienne: 'Débloquer un code (direction, fondateur)',
    visible: (c) => c.role == RoleRacine.adminGsg,
    ouvrir: (context, ref, c) => _aller(context, const EcranDebloquerCode()),
  ),
];

/// Ordre d'affichage pour un rôle (maquettes) ; les autres fonctions
/// visibles suivent.
const ordreParRole = <RoleRacine, List<String>>{
  RoleRacine.parent: ['annonces', 'cahier_liaison', 'emploi_du_temps', 'notes_bulletins', 'scolarite', 'bus',
    'parent_ia', 'inscriptions_famille', 'boutique'],
  RoleRacine.eleve: ['emploi_du_temps', 'notes_bulletins', 'annonces', 'scan_exercice', 'bibliotheque_famille', 'bus',
    'mes_rapports', 'boutique'],
  RoleRacine.enseignant: ['faire_appel', 'notes_enseignant', 'cahier_liaison', 'mes_classes', 'annonces',
    'progression', 'dossier_rh', 'emploi_du_temps'],
  // Administration GSG (REG-23) : les écoles d'abord.
  RoleRacine.adminGsg: ['gsg_ecoles', 'gsg_etablissements', 'gsg_referentiel', 'gsg_reseaux', 'gsg_sms',
    'gsg_vendeurs', 'gsg_debloquer'],
};

/// Groupes de la direction, dans l'ordre des maquettes.
const groupesDirection = [_vie, _eleves, _finances, _personnel, _organisation, _etablissement, _tout];

/// Fonctions visibles pour ce contexte, dans l'ordre du rôle.
List<Fonction> fonctionsVisibles(ContexteAccueil c, {List<Fonction>? catalogue}) {
  final visibles = [for (final f in catalogue ?? catalogueFonctions) if (f.visible(c)) f];
  final ordre = ordreParRole[c.role];
  if (ordre == null) return visibles;
  int rang(Fonction f) {
    final i = ordre.indexOf(f.id);
    return i < 0 ? ordre.length + visibles.indexOf(f) : i;
  }
  return [...visibles]..sort((a, b) => rang(a).compareTo(rang(b)));
}

/// Recherche « Que voulez-vous faire ? » : libellé et mots-clés, sans
/// accents ni majuscules (« recu » trouve « reçu »).
String sansAccents(String s) {
  const de = 'àâäáãçéèêëíìîïñóòôöõúùûüýÿœ';
  const vers = 'aaaaaceeeeiiiinooooouuuuyyo';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = de.indexOf(ch);
    b.write(i < 0 ? ch : vers[i]);
  }
  return b.toString();
}

List<Fonction> rechercher(List<Fonction> fonctions, String texte) {
  final t = sansAccents(texte.trim());
  if (t.isEmpty) return fonctions;
  return [
    for (final f in fonctions)
      if (sansAccents(f.libelle).contains(t) || f.motsCles.any((m) => sansAccents(m).contains(t))) f,
  ];
}
