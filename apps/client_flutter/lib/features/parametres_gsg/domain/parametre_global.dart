import 'dart:convert';

/// Paramètre global de la plateforme (REG-36), réglé par l'Administrateur
/// GSG : tarifs Premium, quotas du Tuteur IA, seuils, devise…
///
/// La valeur est du JSON : le plus souvent `{"valeur": x}`, parfois une
/// valeur nue (`true`, REG-22). Une valeur simple (nombre, texte, oui/non,
/// nue ou dans `{"valeur": x}`) se règle avec un
/// simple champ. Les autres formes (barèmes, listes) se règlent en JSON.
class ParametreGlobal {
  const ParametreGlobal({required this.cle, required this.valeur, this.description, this.modifieLe});

  final String cle;
  /// Objet, liste ou valeur nue, tel que stocké.
  final Object? valeur;
  final String? description;
  final DateTime? modifieLe;

  factory ParametreGlobal.depuisJson(Map<String, dynamic> json) => ParametreGlobal(
        cle: json['cle'] as String,
        valeur: _lire(json['valeur']),
        description: json['description'] as String?,
        modifieLe: json['updated_at'] == null ? null : DateTime.tryParse(json['updated_at'] as String),
      );

  /// Forme `{"valeur": x}` avec x simple (nombre, texte, oui/non) ?
  bool get estSimple {
    final v = valeurSimple;
    return v is num || v is String || v is bool;
  }

  /// Valeur nue (`true`, `5000`), sans objet autour ?
  bool get estNue => valeur is! Map && valeur is! List;

  Object? get valeurSimple {
    final v = valeur;
    if (v is Map) return v.length == 1 && v.containsKey('valeur') ? v['valeur'] : null;
    return v is List ? null : v;
  }

  static Object? _lire(Object? v) => v is Map ? v.cast<String, dynamic>() : v;

  /// Nom lisible : celui connu, sinon la clé en mots.
  String get libelle => libellesConnus[cle] ?? _enMots(cle);

  /// Valeur courte pour la liste.
  String get apercu {
    if (estSimple) {
      final v = valeurSimple;
      if (v is bool) return v ? 'Oui' : 'Non';
      if (v is num) return _nombre(v);
      return '$v';
    }
    final texte = jsonEncode(valeur);
    return texte.length > 60 ? '${texte.substring(0, 57)}…' : texte;
  }

  static const libellesConnus = {
    'tarif_abonnement_premium_eleve_mensuel': 'Premium élève — prix par mois',
    'tarif_abonnement_premium_eleve_annuel': 'Premium élève — prix par an',
    'quota_tuteur_ia_free_mensuel': 'Tuteur IA gratuit — questions par mois',
    'commission_marketplace_pct': 'Commission de la boutique (%)',
    'devise_defaut': 'Devise par défaut',
    'seuil_effectif_gratuit': 'Effectif gratuit (élèves)',
    'tarif_frais_ia_admin_annuel': 'Frais IA de l’administration — par an',
    'duree_retention_journal_audit': 'Conservation du journal d’audit',
    'code_compte_obligatoire': 'Code du compte obligatoire',
    'controle_sessions': 'Contrôle des sessions',
    'anti_rafale_ia': 'Anti-rafale du Tuteur IA',
    'seuil_anomalie_usage_ia_quotidien': 'Alerte d’usage IA anormal (par jour)',
    'poids_type_conversation_ia': 'Poids des types de conversation IA',
    'bareme_licence_pro': 'Barème de la licence Pro',
    'seuil_signalements_question': 'Signalements avant suspension d’une question',
  };

  static String _enMots(String cle) {
    final mots = cle.replaceAll('_', ' ').trim();
    return mots.isEmpty ? cle : '${mots[0].toUpperCase()}${mots.substring(1)}';
  }

  static String _nombre(num v) {
    if (v is double && v != v.roundToDouble()) return v.toString();
    final entier = v.round().toString();
    final groupes = <String>[];
    for (var i = entier.length; i > 0; i -= 3) {
      groupes.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return groupes.join(' ').replaceFirst('- ', '-');
  }

  /// Lit la saisie d'une valeur simple en gardant le type d'origine.
  /// Renvoie null si la saisie n'a pas le bon type.
  Object? valeurDepuisSaisie(Object? saisie) {
    final brute = _brute(saisie);
    if (brute == null) return null;
    return estNue ? brute : {'valeur': brute};
  }

  Object? _brute(Object? saisie) {
    final actuelle = valeurSimple;
    if (actuelle is bool) return saisie is bool ? saisie : null;
    final texte = '${saisie ?? ''}'.trim();
    if (actuelle is num) {
      final n = num.tryParse(texte.replaceAll(' ', '').replaceAll(',', '.'));
      if (n == null) return null;
      return actuelle is int && n == n.roundToDouble() ? n.round() : n;
    }
    return texte.isEmpty ? null : texte;
  }

  /// Lit une saisie JSON ; null si ce n'est pas un objet JSON.
  static Map<String, dynamic>? objetDepuisJson(String texte) {
    final v = jsonDepuisSaisie(texte);
    return v is Map ? v.cast<String, dynamic>() : null;
  }

  /// Lit une saisie JSON de même forme que la valeur actuelle (objet ou
  /// liste) ; null sinon.
  Object? jsonDeMemeForme(String texte) {
    final v = jsonDepuisSaisie(texte);
    if (valeur is Map) return v is Map ? v.cast<String, dynamic>() : null;
    if (valeur is List) return v is List ? v : null;
    return null;
  }

  static Object? jsonDepuisSaisie(String texte) {
    try {
      return jsonDecode(texte);
    } catch (_) {
      return null;
    }
  }
}

/// Un changement passé (qui l'a fait est connu du serveur ; on montre quand).
class ChangementParametre {
  const ChangementParametre({required this.ancienne, required this.nouvelle, required this.le});

  final Object? ancienne;
  final Object? nouvelle;
  final DateTime le;

  factory ChangementParametre.depuisJson(Map<String, dynamic> json) => ChangementParametre(
        ancienne: ParametreGlobal._lire(json['ancienne_valeur']),
        nouvelle: ParametreGlobal._lire(json['nouvelle_valeur']),
        le: DateTime.parse(json['modifie_le'] as String),
      );
}

class ErreurParametre implements Exception {
  const ErreurParametre(this.code);

  final String code;

  String get message => switch (code) {
        'HORS_LIGNE' => 'Pas de réseau : un paramètre de la plateforme se modifie seulement en ligne.',
        'PERMISSION_REFUSEE' => 'Réservé à l’Administrateur GSG.',
        'PARAMETRE_INCONNU' => 'Ce paramètre n’existe plus.',
        'VALEUR_INVALIDE' => 'Valeur invalide : gardez la même forme JSON, par exemple {"valeur": 5000}.',
        'TYPE_INVALIDE' => 'La valeur doit garder son type (un nombre reste un nombre).',
        _ => 'Enregistrement impossible pour le moment. Réessayez.',
      };

  @override
  String toString() => code;
}
