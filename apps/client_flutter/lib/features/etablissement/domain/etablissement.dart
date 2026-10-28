/// Projection cliente de `public.etablissements` (racine multi-tenant, ch. 27).
class Etablissement {
  const Etablissement({
    required this.id,
    required this.nom,
    required this.slug,
    this.paysCode,
    this.ville,
    this.deviseCode = 'GNF',
    this.langueCode = 'fr',
    this.fuseauHoraire = 'Africa/Conakry',
    this.couleurIdentite,
    this.logoChemin,
    this.slogan,
    this.roleDansEtablissement,
  });

  factory Etablissement.depuisJson(Map<String, dynamic> json) {
    return Etablissement(
      id: json['id'] as String,
      nom: json['nom'] as String,
      slug: json['slug'] as String,
      paysCode: json['pays_code'] as String?,
      ville: json['ville'] as String?,
      deviseCode: json['devise_code'] as String? ?? 'GNF',
      langueCode: json['langue_code'] as String? ?? 'fr',
      fuseauHoraire: json['fuseau_horaire'] as String? ?? 'Africa/Conakry',
      couleurIdentite: json['couleur_identite'] as String?,
      logoChemin: json['logo_chemin'] as String?,
      slogan: json['slogan'] as String?,
      roleDansEtablissement: json['role_dans_etablissement'] as String?,
    );
  }

  final String id;
  final String nom;
  final String slug;
  final String? paysCode;
  final String? ville;

  /// Devise, langue et fuseau proviennent du référentiel : ils ne sont jamais
  /// déduits côté client (conventions — pas de configuration en dur).
  final String deviseCode;
  final String langueCode;
  final String fuseauHoraire;

  /// Identité visuelle choisie par la Direction (REG-07 B) : couleur
  /// `#RRGGBB` et chemin du logo dans le bucket public
  /// `logos-etablissements`. Nulles = charte par défaut du pays.
  final String? couleurIdentite;
  final String? logoChemin;

  /// Devise de l'école (« Travail – Discipline – Réussite »), REG-23.
  final String? slogan;

  /// Rôle du compte connecté dans cet établissement (`etablissements_membres`),
  /// qui peut différer de son rôle principal : un parent invité comme
  /// enseignant, par exemple.
  final String? roleDansEtablissement;

  /// Même forme que la ligne lue par [Etablissement.depuisJson] (copie
  /// locale, REG-18).
  Map<String, dynamic> versJson() => {
        'id': id,
        'nom': nom,
        'slug': slug,
        'pays_code': paysCode,
        'ville': ville,
        'devise_code': deviseCode,
        'langue_code': langueCode,
        'fuseau_horaire': fuseauHoraire,
        'couleur_identite': couleurIdentite,
        'logo_chemin': logoChemin,
        'slogan': slogan,
        'role_dans_etablissement': roleDansEtablissement,
      };

  /// Libellé secondaire affiché sous le nom dans les listes.
  String get localisation =>
      [ville, paysCode].where((v) => v != null && v.isNotEmpty).join(' · ');
}
