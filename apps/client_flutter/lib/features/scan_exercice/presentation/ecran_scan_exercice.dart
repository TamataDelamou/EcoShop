import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/glass_card.dart';
import '../../chat_ia/application/chat_ia_providers.dart';
import '../../chat_ia/domain/chat_ia_repository.dart';
import '../../chat_ia/domain/message_chat_ia.dart';
import '../../chat_ia/presentation/widgets/bulle_message_ia.dart';
import '../application/scan_exercice_providers.dart';

/// Écran « Scan et résolution d'exercice » (M16, sous-livrable 5/7, cahier
/// §21.5) — outil élève uniquement.
///
/// Flux respecté à la lettre : photo → reconnaissance de texte (ML Kit,
/// 100% embarquée sur l'appareil — LA PHOTO NE QUITTE JAMAIS L'APPAREIL,
/// seul le texte reconnu est transmis, voir la migration
/// `20260906001509`) → identification matière/chapitre + première réponse de
/// guidage (`demarrer_scan_exercice`) → guidage progressif jusqu'à
/// résolution, en réutilisant intégralement `ChatIaRepository` pour les
/// tours suivants (même infrastructure que le sous-livrable 3/7).
///
/// Le consentement est capturé À CHAQUE scan (donnée scolaire d'un mineur) —
/// jamais un verrou persistant comme Parent IA.
class EcranScanExercice extends ConsumerStatefulWidget {
  const EcranScanExercice({
    super.key,
    required this.etablissementId,
    required this.ficheEleveId,
  });

  final String etablissementId;
  final String ficheEleveId;

  @override
  ConsumerState<EcranScanExercice> createState() => _EcranScanExerciceState();
}

class _EcranScanExerciceState extends ConsumerState<EcranScanExercice> {
  final _texteControleur = TextEditingController();
  final _messageControleur = TextEditingController();
  final _defilement = ScrollController();
  final List<MessageChatIa> _entrees = [];

  bool _consentement = false;
  bool _ocrEnCours = false;
  bool _demarrageEnCours = false;
  bool _envoiEnCours = false;

  String? _conversationId;
  String? _matiere;
  String? _chapitre;

  @override
  void dispose() {
    _texteControleur.dispose();
    _messageControleur.dispose();
    _defilement.dispose();
    super.dispose();
  }

  void _afficherErreur(String code) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Assistant indisponible ($code). Réessayez.')),
    );
  }

  void _defilerVersLeBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_defilement.hasClients) return;
      _defilement.animateTo(
        _defilement.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _capturerPhoto(ImageSource source) async {
    final XFile? photo;
    try {
      photo = await ImagePicker().pickImage(source: source, imageQuality: 85);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'accéder à la caméra/galerie.')),
      );
      return;
    }
    if (photo == null) return;

    setState(() => _ocrEnCours = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final resultat = await recognizer.processImage(InputImage.fromFilePath(photo.path));
      if (!mounted) return;
      setState(() {
        _texteControleur.text = resultat.text;
        _ocrEnCours = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _ocrEnCours = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de la reconnaissance de texte. Réessayez.')),
      );
    } finally {
      await recognizer.close();
    }
  }

  Future<void> _demarrer() async {
    final texte = _texteControleur.text.trim();
    if (texte.isEmpty || !_consentement || _demarrageEnCours) return;

    setState(() => _demarrageEnCours = true);
    final depotScan = ref.read(scanExerciceRepositoryProvider);
    final depotChat = ref.read(chatIaRepositoryProvider);
    try {
      final resultat = await depotScan.demarrerScan(
        etablissementId: widget.etablissementId,
        ficheEleveId: widget.ficheEleveId,
        texteExtrait: texte,
        consentement: true,
      );

      final messageUtilisateur = await depotChat.enregistrerMessage(
        conversationId: resultat.conversationId,
        sender: 'user',
        content: texte,
      );
      final messageAssistant = await depotChat.enregistrerMessage(
        conversationId: resultat.conversationId,
        sender: 'assistant',
        content: resultat.reply,
      );

      if (!mounted) return;
      setState(() {
        _conversationId = resultat.conversationId;
        _matiere = resultat.matiere;
        _chapitre = resultat.chapitre;
        _entrees
          ..add(messageUtilisateur)
          ..add(messageAssistant);
        _demarrageEnCours = false;
      });
      _defilerVersLeBas();
    } on ErreurChatIa catch (e) {
      if (!mounted) return;
      setState(() => _demarrageEnCours = false);
      _afficherErreur(e.code);
    }
  }

  Future<void> _poursuivre(String texte) async {
    final saisie = texte.trim();
    if (saisie.isEmpty || _envoiEnCours || _conversationId == null) return;
    _messageControleur.clear();
    setState(() => _envoiEnCours = true);

    final depotChat = ref.read(chatIaRepositoryProvider);
    try {
      final reponse = await depotChat.envoyerMessage(
        conversationId: _conversationId,
        message: saisie,
      );

      final messageUtilisateur = await depotChat.enregistrerMessage(
        conversationId: _conversationId!,
        sender: 'user',
        content: saisie,
      );
      final messageAssistant = await depotChat.enregistrerMessage(
        conversationId: _conversationId!,
        sender: 'assistant',
        content: reponse.reponse,
      );

      if (!mounted) return;
      setState(() {
        _entrees
          ..add(messageUtilisateur)
          ..add(messageAssistant);
      });
      _defilerVersLeBas();
    } on ErreurChatIa catch (e) {
      _afficherErreur(e.code);
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan-Exercice')),
      body: _conversationId == null ? _vueCapture(context) : _vueGuidage(context),
    );
  }

  Widget _vueCapture(BuildContext context) {
    final palette = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Photographiez votre exercice, vérifiez le texte reconnu puis '
            'lancez l\'analyse — la photo elle-même ne quitte jamais votre '
            'appareil, seul le texte est envoyé.',
            style: TextStyle(color: palette.encreSecondaire),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _ocrEnCours ? null : () => _capturerPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Prendre une photo'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _ocrEnCours ? null : () => _capturerPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galerie'),
                ),
              ),
            ],
          ),
          if (_ocrEnCours)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 16),
          Text('Texte reconnu', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.all(8),
            enfant: TextField(
              controller: _texteControleur,
              minLines: 4,
              maxLines: 10,
              enabled: !_demarrageEnCours,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Le texte reconnu apparaîtra ici — vous pouvez le corriger avant de continuer.',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _consentement,
            onChanged: _demarrageEnCours ? null : (v) => setState(() => _consentement = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              "J'autorise l'envoi de ce texte à l'assistant IA pour m'aider à résoudre cet exercice.",
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _texteControleur.text.trim().isEmpty || !_consentement || _demarrageEnCours
                ? null
                : _demarrer,
            child: _demarrageEnCours
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Analyser'),
          ),
        ],
      ),
    );
  }

  Widget _vueGuidage(BuildContext context) {
    final palette = context.palette;
    final etiquette = [?_matiere, ?_chapitre].join(' · ');

    return Column(
      children: [
        if (etiquette.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
                label: Text(etiquette),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _defilement,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _entrees.length,
            itemBuilder: (context, i) => BulleMessageIa(entree: _entrees[i]),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              enfant: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageControleur,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !_envoiEnCours,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Continuez la résolution…',
                      ),
                      onSubmitted: _poursuivre,
                    ),
                  ),
                  _envoiEnCours
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: Icon(Icons.send, color: palette.primaire),
                          onPressed: () => _poursuivre(_messageControleur.text),
                        ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
