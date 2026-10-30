import '../../../core/auth/role_racine.dart';
import '../../../core/offline/amorcage.dart';

/// Lectures dont l'amorçage a besoin (REG-35, lot 2). Chaque fonction
/// appelle un dépôt existant qui garde sa réponse sur l'appareil ; ici on
/// ne garde que ce qu'il faut pour enchaîner (identifiants).
///
/// Séparé des dépôts pour être testé sans serveur.
class SourcesAmorcage {
  const SourcesAmorcage({
    required this.structure,
    required this.inscriptionsDeClasse,
    required this.affectationsDeClasse,
    required this.emploisDeClasse,
    required this.evaluationsDeClasse,
    required this.mesAffectations,
    required this.emploisDeEnseignant,
    required this.mesEnfants,
    required this.maFiche,
    required this.classeActuelleDeFiche,
    required this.notesDeFiche,
    required this.bulletinsDeFiche,
    required this.presencesDeFiche,
    required this.retardsDeFiche,
    required this.sanctionsDeFiche,
    required this.cahierDeFiche,
    required this.annonces,
    required this.personnel,
    required this.encaissementsRecents,
    required this.fraisScolarite,
    required this.agendaEtablissement,
  });

  /// Classes et année courante de l'école.
  final Future<({String? anneeId, List<({String id, String nom})> classes})> Function(String etablissementId) structure;

  final Future<Object?> Function(String classeId) inscriptionsDeClasse;
  final Future<Object?> Function(String classeId) affectationsDeClasse;
  final Future<Object?> Function(String classeId) emploisDeClasse;
  final Future<Object?> Function(String classeId) evaluationsDeClasse;

  /// Classes de l'enseignant connecté dans cette école.
  final Future<List<String>> Function(String etablissementId) mesAffectations;
  final Future<Object?> Function(String profileId, String etablissementId, String anneeId) emploisDeEnseignant;

  /// Fiches des enfants confirmés du parent dans cette école.
  final Future<List<String>> Function(String etablissementId) mesEnfants;

  /// Fiche de l'élève connecté.
  final Future<String?> Function() maFiche;

  /// Classe actuelle d'une fiche (dernière inscription), ou null.
  final Future<String?> Function(String ficheId) classeActuelleDeFiche;

  final Future<Object?> Function(String ficheId) notesDeFiche;
  final Future<Object?> Function(String ficheId) bulletinsDeFiche;
  final Future<Object?> Function(String ficheId) presencesDeFiche;
  final Future<Object?> Function(String ficheId) retardsDeFiche;
  final Future<Object?> Function(String ficheId) sanctionsDeFiche;
  final Future<Object?> Function(String ficheId) cahierDeFiche;

  final Future<Object?> Function() annonces;
  final Future<Object?> Function(String etablissementId) personnel;
  final Future<Object?> Function(String etablissementId) encaissementsRecents;
  final Future<Object?> Function(String etablissementId, String anneeId) fraisScolarite;
  final Future<Object?> Function(String etablissementId, String anneeId) agendaEtablissement;
}

