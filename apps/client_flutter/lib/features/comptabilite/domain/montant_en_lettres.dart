/// Montant en toutes lettres (français), pour les reçus de dons :
/// « 1 250 000 » → « un million deux cent cinquante mille ».
///
/// Règles de l'orthographe traditionnelle : « et » pour 21, 31… 71 ;
/// « quatre-vingts » et « cents » ne prennent le pluriel qu'en fin de
/// nombre ; « mille » est invariable ; « million(s) », « milliard(s) ».
library;

const _unites = [
  'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', 'dix',
  'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize', 'dix-sept', 'dix-huit', 'dix-neuf',
];
const _dizaines = ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante'];

String _moinsDeCent(int n) {
  if (n < 20) return _unites[n];
  final d = n ~/ 10;
  final u = n % 10;
  if (d == 7 || d == 9) {
    // 70-79 : soixante-dix… ; 90-99 : quatre-vingt-dix…
    final base = d == 7 ? 'soixante' : 'quatre-vingt';
    if (d == 7 && u == 1) return 'soixante et onze';
    return '$base-${_unites[10 + u]}';
  }
  if (d == 8) return u == 0 ? 'quatre-vingts' : 'quatre-vingt-${_unites[u]}';
  if (u == 0) return _dizaines[d];
  if (u == 1) return '${_dizaines[d]} et un';
  return '${_dizaines[d]}-${_unites[u]}';
}

String _moinsDeMille(int n, {required bool finDeNombre}) {
  final c = n ~/ 100;
  final r = n % 100;
  final parties = <String>[];
  if (c == 1) {
    parties.add('cent');
  } else if (c > 1) {
    parties.add('${_unites[c]} ${r == 0 && finDeNombre ? 'cents' : 'cent'}');
  }
  if (r > 0) {
    var t = _moinsDeCent(r);
    // « quatre-vingts » perd son s devant « mille ».
    if (!finDeNombre && t == 'quatre-vingts') t = 'quatre-vingt';
    parties.add(t);
  }
  return parties.join(' ');
}

String montantEnLettres(num montant) {
  var n = montant.round().abs();
  if (n == 0) return 'zéro';
  final parties = <String>[];
  const echelles = [(1000000000, 'milliard'), (1000000, 'million')];
  for (final (valeur, nom) in echelles) {
    final q = n ~/ valeur;
    if (q > 0) {
      parties.add('${_moinsDeMille(q, finDeNombre: true)} $nom${q > 1 ? 's' : ''}');
      n %= valeur;
    }
  }
  final milliers = n ~/ 1000;
  if (milliers > 0) {
    parties.add(milliers == 1 ? 'mille' : '${_moinsDeMille(milliers, finDeNombre: false)} mille');
    n %= 1000;
  }
  if (n > 0) parties.add(_moinsDeMille(n, finDeNombre: true));
  return '${montant < 0 ? 'moins ' : ''}${parties.join(' ')}';
}

/// Nom de la devise en toutes lettres, au pluriel si besoin.
String deviseEnLettres(String code, num montant) {
  final pluriel = montant.round().abs() > 1;
  return switch (code) {
    'GNF' => pluriel ? 'francs guinéens' : 'franc guinéen',
    'XOF' || 'XAF' => pluriel ? 'francs CFA' : 'franc CFA',
    'EUR' => pluriel ? 'euros' : 'euro',
    'USD' => pluriel ? 'dollars' : 'dollar',
    _ => code,
  };
}
