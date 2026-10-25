import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/theme/ambiance_visuelle.dart';
import '../../../core/theme/app_theme_variant.dart';
import '../../../core/theme/couleur_identite.dart';
import '../../export_pdf/application/pdf_palette.dart';
import '../../auth/application/auth_providers.dart';
import '../../referentiel/application/referentiel_providers.dart';
import '../data/identite_visuelle_repository.dart';
import '../data/theme_preference_store.dart';

final _themePreferenceStoreProvider = Provider<ThemePreferenceStore>((ref) {
  final store = CacheDocumentStore(ref.watch(databaseProvider), 'preferences');
  return ThemePreferenceStore(store);
});

/// Préférence d'apparence (clair/sombre/système) de l'utilisateur, persistée
/// localement (chargement asynchrone, [ThemeMode.system] tant qu'elle n'est
/// pas connue — jamais de flash clair→sombre au démarrage sur un mobile déjà
/// réglé en sombre).
final themeModeProvider =
    AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() {
    return ref.watch(_themePreferenceStoreProvider).lire();
  }

  Future<void> definir(ThemeMode mode) async {
    state = AsyncData(mode);
    await ref.read(_themePreferenceStoreProvider).ecrire(mode);
  }
}

/// Type de système éducatif de chaque pays (code ISO → `type_systeme`),
/// gardé sur le téléphone : le thème ne lit jamais le réseau.
final systemesPaysLocauxProvider = FutureProvider<Map<String, String>>((ref) async {
  try {
    final document = await ref.watch(_themePreferenceStoreProvider).lireSystemesPays();
    return document;
  } catch (_) {
    return const {};
  }
});

/// Complète la copie du téléphone quand le pays de l'établissement n'y est
/// pas encore : liste des pays relue en arrière-plan. Ne lève jamais : sans
/// réseau, le thème reste sur la charte par défaut.
final _completerSystemesPaysProvider = FutureProvider<void>((ref) async {
  try {
    final pays = await ref.watch(paysPedagogiquesProvider.future);
    if (pays.isEmpty) return;
    await ref.read(_themePreferenceStoreProvider).ecrireSystemesPays({
      for (final p in pays) p.codeIso: p.typeSysteme,
    });
    ref.invalidate(systemesPaysLocauxProvider);
  } catch (_) {
    // Hors connexion ou serveur indisponible : nouvel essai au prochain
    // lancement.
  }
});

/// Variante visuelle active, dérivée du pays pédagogique de l'établissement
/// actif (M4 : `pays_pedagogiques.type_systeme`) — jamais un choix libre de
/// l'utilisateur : la charte graphique reflète le système éducatif réel de
/// l'établissement. Repli sur [AppThemeVariant.francophoneCfa] tant que le
/// type du pays n'est pas connu sur le téléphone. Ne dépend jamais du
/// réseau et ne lève jamais (le thème est lu par la racine de l'app : une
/// erreur ici ferait planter tous les écrans).
final themeVariantProvider = Provider<AppThemeVariant>((ref) {
  final paysCode = ref.watch(etablissementActifProvider)?.paysCode;
  if (paysCode == null) return AppThemeVariant.francophoneCfa;

  final type = ref.watch(systemesPaysLocauxProvider).valueOrNull?[paysCode];
  if (type != null) return AppThemeVariant.depuisCodeSysteme(type);

  ref.watch(_completerSystemesPaysProvider);
  return AppThemeVariant.francophoneCfa;
});

/// Ambiance personnelle choisie par l'utilisateur (REG-07 C), mémorisée sur
/// l'appareil. [AmbianceVisuelle.etablissement] tant qu'elle n'est pas lue.
final ambianceProvider =
    AsyncNotifierProvider<AmbianceNotifier, AmbianceVisuelle>(AmbianceNotifier.new);

class AmbianceNotifier extends AsyncNotifier<AmbianceVisuelle> {
  @override
  Future<AmbianceVisuelle> build() {
    return ref.watch(_themePreferenceStoreProvider).lireAmbiance();
  }

  Future<void> definir(AmbianceVisuelle ambiance) async {
    state = AsyncData(ambiance);
    await ref.read(_themePreferenceStoreProvider).ecrireAmbiance(ambiance);
  }
}

/// Identité visuelle de l'établissement actif (REG-07 B) : couleur choisie
/// par la Direction (ajustée à l'affichage pour rester lisible) et URL
/// publique du logo. Vide = charte par défaut du pays.
class IdentiteEtablissement {
  const IdentiteEtablissement({this.couleur, this.logoUrl});

  static const vide = IdentiteEtablissement();

  final Color? couleur;
  final String? logoUrl;
}

final identiteEtablissementProvider = Provider<IdentiteEtablissement>((ref) {
  final etablissement = ref.watch(etablissementActifProvider);
  if (etablissement == null) return IdentiteEtablissement.vide;
  final chemin = etablissement.logoChemin;
  return IdentiteEtablissement(
    couleur: CouleurIdentite.depuisHex(etablissement.couleurIdentite),
    logoUrl: chemin == null
        ? null
        : ref.watch(supabaseClientProvider).storage.from(bucketLogosEtablissements).getPublicUrl(chemin),
  );
});

/// Identité pour les documents imprimés : couleur + octets du logo,
/// téléchargés une fois. Un logo injoignable (hors connexion) n'empêche
/// jamais l'export : le document sort simplement sans logo.
final identitePdfProvider = FutureProvider<IdentitePdf>((ref) async {
  final identite = ref.watch(identiteEtablissementProvider);
  final url = identite.logoUrl;
  if (url == null) return IdentitePdf(couleur: identite.couleur);
  try {
    final reponse = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (reponse.statusCode != 200) return IdentitePdf(couleur: identite.couleur);
    return IdentitePdf(couleur: identite.couleur, logo: reponse.bodyBytes);
  } catch (_) {
    return IdentitePdf(couleur: identite.couleur);
  }
});

/// Port d'écriture de l'identité visuelle (Direction).
final identiteVisuelleRepositoryProvider = Provider<IdentiteVisuelleRepository>((ref) {
  return SupabaseIdentiteVisuelleRepository(ref.watch(supabaseClientProvider));
});

/// Sélection d'une image de logo dans la galerie (abstraite pour les tests).
typedef ImageLogo = ({Uint8List octets, String extension});

final selecteurLogoProvider = Provider<Future<ImageLogo?> Function()>((ref) {
  return () async {
    final fichier = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 90,
    );
    if (fichier == null) return null;
    final nom = fichier.name.toLowerCase();
    return (octets: await fichier.readAsBytes(), extension: nom.endsWith('.png') ? 'png' : 'jpeg');
  };
});
