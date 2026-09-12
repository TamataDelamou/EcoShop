import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/glass_card.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../../scolarite/domain/classe.dart';
import '../application/chat_ia_providers.dart';
import '../domain/chat_ia_repository.dart';
import '../domain/detail_eleve_pseudonymise.dart';
import '../domain/message_chat_ia.dart';
import '../domain/persona_ia.dart';
import 'widgets/badge_signal_ia_chat.dart';
import 'widgets/bulle_message_ia.dart';

/// Écran de chat IA à rôles (M16, sous-livrable 3/7) — un seul écran pour
/// les 3 personas (Tuteur-IA/élève, Prof-Assistant/enseignant,
/// Directeur-Adviser/direction) : le flux et les garanties de sécurité sont
/// strictement les mêmes, seul le persona affiché change. Le rôle réel n'est
/// jamais choisi ici — il est re-dérivé côté serveur à chaque appel
/// (`determiner_role_ia`), ce [persona] ne sert qu'à l'affichage (titre,
/// icône) et est cohérent par construction avec `RoleRacine` du profil actif
/// (voir `PersonaIa.depuisRoleRacine`, appelé par l'appelant).
///
/// Portée volontairement limitée à cette passe : une conversation par
/// ouverture d'écran (pas de liste de conversations passées à reprendre) —
/// le flux à 3 couches (déclenchement structuré → réponse groundée → détail
/// nominatif sur demande) est entièrement couvert, une liste d'historique
/// est un complément UI indépendant, pas un pré-requis de sécurité.
class EcranChatIa extends ConsumerStatefulWidget {
  const EcranChatIa({super.key, required this.etablissementId, required this.persona});

  final String etablissementId;
  final PersonaIa persona;

  @override
  ConsumerState<EcranChatIa> createState() => _EcranChatIaState();
}

class _EntreeChat {
  _EntreeChat({required this.message, this.detailEleves = const []});

  final MessageChatIa message;
  final List<DetailElevePseudonymise> detailEleves;
}

class _EcranChatIaState extends ConsumerState<EcranChatIa> {
  final _controleur = TextEditingController();
  final _defilement = ScrollController();
  final List<_EntreeChat> _entrees = [];

  String? _conversationId;
  bool _grounding = false;
  bool _envoiEnCours = false;

