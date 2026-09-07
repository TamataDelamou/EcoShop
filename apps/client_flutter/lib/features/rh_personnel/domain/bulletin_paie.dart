import 'enums_rh.dart';

/// Projection cliente de `public.paie_bulletins` (M8) — **consultation
/// uniquement** en M8 : l'établissement des bulletins (calcul, validation,
/// export) est le périmètre du module M14 (Comptabilité). `net` est
/// systématiquement recalculé côté serveur (trigger `paie_calcule_net`), le
/// client ne fait jamais foi sur ce montant lors d'une écriture — d'où
/// l'absence de méthode d'écriture dans [RhRepository] pour cette entité.
class BulletinPaie {
  const BulletinPaie({
    required this.id,
    required this.etablissementId,
    required this.employeId,
    required this.contratId,
    required this.periodeDebut,
    required this.periodeFin,
    required this.salaireBase,
    this.primes = 0,
    this.retenues = 0,
    required this.net,
    this.statut = StatutPaie.brouillon,
  });

  factory BulletinPaie.depuisJson(Map<String, dynamic> json) => BulletinPaie(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        employeId: json['employe_id'] as String,
        contratId: json['contrat_id'] as String,
        periodeDebut: DateTime.parse(json['periode_debut'] as String),
        periodeFin: DateTime.parse(json['periode_fin'] as String),
        salaireBase: (json['salaire_base'] as num).toDouble(),
        primes: (json['primes'] as num?)?.toDouble() ?? 0,
        retenues: (json['retenues'] as num?)?.toDouble() ?? 0,
        net: (json['net'] as num).toDouble(),
        statut: StatutPaie.depuisCode(json['statut'] as String?),
      );

  final String id;
  final String etablissementId;
  final String employeId;
  final String contratId;
  final DateTime periodeDebut;
  final DateTime periodeFin;
  final double salaireBase;
  final double primes;
  final double retenues;
  final double net;
  final StatutPaie statut;
}
