import '../db/cache_document_store.dart';
import 'lecture_patiente.dart';

/// Lecture d'une liste « serveur si rapide, appareil sinon », partagée par
/// les dépôts hors ligne des modules M5 à M11 (notes, scolarité, RH, vie
/// scolaire, planification, rapports, communication).
///
/// Même règle que [lireAvecPatience] : la liste du serveur est gardée sous
/// `{'lignes': [...]}` (format inchangé, les copies déjà présentes sur les
/// téléphones restent lisibles) ; si le serveur échoue ([estPanne]) ou met
/// plus de [patience] à répondre alors qu'une copie existe, la copie est
/// servie et la réponse tardive gardée en arrière-plan.
Future<List<T>> lireListeAvecCache<T>({
  required CacheDocumentStore cache,
  required String type,
  required String cle,
  required Future<List<T>> Function() lire,
  required Map<String, dynamic> Function(T) versJson,
  required T Function(Map<String, dynamic>) depuisJson,
  required bool Function(Object erreur) estPanne,
  Duration patience = delaiPatienceLecture,
}) async {
  final resultat = await lireAvecPatience<List<T>>(
    serveur: lire,
    appareil: () async {
      final lu = await cache.lireDocumentDate(type, cle);
      if (lu == null) return null;
      final lignes = (lu.document['lignes'] as List<dynamic>)
          .map((l) => depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
      return (valeur: lignes, date: lu.misAJourLe);
    },
    garder: (liste) => cache.ecrireDocument(type, cle, {
      'lignes': liste.map(versJson).toList(growable: false),
    }),
    estPanne: estPanne,
    patience: patience,
  );
  return resultat.valeur;
}
