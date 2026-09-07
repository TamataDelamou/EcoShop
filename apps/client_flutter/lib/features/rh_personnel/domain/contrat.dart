import 'enums_rh.dart';

/// Projection cliente de `public.contrats` (M8). Écriture réservée à la RH,
/// toujours en ligne (pas de file `sync_queue` : un contrat engage
/// juridiquement l'établissement, une confirmation réseau immédiate est
/// requise avant de le considérer créé).
class Contrat {
  const Contrat({
    required this.id,
    required this.etablissementId,
    required this.employeId,
    this.type = TypeContrat.cdd,
    required this.dateDebut,
    this.dateFin,
    required this.salaireBase,
    this.renouvellementAuto = false,
    this.actif = true,
  });

  factory Contrat.depuisJson(Map<String, dynamic> json) => Contrat(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        employeId: json['employe_id'] as String,
        type: TypeContrat.depuisCode(json['type'] as String?),
        dateDebut: DateTime.parse(json['date_debut'] as String),
        dateFin: json['date_fin'] == null ? null : DateTime.parse(json['date_fin'] as String),
        salaireBase: (json['salaire_base'] as num).toDouble(),
        renouvellementAuto: json['renouvellement_auto'] as bool? ?? false,
        actif: json['actif'] as bool? ?? true,
      );

  /// Colonnes réelles de `public.contrats` — pour la création/édition
  /// (`id` omis à la création : généré côté serveur).
  Map<String, dynamic> versJsonEcriture() => {
        'etablissement_id': etablissementId,
        'employe_id': employeId,
        'type': type.code,
        'date_debut': _dateIso(dateDebut),
        'date_fin': dateFin == null ? null : _dateIso(dateFin!),
        'salaire_base': salaireBase,
        'renouvellement_auto': renouvellementAuto,
        'actif': actif,
      };

  final String id;
  final String etablissementId;
  final String employeId;
  final TypeContrat type;
  final DateTime dateDebut;
  final DateTime? dateFin;
  final double salaireBase;
  final bool renouvellementAuto;
  final bool actif;

  /// Contrat en cours à la date du jour (utile pour l'affichage « contrat
  /// actuel » sur la fiche employé).
  bool get estEnCours {
    if (!actif) return false;
    final aujourdHui = DateTime.now();
    return dateFin == null || !dateFin!.isBefore(DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day));
  }

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
