import 'enums_rapports.dart';

/// Projection cliente de `public.rapports` (M10) — demande de génération
/// différée (bulletin, relevé, statistiques globales, personnalisé, résumé
/// exécutif). La génération elle-même est un traitement serveur : le client
/// crée la ligne au statut `demande` puis interroge `statut`/`fichierUrl`.
///
/// `demandeHorsLigne` porte l'intention hors-ligne documentée par le
/// contrat M10 (`rapports.demande_hors_ligne` + `cache_valide_jus`) : une
/// demande déposée sans réseau est marquée ainsi puis rejouée via
/// `sync_queue`, comme les autres écritures tolérantes du projet (M6-M9).
class Rapport {
  const Rapport({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    this.periodeId,
    this.classeId,
    this.ficheEleveId,
    required this.type,
    this.format = TypeExport.pdf,
    this.filtres = const {},
    this.statut = StatutRapport.demande,
    this.fichierUrl,
    this.genereLe,
    this.demandeHorsLigne = false,
  });

  factory Rapport.depuisJson(Map<String, dynamic> json) => Rapport(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        periodeId: json['periode_id'] as String?,
        classeId: json['classe_id'] as String?,
        ficheEleveId: json['fiche_eleve_id'] as String?,
        type: json['type'] as String,
        format: TypeExport.depuisCode(json['format'] as String?),
        filtres: (json['filtres'] as Map<String, dynamic>?) ?? const {},
        statut: StatutRapport.depuisCode(json['statut'] as String?),
        fichierUrl: json['fichier_url'] as String?,
        genereLe: json['genere_le'] == null ? null : DateTime.parse(json['genere_le'] as String),
        demandeHorsLigne: json['demande_hors_ligne'] as bool? ?? false,
      );

  factory Rapport.depuisJsonCache(Map<String, dynamic> json) => Rapport.depuisJson(json);

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'periode_id': periodeId,
        'classe_id': classeId,
        'fiche_eleve_id': ficheEleveId,
        'type': type,
        'format': format.code,
        'filtres': filtres,
        'statut': statut.code,
        'fichier_url': fichierUrl,
        'genere_le': genereLe?.toIso8601String(),
        'demande_hors_ligne': demandeHorsLigne,
      };

  /// Colonnes réelles de `public.rapports` — pour la demande de génération
  /// (`id` fourni côté client pour l'affichage immédiat hors-ligne, mais
  /// n'est pas la clé de dédoublonnage serveur : `rapports` n'a aucune
  /// contrainte unique sur les colonnes métier, une nouvelle demande crée
  /// donc toujours une nouvelle ligne).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'periode_id': periodeId,
        'classe_id': classeId,
        'fiche_eleve_id': ficheEleveId,
        'type': type,
        'format': format.code,
        'filtres': filtres,
        'demande_hors_ligne': demandeHorsLigne,
      };

  factory Rapport.depuisJsonEcriture(Map<String, dynamic> json) => Rapport(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        periodeId: json['periode_id'] as String?,
        classeId: json['classe_id'] as String?,
        ficheEleveId: json['fiche_eleve_id'] as String?,
        type: json['type'] as String,
        format: TypeExport.depuisCode(json['format'] as String?),
        filtres: (json['filtres'] as Map<String, dynamic>?) ?? const {},
        demandeHorsLigne: json['demande_hors_ligne'] as bool? ?? false,
      );

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String? periodeId;
  final String? classeId;
  final String? ficheEleveId;
  final String type;
  final TypeExport format;
  final Map<String, dynamic> filtres;
  final StatutRapport statut;
  final String? fichierUrl;
  final DateTime? genereLe;
  final bool demandeHorsLigne;
}
