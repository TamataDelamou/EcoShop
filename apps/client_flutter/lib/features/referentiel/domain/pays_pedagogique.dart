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
      };

  final String codeIso;
  final String nom;
  final String typeSysteme;
  final String langueEnseignementPrincipale;
  final String? organismeExaminateur;
  final String deviseCode;
  final String statutDeploiement;
}
