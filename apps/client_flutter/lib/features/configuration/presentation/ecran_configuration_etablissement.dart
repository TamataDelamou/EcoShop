import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../etablissement/domain/etablissement.dart';
import '../../inscription_en_ligne/presentation/ecran_campagne_inscription.dart';
import '../../invitations/presentation/ecran_invitations_etablissement.dart';
import '../../paiement_mobile/presentation/ecran_orange_money_etablissement.dart';
import '../../scolarite/presentation/ecran_creation_inscription.dart';
import '../../scolarite/presentation/ecran_parametres_financiers.dart';
import '../../themes/presentation/ecran_identite_visuelle.dart';
import '../application/configuration_providers.dart';
import '../domain/configuration.dart';
import 'ecran_affectations.dart';
import 'ecran_annees_scolaires.dart';
import 'ecran_classes_configuration.dart';
import 'ecran_emploi_du_temps_automatique.dart';
import 'ecran_groupes.dart';
import 'ecran_programme_etablissement.dart';
import 'ecran_salles_configuration.dart';
import 'elements_configuration.dart';

/// Une étape de la mise en route.
class EtapeConfiguration {
  const EtapeConfiguration({
    required this.cle,
    required this.titre,
    required this.icone,
    required this.etat,
    required this.faite,
    this.facultative = false,
    this.ouvrir,
    this.bloquee,
  });

  final String cle;
  final String titre;
  final IconData icone;

  /// Ce qui est fait, en clair (« 12 classes », « à faire »).
  final String etat;
  final bool faite;
  final bool facultative;

  /// Null : étape pas encore accessible ([bloquee] dit pourquoi).
  final Widget Function()? ouvrir;
  final String? bloquee;
}

