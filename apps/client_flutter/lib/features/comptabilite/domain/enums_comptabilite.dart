/// Type de compte comptable — `plans_comptables.type` est un `text` libre
/// côté serveur (pas d'enum SQL : plan comptable OUVERT, aucun OHADA imposé).
/// Ce type Dart couvre les valeurs conventionnelles utilisées par les RPC
/// IA (`predire_tresorerie` filtre `banque`/`caisse`, `analyser_tendances`
/// filtre `charge`/`produit`) ; toute autre valeur saisie par l'établissement
/// retombe sur [autre] côté affichage sans jamais être rejetée côté serveur.
enum TypeCompte {
  autre('autre'),
  banque('banque'),
  caisse('caisse'),
  charge('charge'),
  produit('produit');

  const TypeCompte(this.code);

  final String code;

  String get libelle => switch (this) {
        TypeCompte.autre => 'Autre',
        TypeCompte.banque => 'Banque',
        TypeCompte.caisse => 'Caisse',
        TypeCompte.charge => 'Charge',
        TypeCompte.produit => 'Produit',
      };

  static TypeCompte depuisCode(String? code) =>
      TypeCompte.values.firstWhere((v) => v.code == code, orElse: () => TypeCompte.autre);
}

/// Type de journal — même convention `text` libre (`journaux.type`).
enum TypeJournal {
  operations('operations'),
  banque('banque'),
  caisse('caisse'),
  achats('achats'),
  ventes('ventes');

  const TypeJournal(this.code);

  final String code;

  String get libelle => switch (this) {
        TypeJournal.operations => 'Opérations diverses',
        TypeJournal.banque => 'Banque',
        TypeJournal.caisse => 'Caisse',
        TypeJournal.achats => 'Achats',
        TypeJournal.ventes => 'Ventes',
      };

  static TypeJournal depuisCode(String? code) =>
      TypeJournal.values.firstWhere((v) => v.code == code, orElse: () => TypeJournal.operations);
}
