import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Lecture à voix haute (REG-37) par la synthèse vocale du téléphone, sans
/// réseau : questions des petites classes, bilan et conseils aux parents
/// qui lisent peu. En français ; les langues nationales (pular, malinké,
/// soussou) demanderont des enregistrements, la synthèse ne les parle pas.
abstract interface class LecteurVocal {
  /// Lit [texte] ; faux si le téléphone n'a pas de voix française.
  Future<bool> lire(String texte);

  Future<void> arreter();
}

class LecteurVocalTelephone implements LecteurVocal {
  LecteurVocalTelephone([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool? _pret;

  Future<bool> _preparer() async {
    if (_pret != null) return _pret!;
    try {
      final disponible = await _tts.isLanguageAvailable('fr-FR');
      if (disponible == false) {
        _pret = false;
        return false;
      }
      await _tts.setLanguage('fr-FR');
      await _tts.setSpeechRate(0.45); // un peu lent : enfants et parents
      await _tts.awaitSpeakCompletion(false);
      _pret = true;
    } catch (_) {
      _pret = false;
    }
    return _pret!;
  }

  @override
  Future<bool> lire(String texte) async {
    if (texte.trim().isEmpty || !await _preparer()) return false;
    try {
      await _tts.stop();
      await _tts.speak(texteALire(texte));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> arreter() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// Rend un texte prononçable : trous « [[1]] » lus « blanc », « % » lu
/// « pour cent », guillemets et flèches retirés.
String texteALire(String texte) => texte
    .replaceAll(RegExp(r'\[\[\w+\]\]|……\(\w+\)'), ' blanc ')
    .replaceAll('%', ' pour cent')
    .replaceAll(RegExp('[«»→]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final lecteurVocalProvider = Provider<LecteurVocal>((ref) => LecteurVocalTelephone());
