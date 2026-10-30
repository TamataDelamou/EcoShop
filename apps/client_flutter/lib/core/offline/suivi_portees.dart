/// Suivi des portées lues (REG-35, lot 3 — synchronisation par
/// différences).
///
/// Pour chaque portée (`classe:<id>`, `fiche:<id>`, `etablissement:<id>`),
/// la date de sa dernière lecture complète, **à l'heure du serveur** (celle
/// que renvoie `portees_modifiees` avant les lectures) : l'horloge du
/// téléphone, souvent fausse, n'entre jamais dans la comparaison.
library;

/// Au-delà, une portée est relue même si le serveur ne la signale pas
/// modifiée : les copies contiennent aussi des noms venus d'autres tables
/// (enseignant, matière) que le journal ne suit pas.
const ageMaxPortee = Duration(days: 7);

class SuiviPortees {
  const SuiviPortees(this.lues);

  /// Portée → date de lecture (heure du serveur).
  final Map<String, DateTime> lues;

  static const vide = SuiviPortees({});

  static SuiviPortees depuisJson(Map<String, dynamic>? json) {
    final brut = json?['lues'];
    if (brut is! Map) return vide;
    final lues = <String, DateTime>{};
    for (final entree in brut.entries) {
      final date = DateTime.tryParse('${entree.value}');
      if (date != null) lues['${entree.key}'] = date.toUtc();
    }
    return SuiviPortees(lues);
  }

  Map<String, dynamic> versJson() => {
        'lues': {for (final e in lues.entries) e.key: e.value.toUtc().toIso8601String()},
      };

  /// Portées à soumettre au serveur : celles lues il y a moins de
  /// [ageMaxPortee] (les autres seront relues de toute façon). [maintenant]
  /// est l'heure du téléphone, utilisée seulement pour cet âge maximal.
  List<Map<String, String>> demandes(DateTime maintenant) => [
        for (final e in lues.entries)
          if (maintenant.toUtc().difference(e.value) < ageMaxPortee)
            if (_decouper(e.key) case (final type, final id))
              {'portee': type, 'id': id, 'depuis': e.value.toIso8601String()},
      ];

  /// Portées dont la copie est à jour : soumises au serveur et non
  /// signalées modifiées.
  Set<String> inchangees({required Set<String> modifiees, required DateTime maintenant}) => {
        for (final d in demandes(maintenant))
          if (!modifiees.contains('${d['portee']}:${d['id']}')) '${d['portee']}:${d['id']}',
      };

  /// Suivi après un amorçage terminé : [relues] lues entièrement à
  /// [luLe] ; les portées ni relues ni vues ([vues]) sont oubliées (classe
  /// fermée, enfant délié).
  SuiviPortees apres({required Set<String> relues, required Set<String> vues, required DateTime luLe}) =>
      SuiviPortees({
        for (final e in lues.entries)
          if (vues.contains(e.key) && !relues.contains(e.key)) e.key: e.value,
        for (final p in relues) p: luLe.toUtc(),
      });

  static (String, String)? _decouper(String portee) {
    final i = portee.indexOf(':');
    if (i <= 0 || i == portee.length - 1) return null;
    return (portee.substring(0, i), portee.substring(i + 1));
  }
}

/// Réponse de `portees_modifiees` : heure du serveur et portées modifiées.
({DateTime? maintenant, Set<String> modifiees}) lireReponsePortees(Object? json) {
  if (json is! Map) return (maintenant: null, modifiees: const {});
  final maintenant = DateTime.tryParse('${json['maintenant']}')?.toUtc();
  final liste = json['modifiees'];
  return (
    maintenant: maintenant,
    modifiees: {
      if (liste is List)
        for (final m in liste)
          if (m is Map && m['portee'] != null && m['id'] != null) '${m['portee']}:${m['id']}',
    },
  );
}