  @override
  void dispose() {
    _controleur.dispose();
    _defilement.dispose();
    super.dispose();
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

  void _afficherErreur(String code) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Assistant indisponible ($code). Réessayez.')),
    );
  }

  Future<void> _envoyer(String texte) async {
    final saisie = texte.trim();
    if (saisie.isEmpty || _envoiEnCours) return;
    _controleur.clear();
    setState(() => _envoiEnCours = true);

    final depot = ref.read(chatIaRepositoryProvider);
    try {
      final reponse = await depot.envoyerMessage(
        conversationId: _conversationId,
        etablissementId: _conversationId == null ? widget.etablissementId : null,
        message: saisie,
      );
      _conversationId = reponse.conversationId;

      final messageUtilisateur = await depot.enregistrerMessage(
        conversationId: _conversationId!,
        sender: 'user',
        content: saisie,
      );
      final messageAssistant = await depot.enregistrerMessage(
        conversationId: _conversationId!,
        sender: 'assistant',
        content: reponse.reponse,
      );

      if (!mounted) return;
      setState(() {
        _entrees.add(_EntreeChat(message: messageUtilisateur));
        _entrees.add(_EntreeChat(message: messageAssistant, detailEleves: reponse.detailEleves));
      });
      _defilerVersLeBas();
    } on ErreurChatIa catch (e) {
      _afficherErreur(e.code);
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
    }
  }

  Future<void> _demarrerAnalyseRisque({required String cibleType, String? cibleId}) async {
    setState(() => _envoiEnCours = true);
    final depot = ref.read(chatIaRepositoryProvider);
    try {
      final resultat = await depot.demarrerAnalyseRisque(
        etablissementId: widget.etablissementId,
        cibleType: cibleType,
        cibleId: cibleId,
      );
      _conversationId = resultat.conversationId;
      _grounding = true;

      final messageDeclencheur = await depot.enregistrerMessage(
        conversationId: _conversationId!,
        sender: 'user',
        content: resultat.messageDeclencheur,
      );
      final messageAssistant = await depot.enregistrerMessage(
        conversationId: _conversationId!,
        sender: 'assistant',
        content: resultat.reponse,
      );

      if (!mounted) return;
      setState(() {
        _entrees.add(_EntreeChat(message: messageDeclencheur));
        _entrees.add(_EntreeChat(message: messageAssistant));
      });
      _defilerVersLeBas();
    } on ErreurChatIa catch (e) {
      _afficherErreur(e.code);
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
    }
  }

  Future<void> _ouvrirDialogueAnalyse() async {
    final structure = ref.read(structureEtablissementProvider(null)).value;
    final anneeId = structure?.anneeCourante?.id;
    final classes = (structure?.classes ?? const <Classe>[])
        .where((c) => c.actif && c.anneeScolaireId == anneeId)
        .toList(growable: false);

    var cibleType = 'etablissement';
    Classe? classeChoisie;

    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => StatefulBuilder(
        builder: (contexteDialogue, setDialogState) => AlertDialog(
          title: const Text("Analyser le risque d'échec"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioListTile<String>(
                value: 'etablissement',
                groupValue: cibleType,
                title: const Text("L'établissement entier"),
                onChanged: (v) => setDialogState(() => cibleType = v!),
              ),
              RadioListTile<String>(
                value: 'classe',
                groupValue: cibleType,
                title: const Text('Une classe précise'),
                onChanged: classes.isEmpty ? null : (v) => setDialogState(() => cibleType = v!),
              ),
              if (cibleType == 'classe')
                DropdownButton<Classe>(
                  isExpanded: true,
                  value: classeChoisie,
                  hint: const Text('Choisir une classe'),
                  items: [
                    for (final c in classes) DropdownMenuItem(value: c, child: Text(c.nom)),
                  ],
                  onChanged: (c) => setDialogState(() => classeChoisie = c),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(contexteDialogue).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: cibleType == 'classe' && classeChoisie == null
                  ? null
                  : () => Navigator.of(contexteDialogue).pop(true),
              child: const Text('Analyser'),
            ),
          ],
        ),
      ),
    );

    if (confirme != true) return;
    await _demarrerAnalyseRisque(
      cibleType: cibleType,
      cibleId: cibleType == 'classe' ? classeChoisie!.id : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final estDirection = widget.persona == PersonaIa.direction;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.persona.libelle),
        actions: [
          if (estDirection)
            IconButton(
              icon: const Icon(Icons.query_stats_outlined),
              tooltip: "Analyser le risque d'échec",
              onPressed: _envoiEnCours ? null : _ouvrirDialogueAnalyse,
            ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: BadgeSignalIaChat(),
            ),
          ),
          Expanded(
            child: _entrees.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        estDirection
                            ? "Discutez librement, ou lancez « Analyser le risque d'échec » "
                                "(icône en haut) pour une analyse groundée sur des chiffres réels."
                            : 'Posez votre première question à ${widget.persona.libelle}.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.palette.encreSecondaire),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _defilement,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _entrees.length,
                    itemBuilder: (context, i) => BulleMessageIa(entree: _entrees[i].message, detailEleves: _entrees[i].detailEleves),
                  ),
          ),
          if (_grounding)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.groups_outlined, size: 16),
                  label: const Text('Qui sont-ils ?'),
                  onPressed: _envoiEnCours ? null : () => _envoyer('Qui sont-ils ?'),
                ),
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
                        controller: _controleur,
                        minLines: 1,
                        maxLines: 4,
                        enabled: !_envoiEnCours,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Écrivez votre message…',
                        ),
                        onSubmitted: _envoyer,
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
                            icon: Icon(Icons.send, color: context.palette.primaire),
                            onPressed: () => _envoyer(_controleur.text),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
