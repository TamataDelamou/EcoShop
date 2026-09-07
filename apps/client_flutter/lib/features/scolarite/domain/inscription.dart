import 'classe.dart';
import 'enums_scolarite.dart';
import 'fiche_eleve.dart';

/// Projection cliente de `public.inscriptions` (M5).
///
/// [fiche] est peuplée via l'embed PostgREST `fiches_eleves(*)` (listes de
/// classe) ; [classe] via l'embed `classes(*)` (historique d'une fiche). Une
/// même lecture ne peuple jamais les deux à la fois (contrat M05 §2).
class Inscription {
  const Inscription({
    required this.id,
    required this.etablissementId,
    required this.ficheEleveId,
    required this.classeId,
    required this.anneeScolaireId,
    required this.dateInscription,
    this.statut = StatutInscription.active,
    this.dateRetrait,
    this.motifRetrait,
    this.fiche,
    this.classe,
  });

  factory Inscription.depuisJson(Map<String, dynamic> json) {
    final ficheJson = json['fiches_eleves'] as Map<String, dynamic>?;
    final classeJson = json['classes'] as Map<String, dynamic>?;
    return Inscription(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      classeId: json['classe_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      dateInscription: DateTime.parse(json['date_inscription'] as String),
      statut: StatutInscription.depuisCode(json['statut'] as String?),
      dateRetrait:
          json['date_retrait'] == null ? null : DateTime.parse(json['date_retrait'] as String),
      motifRetrait: json['motif_retrait'] as String?,
      fiche: ficheJson == null ? null : FicheEleve.depuisJson(ficheJson),
      classe: classeJson == null ? null : Classe.depuisJson(classeJson),
    );
  }

  /// Sérialisation plate pour le cache local.
  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'fiche_eleve_id': ficheEleveId,
        'classe_id': classeId,
        'annee_scolaire_id': anneeScolaireId,
        'date_inscription': dateInscription.toIso8601String(),
        'statut': statut.code,
        'date_retrait': dateRetrait?.toIso8601String(),
        'motif_retrait': motifRetrait,
        'fiches_eleves': fiche?.versJson(),
        'classes': classe?.versJson(),
      };

  final String id;
  final String etablissementId;
  final String ficheEleveId;
  final String classeId;
  final String anneeScolaireId;
  final DateTime dateInscription;
  final StatutInscription statut;
  final DateTime? dateRetrait;
  final String? motifRetrait;
  final FicheEleve? fiche;
  final Classe? classe;
}