/// Étapes de la mise en route, dans l'ordre (REG-23).
List<EtapeConfiguration> etapesConfiguration(Etablissement etab, EtatConfiguration e) {
  final annee = e.anneeId;
  String n(int v, String un, String plusieurs) => v == 0 ? 'à faire' : '$v ${v > 1 ? plusieurs : un}';
  const sansAnnee = 'Créez d’abord l’année scolaire';
  return [
    EtapeConfiguration(
      cle: 'annee',
      titre: 'Année scolaire et périodes',
      icone: Icons.event_note_outlined,
      etat: annee == null ? 'à faire' : '${e.anneeLibelle} · ${e.periodes} période${e.periodes > 1 ? 's' : ''}',
      faite: annee != null && e.periodes > 0,
      ouvrir: () => EcranAnneesScolaires(etablissement: etab),
    ),
    EtapeConfiguration(
      cle: 'programme',
      titre: 'Programme officiel',
      icone: Icons.menu_book_outlined,
      etat: etab.paysCode == null ? 'pays de l’école à renseigner' : 'niveaux, matières, coefficients, volumes',
      faite: etab.paysCode != null,
      ouvrir: () => EcranProgrammeEtablissement(etablissement: etab),
    ),
    EtapeConfiguration(
      cle: 'classes',
      titre: 'Classes',
      icone: Icons.class_outlined,
      etat: e.classes == 0
          ? 'à faire'
          : '${e.classes} classe${e.classes > 1 ? 's' : ''}'
              '${e.classesSansNiveau > 0 ? ' · ${e.classesSansNiveau} sans niveau' : ''}',
      faite: e.classes > 0 && e.classesSansNiveau == 0,
      ouvrir: annee == null ? null : () => EcranClassesConfiguration(etablissement: etab, anneeId: annee),
      bloquee: sansAnnee,
    ),
    EtapeConfiguration(
      cle: 'frais',
      titre: 'Frais de scolarité',
      icone: Icons.request_quote_outlined,
      etat: n(e.frais, 'tarif', 'tarifs'),
      faite: e.frais > 0,
      ouvrir: annee == null ? null : () => EcranParametresFinanciers(etablissementId: etab.id, anneeScolaireId: annee),
      bloquee: sansAnnee,
    ),
    EtapeConfiguration(
      cle: 'personnel',
      titre: 'Personnel et enseignants',
      icone: Icons.badge_outlined,
      etat: e.personnel <= 1 ? 'à inviter' : '${e.personnel} membres dont ${e.enseignants} enseignant${e.enseignants > 1 ? 's' : ''}',
      faite: e.enseignants > 0,
      ouvrir: () => EcranInvitationsEtablissement(etablissementId: etab.id),
    ),
    EtapeConfiguration(
      cle: 'groupes',
      titre: 'Groupes pédagogiques',
      icone: Icons.groups_2_outlined,
      etat: e.groupes == 0 ? 'facultatif' : '${e.groupes} groupe${e.groupes > 1 ? 's' : ''}',
      faite: e.groupes > 0,
      facultative: true,
      ouvrir: annee == null ? null : () => EcranGroupes(etablissement: etab, anneeId: annee),
      bloquee: sansAnnee,
    ),
    EtapeConfiguration(
      cle: 'salles',
      titre: 'Salles',
      icone: Icons.meeting_room_outlined,
      etat: e.salles == 0 ? 'facultatif' : '${e.salles} salle${e.salles > 1 ? 's' : ''}',
      faite: e.salles > 0,
      facultative: true,
      ouvrir: () => EcranSallesConfiguration(etablissement: etab),
    ),
    EtapeConfiguration(
      cle: 'cours',
      titre: 'Cours et enseignants',
      icone: Icons.co_present_outlined,
      etat: e.affectations == 0
          ? 'à faire'
          : '${e.affectations} cours${e.classesSansAffectation > 0 ? ' · ${e.classesSansAffectation} classe(s) sans cours' : ''}',
      faite: e.affectations > 0 && e.classesSansAffectation == 0,
      ouvrir: annee == null ? null : () => EcranAffectations(etablissement: etab, anneeId: annee),
      bloquee: sansAnnee,
    ),
    EtapeConfiguration(
      cle: 'emploi',
      titre: 'Emploi du temps',
      icone: Icons.calendar_view_week_outlined,
      etat: e.seances == 0 ? (e.grilleHoraire ? 'à calculer' : 'grille puis calcul automatique') : '${e.seances} séances publiées',
      faite: e.seances > 0,
      ouvrir: annee == null ? null : () => EcranEmploiDuTempsAutomatique(etablissement: etab, anneeId: annee),
      bloquee: sansAnnee,
    ),
    EtapeConfiguration(
      cle: 'inscriptions',
      titre: 'Inscrire les élèves',
      icone: Icons.person_add_alt_1_outlined,
      etat: e.elevesInscrits == 0 ? 'à faire' : '${e.elevesInscrits} élève${e.elevesInscrits > 1 ? 's' : ''} inscrit${e.elevesInscrits > 1 ? 's' : ''}',
      faite: e.elevesInscrits > 0,
      ouvrir: e.classes == 0 ? null : () => const EcranCreationInscription(),
      bloquee: 'Créez d’abord les classes',
    ),
    EtapeConfiguration(
      cle: 'en_ligne',
      titre: 'Inscriptions en ligne',
      icone: Icons.how_to_reg_outlined,
      etat: e.campagneInscription ? 'campagne ouverte' : 'facultatif',
      faite: e.campagneInscription,
      facultative: true,
      ouvrir: () => EcranCampagneInscription(etablissementId: etab.id, devise: etab.deviseCode),
    ),
    EtapeConfiguration(
      cle: 'identite',
      titre: 'Logo, couleur et slogan',
      icone: Icons.palette_outlined,
      etat: e.identiteVisuelle || e.slogan
          ? [if (e.identiteVisuelle) 'identité choisie', if (e.slogan) 'slogan'].join(' · ')
          : 'facultatif',
      faite: e.identiteVisuelle,
      facultative: true,
      ouvrir: () => EcranIdentiteVisuelle(etablissement: etab),
    ),
    EtapeConfiguration(
      cle: 'orange_money',
      titre: 'Paiement Orange Money',
      icone: Icons.phone_iphone_rounded,
      etat: e.paiementMobile ? 'activé' : 'facultatif',
      faite: e.paiementMobile,
      facultative: true,
      ouvrir: () => EcranOrangeMoneyEtablissement(etablissementId: etab.id, devise: etab.deviseCode),
    ),
  ];
}

