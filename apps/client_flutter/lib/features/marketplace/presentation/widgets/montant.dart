import 'package:intl/intl.dart';

/// Formate un montant avec séparateurs de milliers et devise, ex. `230 000 GNF`.
String formaterMontant(double montant, String devise) {
  final formateur = NumberFormat.decimalPattern('fr');
  return '${formateur.format(montant)} $devise';
}
