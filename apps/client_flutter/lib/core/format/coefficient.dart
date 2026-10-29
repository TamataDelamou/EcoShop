/// Coefficient d'une matière, décimal depuis REG-33 (0,5 ; 1,5 ; 2,5…).
///
/// Lu depuis le serveur (nombre JSON, entier ou décimal, parfois texte) ;
/// affiché à la française, sans zéro inutile : 5 → « 5 », 2.5 → « 2,5 ».
double? lireCoefficient(Object? valeur) => switch (valeur) {
      null => null,
      num n => n.toDouble(),
      String s => double.tryParse(s.replaceAll(',', '.')),
      _ => null,
    };

String formaterCoefficient(double coefficient) {
  if (coefficient == coefficient.roundToDouble()) return coefficient.toInt().toString();
  var texte = coefficient.toStringAsFixed(2);
  while (texte.endsWith('0')) {
    texte = texte.substring(0, texte.length - 1);
  }
  return texte.replaceAll('.', ',');
}
