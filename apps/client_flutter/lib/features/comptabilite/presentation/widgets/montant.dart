import 'package:intl/intl.dart';

/// Formate un montant avec séparateurs de milliers, ex. `230 000`.
String formaterMontant(double montant) => NumberFormat.decimalPattern('fr').format(montant);
