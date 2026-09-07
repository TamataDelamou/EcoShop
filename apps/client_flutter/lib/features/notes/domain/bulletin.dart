import 'enums_notes.dart';

/// Projection cliente de `public.bulletins` (M6) — snapshot signé des
/// résultats d'un élève pour une période.
///
/// [signatureSha256] permet de détecter une altération du [contenu] entre sa
/// génération serveur et sa consultation ; le client ne la vérifie pas
/// lui-même (pas de clé publique distribuée à ce stade), il l'affiche comme
/// preuve d'intégrité disponible côté back-office en cas de litige.
class Bulletin {
  const Bulletin({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.classeId,
    required this.ficheEleveId,
    this.periodeId,
    this.type = TypeBulletin.trimestriel,
    this.statut = StatutBulletin.brouillon,
    this.contenu = const {},
    this.signatureSha256,
    this.genereLe,
    this.publieLe,
  });

  factory Bulletin.depuisJson(Map<String, dynamic> json) {
    return Bulletin(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      classeId: json['classe_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      periodeId: json['periode_id'] as String?,
      type: TypeBulletin.depuisCode(json['type'] as String?),
      statut: StatutBulletin.depuisCode(json['statut'] as String?),
      contenu: (json['contenu'] as Map<String, dynamic>?) ?? const {},
      signatureSha256: json['signature_sha256'] as String?,
      genereLe: json['genere_le'] == null ? null : DateTime.parse(json['genere_le'] as String),
      publieLe: json['publie_le'] == null ? null : DateTime.parse(json['publie_le'] as String),
    );
  }

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'fiche_eleve_id': ficheEleveId,
        'periode_id': periodeId,
        'type': type.code,
        'statut': statut.code,
        'contenu': contenu,
        'signature_sha256': signatureSha256,
        'genere_le': genereLe?.toIso8601String(),
        'publie_le': publieLe?.toIso8601String(),
      };

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String classeId;
  final String ficheEleveId;
  final String? periodeId;
  final TypeBulletin type;
  final StatutBulletin statut;
  final Map<String, dynamic> contenu;
  final String? signatureSha256;
  final DateTime? genereLe;
  final DateTime? publieLe;
}
