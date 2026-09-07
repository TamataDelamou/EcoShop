/// Enums SQL de M5 (`type_periode`, `statut_inscription`,
/// `type_relation_parentale`, `statut_relation`, `role_affectation`).
library;

enum TypePeriode {
  trimestre('trimestre'),
  semestre('semestre'),
  terme('terme');

  const TypePeriode(this.code);
  final String code;

  static TypePeriode depuisCode(String? code) {
    for (final v in TypePeriode.values) {
      if (v.code == code) return v;
    }
    return TypePeriode.trimestre;
  }
}

enum StatutInscription {
  active('active'),
  retiree('retiree'),
  redoublante('redoublante'),
  enAttente('en_attente');

  const StatutInscription(this.code);
  final String code;

  static StatutInscription depuisCode(String? code) {
    for (final v in StatutInscription.values) {
      if (v.code == code) return v;
    }
    return StatutInscription.active;
  }
}

enum TypeRelationParentale {
  tuteurLegal('tuteur_legal'),
  parent('parent'),
  autre('autre');

  const TypeRelationParentale(this.code);
  final String code;

  static TypeRelationParentale depuisCode(String? code) {
    for (final v in TypeRelationParentale.values) {
      if (v.code == code) return v;
    }
    return TypeRelationParentale.parent;
  }
}

enum StatutRelation {
  enAttente('en_attente'),
  confirmee('confirmee'),
  refusee('refusee');

  const StatutRelation(this.code);
  final String code;

  static StatutRelation depuisCode(String? code) {
    for (final v in StatutRelation.values) {
      if (v.code == code) return v;
    }
    return StatutRelation.enAttente;
  }
}

enum RoleAffectation {
  titulaire('titulaire'),
  enseignant('enseignant'),
  suppleant('suppleant');

  const RoleAffectation(this.code);
  final String code;

  static RoleAffectation depuisCode(String? code) {
    for (final v in RoleAffectation.values) {
      if (v.code == code) return v;
    }
    return RoleAffectation.enseignant;
  }
}
