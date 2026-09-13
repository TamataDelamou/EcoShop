/// Libellés des deux signataires du bulletin pour un cycle donné (D5) —
/// valeurs par défaut posées en base, ajustables par pays uniquement (pas
/// par établissement dans cette passe).
class LibellesSignatureCycle {
  const LibellesSignatureCycle({required this.signataire1, required this.signataire2});

  factory LibellesSignatureCycle.depuisJson(Map<String, dynamic> json) {
    return LibellesSignatureCycle(
      signataire1: json['signataire1'] as String? ?? '',
      signataire2: json['signataire2'] as String? ?? '',
    );
  }

  final String signataire1;
  final String signataire2;
}

/// Projection cliente de `public.pays_pedagogiques` (M4).
///
/// Seuls les pays `deploye` sont visibles côté client (RLS) : ce champ est
/// donc toujours vrai pour les lignes reçues du serveur, mais on le conserve
/// pour l'affichage éventuel côté back-office/preview.
class PaysPedagogique {
  const PaysPedagogique({
    required this.codeIso,
    required this.nom,
    required this.typeSysteme,
    required this.langueEnseignementPrincipale,
    this.organismeExaminateur,
    this.deviseCode = 'XOF',
    this.statutDeploiement = 'deploye',
    this.ministereTutelle,
    this.signaturesBulletin = const {},
  });

  factory PaysPedagogique.depuisJson(Map<String, dynamic> json) {
    return PaysPedagogique(
      codeIso: json['code_iso'] as String,
      nom: json['nom'] as String,
      typeSysteme: json['type_systeme'] as String,
      langueEnseignementPrincipale:
          json['langue_enseignement_principale'] as String,
      organismeExaminateur: json['organisme_examinateur'] as String?,
      deviseCode: json['devise_code'] as String? ?? 'XOF',
      statutDeploiement: json['statut_deploiement'] as String? ?? 'deploye',
      ministereTutelle: json['ministere_tutelle'] as String?,
      signaturesBulletin:
          (json['signatures_bulletin'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Map<String, dynamic> versJson() => {
        'code_iso': codeIso,
        'nom': nom,
        'type_systeme': typeSysteme,
        'langue_enseignement_principale': langueEnseignementPrincipale,
        'organisme_examinateur': organismeExaminateur,
        'devise_code': deviseCode,
        'statut_deploiement': statutDeploiement,
        'ministere_tutelle': ministereTutelle,
        'signatures_bulletin': signaturesBulletin,
      };

  final String codeIso;
  final String nom;
  final String typeSysteme;
  final String langueEnseignementPrincipale;
  final String? organismeExaminateur;
  final String deviseCode;
  final String statutDeploiement;

  /// Donnée neuve (D5), distincte de [organismeExaminateur] (organisme
  /// certificateur d'un examen, pas l'autorité de tutelle administrative) —
  /// `null` tant qu'aucune source ministérielle fiable n'a été intégrée
  /// (jamais de valeur inventée côté client) ; un bulletin l'affiche s'il
  /// est renseigné, l'omet sinon — jamais une erreur bloquante.
  final String? ministereTutelle;

  /// jsonb brut, clés `primaire`/`college`/`lycee` (D5) — voir
  /// [signaturesPourIsced].
  final Map<String, dynamic> signaturesBulletin;

  /// Libellés de signature du bulletin pour le palier ISCED normalisé de la
  /// classe (1 = primaire, 2 = collège, 3 = lycée — voir `classe_isced`
  /// côté serveur, cahier §6.4 : le code de cycle littéral varie par pays,
  /// l'ISCED non). `null` si le palier est inconnu ou hors de ces 3 valeurs
  /// — un bulletin omet alors le bloc signatures plutôt que d'en afficher un
  /// incohérent.
  LibellesSignatureCycle? signaturesPourIsced(int? isced) {
    final cle = switch (isced) {
      1 => 'primaire',
      2 => 'college',
      3 => 'lycee',
      _ => null,
    };
    if (cle == null) return null;
    final json = signaturesBulletin[cle] as Map<String, dynamic>?;
    return json == null ? null : LibellesSignatureCycle.depuisJson(json);
  }
}