/// Ce que l'amorçage lit d'avance pour un espace (un rôle dans une école).
///
/// Granularité : la classe, jamais l'élève, pour la Direction et le
/// personnel — une école de 2 000 élèves compte une cinquantaine de classes,
/// soit environ 200 lectures au lieu de plusieurs milliers. Les données
/// d'un élève (notes, absences) sont lues d'avance seulement pour l'élève
/// lui-même et pour les enfants d'un parent ; les autres se chargent à la
/// demande, comme les modèles « lazy » de Linear.
List<TacheAmorcage> planAmorcage({
  required RoleRacine role,
  required String etablissementId,
  required String profileId,
  required SourcesAmorcage sources,
}) {
  final s = sources;
  // Portées (lot 3) : une lecture dont la portée n'a pas changé depuis la
  // dernière fois est sautée. Les tâches qui produisent d'autres tâches n'en
  // ont pas : elles tournent toujours, pour découvrir classes et enfants.
  final ecole = 'etablissement:$etablissementId';
  String pClasse(String id) => 'classe:$id';
  String pFiche(String id) => 'fiche:$id';

  final taches = <TacheAmorcage>[
    TacheAmorcage.lire('Annonces', s.annonces, portee: ecole),
  ];

  List<TacheAmorcage> classe(String id, String nom, {required bool gestion}) => [
        TacheAmorcage.lire('Élèves de $nom', () => s.inscriptionsDeClasse(id), portee: pClasse(id)),
        TacheAmorcage.lire('Emploi du temps de $nom', () => s.emploisDeClasse(id), portee: pClasse(id)),
        TacheAmorcage.lire('Évaluations de $nom', () => s.evaluationsDeClasse(id), portee: pClasse(id)),
        if (gestion)
          TacheAmorcage.lire('Enseignants de $nom', () => s.affectationsDeClasse(id), portee: pClasse(id)),
      ];

  List<TacheAmorcage> fiche(String ficheId) => [
        TacheAmorcage.lire('Notes', () => s.notesDeFiche(ficheId), portee: pFiche(ficheId)),
        TacheAmorcage.lire('Bulletins', () => s.bulletinsDeFiche(ficheId), portee: pFiche(ficheId)),
        TacheAmorcage.lire('Absences', () => s.presencesDeFiche(ficheId), portee: pFiche(ficheId)),
        TacheAmorcage.lire('Retards', () => s.retardsDeFiche(ficheId), portee: pFiche(ficheId)),
        TacheAmorcage.lire('Sanctions', () => s.sanctionsDeFiche(ficheId), portee: pFiche(ficheId)),
        TacheAmorcage.lire('Cahier de liaison', () => s.cahierDeFiche(ficheId), portee: pFiche(ficheId)),
        TacheAmorcage('Classe de l\'élève', () async {
          final classeId = await s.classeActuelleDeFiche(ficheId);
          if (classeId == null) return const [];
          return [TacheAmorcage.lire('Emploi du temps', () => s.emploisDeClasse(classeId), portee: pClasse(classeId))];
        }),
      ];

  switch (role) {
    case RoleRacine.direction:
    case RoleRacine.personnel:
      taches.addAll([
        TacheAmorcage('Classes de l\'école', () async {
          final st = await s.structure(etablissementId);
          final annee = st.anneeId;
          return [
            for (final c in st.classes) ...classe(c.id, c.nom, gestion: true),
            if (annee != null) ...[
              TacheAmorcage.lire('Tarifs', () => s.fraisScolarite(etablissementId, annee), portee: ecole),
              TacheAmorcage.lire('Agenda', () => s.agendaEtablissement(etablissementId, annee), portee: ecole),
            ],
          ];
        }),
        TacheAmorcage.lire('Personnel', () => s.personnel(etablissementId), portee: ecole),
        TacheAmorcage.lire('Derniers encaissements', () => s.encaissementsRecents(etablissementId), portee: ecole),
      ]);
    case RoleRacine.enseignant:
      taches.add(TacheAmorcage('Mes classes', () async {
        final st = await s.structure(etablissementId);
        final mes = (await s.mesAffectations(etablissementId)).toSet();
        final annee = st.anneeId;
        return [
          for (final c in st.classes)
            if (mes.contains(c.id)) ...classe(c.id, c.nom, gestion: false),
          if (annee != null)
            TacheAmorcage.lire('Mon emploi du temps', () => s.emploisDeEnseignant(profileId, etablissementId, annee)),
        ];
      }));
    case RoleRacine.parent:
      taches.add(TacheAmorcage('Mes enfants', () async {
        final fiches = await s.mesEnfants(etablissementId);
        return [for (final f in fiches) ...fiche(f)];
      }));
    case RoleRacine.eleve:
      taches.add(TacheAmorcage('Ma fiche', () async {
        final f = await s.maFiche();
        return f == null ? const [] : fiche(f);
      }));
    case RoleRacine.vendeur:
    case RoleRacine.fondateurReseau:
    case RoleRacine.adminGsg:
    case RoleRacine.adminContenu:
      // Hors du périmètre de ce lot : leurs écrans gardent leur copie à la
      // première consultation.
      break;
  }
  return taches;
}
