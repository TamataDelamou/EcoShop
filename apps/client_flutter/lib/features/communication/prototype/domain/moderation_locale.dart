/// Détection heuristique de termes inappropriés — **prototype local**, un
/// simple lexique français, pas un service de modération réel (pas d'appel
/// serveur, pas de file de signalement, pas d'apprentissage). Sert de
/// démonstrateur pour la future intégration IA de modération une fois le
/// backend de messagerie livré (voir `prototype/README` dans le rapport de
/// clôture M9).
///
/// Comme partout ailleurs dans le projet, le signal ne bloque jamais l'envoi
/// — il informe l'auteur et, plus tard, la modération humaine.
final RegExp _lexiqueInapproprie = RegExp(
  r'(idiot|stupide|débile|debile|con(ne)?|imb[ée]cile|merde|nul(le)?|insulte|menace)',
  caseSensitive: false,
);

bool contientTermeInapproprie(String texte) => _lexiqueInapproprie.hasMatch(texte);
