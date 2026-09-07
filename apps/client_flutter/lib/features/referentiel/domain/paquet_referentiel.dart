/// Projection cliente de `public.paquets_referentiel` (M4).
///
/// Unité de téléchargement hors-ligne du référentiel, versionnée et vérifiée
/// par empreinte SHA-256 (contrat M04 §5) — axe différenciant du module.
class PaquetReferentiel {
  const PaquetReferentiel({
    required this.id,
    required this.paysCode,
    required this.version,
    required this.empreinteSha256,
    required this.tailleOctets,
    this.niveauId,
    this.url,
    this.publieLe,
  });

  factory PaquetReferentiel.depuisJson(Map<String, dynamic> json) {
    return PaquetReferentiel(
      id: json['id'] as String,
      paysCode: json['pays_code'] as String,
      version: json['version'] as int,
      empreinteSha256: json['empreinte_sha256'] as String,
      tailleOctets: (json['taille_octets'] as num).toInt(),
      niveauId: json['niveau_id'] as String?,
      url: json['url'] as String?,
      publieLe: json['publie_le'] == null
          ? null
          : DateTime.parse(json['publie_le'] as String),
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'pays_code': paysCode,
        'version': version,
        'empreinte_sha256': empreinteSha256,
        'taille_octets': tailleOctets,
        'niveau_id': niveauId,
        'url': url,
        'publie_le': publieLe?.toIso8601String(),
      };

  final String id;
  final String paysCode;
  final int version;
  final String empreinteSha256;
  final int tailleOctets;
  final String? niveauId;
  final String? url;
  final DateTime? publieLe;
}
