import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../domain/scolarite_repository.dart';

/// Frais de scolarité par niveau de classe et répartition automatique en
/// tranches ou en mois (REG-39, migration 20260906001594).
class FraisRepository {
  const FraisRepository(this._client);

  final SupabaseClient _client;

  /// Tarif d'un niveau (toutes ses classes) ; [niveauId] nul : tarif par
  /// défaut. [montantAnnuel] nul : le niveau revient au tarif par défaut.
  Future<void> enregistrerTarif({
    required String etablissementId,
    required String anneeId,
    String? niveauId,
    double? montantAnnuel,
    double fraisInscription = 0,
  }) =>
      _appeler('enregistrer_frais_niveau', {
        'p_etablissement': etablissementId,
        'p_annee': anneeId,
        'p_niveau': niveauId,
        'p_montant_annuel': montantAnnuel,
        'p_frais_inscription': fraisInscription,
      });

  /// Remplace les paliers de l'année ([paliers] vide : paiement en une fois).
  Future<void> repartir({
    required String etablissementId,
    required String anneeId,
    required List<PalierPropose> paliers,
  }) =>
      _appeler('repartir_paliers', {
        'p_etablissement': etablissementId,
        'p_annee': anneeId,
        'p_paliers': [for (final p in paliers) p.versJson()],
      });

  Future<void> _appeler(String fonction, Map<String, dynamic> params) async {
    try {
      await _client.rpc<dynamic>(fonction, params: params);
    } on PostgrestException catch (e) {
      for (final code in const [
        'FRAIS_FIXES_PAR_RESEAU',
        'PERMISSION_REFUSEE',
        'SOMME_DIFFERENTE_DE_100',
        'MONTANT_INVALIDE',
        'TROP_DE_PALIERS',
      ]) {
        if (e.message.contains(code)) throw ErreurScolarite(code);
      }
      throw ErreurScolarite('INCONNU', e.message);
    }
  }
}

/// Palier calculé par la répartition automatique.
class PalierPropose {
  const PalierPropose(this.nom, this.pourcentage, {this.dateLimite});

  final String nom;
  final double pourcentage;
  final DateTime? dateLimite;

  Map<String, dynamic> versJson() {
    String d(int v) => v.toString().padLeft(2, '0');
    final date = dateLimite;
    return {
      'nom': nom,
      'pourcentage': pourcentage,
      if (date != null) 'date_limite': '${date.year}-${d(date.month)}-${d(date.day)}',
    };
  }
}

const moisFrancais = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
  'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
];

/// Parts égales arrondies au centième ; le dernier palier complète à 100 %.
List<double> partsEgales(int n) {
  if (n <= 0) return const [];
  final part = (10000 / n).floor() / 100;
  return [for (var i = 0; i < n; i++) i == n - 1 ? double.parse((100 - part * (n - 1)).toStringAsFixed(2)) : part];
}

/// [n] tranches égales, sans date limite.
List<PalierPropose> repartitionTranches(int n) {
  final parts = partsEgales(n);
  return [for (var i = 0; i < n; i++) PalierPropose('Tranche ${i + 1}', parts[i])];
}

/// [n] mensualités à partir du mois [premierMois] (1 à 12) de [annee] ;
/// date limite : le [jourLimite] de chaque mois.
List<PalierPropose> repartitionMensuelle({
  required int premierMois,
  required int n,
  required int annee,
  int jourLimite = 10,
}) {
  final parts = partsEgales(n);
  return [
    for (var i = 0; i < n; i++)
      () {
        final date = DateTime(annee, premierMois + i, jourLimite);
        return PalierPropose(moisFrancais[date.month - 1], parts[i], dateLimite: date);
      }(),
  ];
}

/// Montants de chaque palier pour un tarif annuel, arrondis au franc ; le
/// dernier absorbe l'arrondi pour que la somme fasse le tarif exact.
List<int> montantsParPalier(double montantAnnuel, List<double> pourcentages) {
  final total = montantAnnuel.round();
  final montants = <int>[];
  var cumul = 0;
  for (var i = 0; i < pourcentages.length; i++) {
    final m = i == pourcentages.length - 1 ? total - cumul : (montantAnnuel * pourcentages[i] / 100).round();
    montants.add(m);
    cumul += m;
  }
  return montants;
}

final fraisRepositoryProvider = Provider<FraisRepository>((ref) => FraisRepository(ref.watch(supabaseClientProvider)));