/// « Configurer mon établissement » (REG-23) : toutes les étapes de la mise
/// en route au même endroit, dans l'ordre, avec l'état de chacune.
class EcranConfigurationEtablissement extends ConsumerWidget {
  const EcranConfigurationEtablissement({super.key, required this.etablissement});

  final Etablissement etablissement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(etatConfigurationProvider(etablissement.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Configurer mon établissement')),
      body: etat.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErreurChargement(onReessayer: () => ref.invalidate(etatConfigurationProvider(etablissement.id))),
        data: (e) {
          final etapes = etapesConfiguration(etablissement, e);
          final essentielles = etapes.where((x) => !x.facultative).toList();
          final faites = essentielles.where((x) => x.faite).length;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(etatConfigurationProvider(etablissement.id)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _Progression(faites: faites, total: essentielles.length, nom: etablissement.nom),
                const SizedBox(height: 12),
                for (var i = 0; i < etapes.length; i++) _LigneEtape(numero: i + 1, etape: etapes[i], etablissementId: etablissement.id),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Progression extends StatelessWidget {
  const _Progression({required this.faites, required this.total, required this.nom});

  final int faites;
  final int total;
  final String nom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fini = faites == total;
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nom, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(fini
                ? 'Votre établissement est prêt. Vous pouvez revenir ici à chaque rentrée.'
                : '$faites étape${faites > 1 ? 's' : ''} essentielle${faites > 1 ? 's' : ''} sur $total. Suivez l’ordre : chaque étape prépare la suivante.'),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: total == 0 ? 0 : faites / total, minHeight: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneEtape extends ConsumerWidget {
  const _LigneEtape({required this.numero, required this.etape, required this.etablissementId});

  final int numero;
  final EtapeConfiguration etape;
  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schema = Theme.of(context).colorScheme;
    final ouvrir = etape.ouvrir;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: Key('etape_${etape.cle}'),
        leading: CircleAvatar(
          backgroundColor: etape.faite ? schema.primary : schema.surfaceContainerHighest,
          foregroundColor: etape.faite ? schema.onPrimary : schema.onSurfaceVariant,
          child: etape.faite ? const Icon(Icons.check) : Text('$numero'),
        ),
        title: Row(
          children: [
            Icon(etape.icone, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(etape.titre, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
        subtitle: Text(ouvrir == null ? (etape.bloquee ?? etape.etat) : etape.etat),
        trailing: const Icon(Icons.chevron_right),
        onTap: ouvrir == null
            ? () => signaler(context, etape.bloquee ?? 'Étape pas encore disponible.')
            : () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ouvrir()));
                // Retour : l'état est relu (étape cochée).
                ref.invalidate(etatConfigurationProvider(etablissementId));
              },
      ),
    );
  }
}

/// Carte de l'accueil de la Direction tant que la mise en route n'est pas
/// finie : « Configurer mon établissement — 4 étapes sur 9 ».
class CarteMiseEnRoute extends ConsumerWidget {
  const CarteMiseEnRoute({super.key, required this.etablissement});

  final Etablissement etablissement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(etatConfigurationProvider(etablissement.id)).valueOrNull;
    if (e == null) return const SizedBox.shrink();
    final essentielles = etapesConfiguration(etablissement, e).where((x) => !x.facultative).toList();
    final faites = essentielles.where((x) => x.faite).length;
    if (faites == essentielles.length) return const SizedBox.shrink();
    final suivante = essentielles.firstWhere((x) => !x.faite);
    final schema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        key: const Key('carte_mise_en_route'),
        color: schema.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranConfigurationEtablissement(etablissement: etablissement)),
            );
            ref.invalidate(etatConfigurationProvider(etablissement.id));
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(value: faites / essentielles.length, strokeWidth: 5),
                      Text('$faites/${essentielles.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Configurer mon établissement',
                          style: TextStyle(fontWeight: FontWeight.w800, color: schema.onPrimaryContainer)),
                      const SizedBox(height: 2),
                      Text('Étape suivante : ${suivante.titre}', style: TextStyle(color: schema.onPrimaryContainer)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: schema.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
