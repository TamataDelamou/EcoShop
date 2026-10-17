import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_paiement_mobile_repository.dart';
import '../domain/paiement_mobile_repository.dart';
import '../domain/transaction_mobile_money.dart';
import 'lanceur_url.dart';

/// Port des paiements mobile money — toujours réseau direct (voir la doc
/// de [PaiementMobileRepository]).
final paiementMobileRepositoryProvider = Provider<PaiementMobileRepository>((ref) {
  return SupabasePaiementMobileRepository(ref.watch(supabaseClientProvider));
});

final lanceurUrlProvider = Provider<LanceurUrl>((ref) => const LanceurUrlExterne());

/// Intervalle entre deux lectures du statut pendant le suivi d'un paiement.
/// Surchargé dans les tests.
final intervalleSuiviPaiementProvider = Provider<Duration>((ref) => const Duration(seconds: 3));

/// Suivi en direct d'une transaction : relit le statut à intervalle régulier
/// jusqu'à un statut final (confirmé ou non abouti), puis s'arrête. Une
/// lecture ratée (réseau) n'interrompt pas le suivi : la suivante réessaie.
final suiviTransactionProvider =
    StreamProvider.autoDispose.family<TransactionMobileMoney, String>((ref, transactionId) async* {
  final depot = ref.watch(paiementMobileRepositoryProvider);
  final intervalle = ref.watch(intervalleSuiviPaiementProvider);

  while (true) {
    TransactionMobileMoney? lue;
    try {
      lue = await depot.lireTransaction(transactionId);
    } on ErreurPaiementMobile {
      lue = null;
    }
    if (lue != null) {
      yield lue;
      if (lue.statut.estFinal) return;
    }
    await Future<void>.delayed(intervalle);
  }
});

final etatOrangeMoneyProvider = FutureProvider.autoDispose.family<EtatOrangeMoney, String>((ref, etablissementId) {
  return ref.watch(paiementMobileRepositoryProvider).etatOrangeMoney(etablissementId);
});

final transactionsMobilesEtablissementProvider =
    FutureProvider.autoDispose.family<List<TransactionMobileMoney>, String>((ref, etablissementId) {
  return ref.watch(paiementMobileRepositoryProvider).transactionsEtablissement(etablissementId);
});

/// Indicateurs du jour pour le tableau de bord Direction — affichage
/// seulement, calculés sur les transactions déjà lues (le serveur fait foi).
class IndicateursMobileMoney {
  const IndicateursMobileMoney({
    required this.montantConfirmeDuJour,
    required this.confirmeesDuJour,
    required this.enCours,
    required this.nonAbouties,
  });

  factory IndicateursMobileMoney.depuis(List<TransactionMobileMoney> transactions, DateTime maintenant) {
    final debutJour = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final duJour = transactions.where((t) => !t.creeLe.toLocal().isBefore(debutJour)).toList();
    final confirmees = duJour.where((t) => t.statut == StatutTransactionMobile.reussi).toList();
    return IndicateursMobileMoney(
      montantConfirmeDuJour: confirmees.fold<double>(0, (somme, t) => somme + t.montant),
      confirmeesDuJour: confirmees.length,
      enCours: transactions.where((t) => !t.statut.estFinal).length,
      nonAbouties: duJour.where((t) => t.statut == StatutTransactionMobile.echoue).length,
    );
  }

  final double montantConfirmeDuJour;
  final int confirmeesDuJour;
  final int enCours;
  final int nonAbouties;
}
