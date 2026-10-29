import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pages légales du site de Global Service Groupe (REG-31). Adresses
/// déclarées sur l'écran de consentement Google et au Play Store : ne pas
/// les changer sans mettre à jour ces deux déclarations.
abstract final class LiensLegaux {
  static final Uri confidentialite = Uri.parse('https://globalservicegroupe.com/confidentialite/');
  static final Uri conditions = Uri.parse('https://globalservicegroupe.com/conditions/');
  static final Uri suppressionCompte = Uri.parse('https://globalservicegroupe.com/suppression-compte/');
  static const String courriel = 'contact@globalservicegroupe.com';
}

/// Ouvre une page légale dans le navigateur du téléphone. Sans navigateur ou
/// sans connexion, l'adresse est affichée pour être notée.
Future<void> ouvrirLienLegal(BuildContext context, Uri adresse) async {
  final messager = ScaffoldMessenger.maybeOf(context);
  var ouvert = false;
  try {
    ouvert = await launchUrl(adresse, mode: LaunchMode.externalApplication);
  } catch (_) {
    ouvert = false;
  }
  if (!ouvert) {
    messager?.showSnackBar(SnackBar(content: Text('Ouvrez ${adresse.host}${adresse.path} dans votre navigateur.')));
  }
}
