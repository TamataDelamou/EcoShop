import 'package:url_launcher/url_launcher.dart';

/// Ouvre la page de paiement Orange Money hors de l'application (navigateur
/// ou application Orange Money si elle intercepte le lien). Abstrait pour
/// que les tests n'ouvrent jamais rien.
abstract interface class LanceurUrl {
  Future<bool> ouvrir(Uri url);
}

class LanceurUrlExterne implements LanceurUrl {
  const LanceurUrlExterne();

  @override
  Future<bool> ouvrir(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
}
