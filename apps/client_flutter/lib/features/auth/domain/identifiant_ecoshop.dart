/// Identifiant EcoShop (REG-18, partie D) : `EC-XXXX-XXC`, attribué par le
/// serveur, propre à EcoShop, jamais réattribué.
///
/// Même calcul que la base (`normaliser_identifiant_ecoshop`) et l'Edge
/// Function `connexion_identifiant` : 6 caractères de l'alphabet de Crockford
/// (sans I, L, O, U) et un caractère de contrôle Luhn mod 32. Une faute de
/// frappe est repérée sur le téléphone, sans rien demander au serveur.
///
/// L'identifiant n'est pas un secret : il sert à recevoir un code à l'adresse
/// du compte, jamais à ouvrir une session à lui seul.
abstract final class IdentifiantEcoshop {
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static final _forme = RegExp(r'^EC[0-9A-HJKMNP-TV-Z]{7}$');

  /// Caractère de contrôle de [corps] (6 caractères de l'alphabet).
  static String controle(String corps) {
    var facteur = 2;
    var somme = 0;
    for (var i = corps.length - 1; i >= 0; i--) {
      final valeur = _alphabet.indexOf(corps[i]);
      if (valeur < 0) throw ArgumentError.value(corps, 'corps', 'caractère hors alphabet');
      final ajout = facteur * valeur;
      facteur = facteur == 2 ? 1 : 2;
      somme += ajout ~/ 32 + ajout % 32;
    }
    return _alphabet[(32 - somme % 32) % 32];
  }

  /// Forme `EC-XXXX-XXC`, ou null si [saisie] n'est pas un identifiant
  /// valide. Tolère minuscules, espaces et tirets ; O lu comme 0, I et L
  /// comme 1.
  static String? normaliser(String saisie) {
    final v = saisie
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    if (!_forme.hasMatch(v)) return null;
    if (controle(v.substring(2, 8)) != v[8]) return null;
    return 'EC-${v.substring(2, 6)}-${v.substring(6, 9)}';
  }

  /// Vrai si la saisie ressemble à un identifiant (commence par « EC »,
  /// sans @) : le champ de connexion choisit alors la connexion par
  /// identifiant, et signale une faute de frappe plutôt qu'une adresse
  /// invalide.
  static bool ressemble(String saisie) {
    final v = saisie.trim().toUpperCase();
    return v.startsWith('EC') && !v.contains('@');
  }
}
