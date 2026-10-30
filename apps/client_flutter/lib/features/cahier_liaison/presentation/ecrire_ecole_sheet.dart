import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/cahier_liaison_providers.dart';
import '../domain/cahier_liaison.dart';

/// Parent : écrire à l'école au sujet de son enfant (REG-34).
///
/// On choisit d'abord à qui (un enseignant de l'enfant, avec ses matières,
/// ou la direction), puis on écrit. Les heures de l'école sont dites avant
/// d'écrire : hors de ces heures, le message part tout de suite mais
/// l'enseignant n'est prévenu qu'à l'ouverture — comme les « heures
/// calmes » de ClassDojo ou Remind. Aucun numéro personnel n'est montré.
///
/// Renvoie vrai si le serveur a reçu, faux si le message attend le réseau,
/// null si le parent a renoncé.
Future<bool?> ouvrirEcrireEcole(BuildContext context, {required String ficheEleveId, required String nomEleve}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => EcrireEcoleSheet(ficheEleveId: ficheEleveId, nomEleve: nomEleve),
  );
}

class EcrireEcoleSheet extends ConsumerStatefulWidget {
  const EcrireEcoleSheet({super.key, required this.ficheEleveId, required this.nomEleve});

  final String ficheEleveId;
  final String nomEleve;

  @override
  ConsumerState<EcrireEcoleSheet> createState() => _EcrireEcoleSheetState();
}

class _EcrireEcoleSheetState extends ConsumerState<EcrireEcoleSheet> {
  final _texte = TextEditingController();
  String? _destinataire;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final texte = _texte.text.trim();
    final destinataire = _destinataire;
    if (destinataire == null) {
      setState(() => _erreur = 'Choisissez à qui écrire.');
      return;
    }
    if (texte.isEmpty) {
      setState(() => _erreur = 'Écrivez votre message.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final recu = await ref
          .read(cahierLiaisonRepositoryProvider)
          .ecrireAEcole(ficheEleveId: widget.ficheEleveId, destinataireId: destinataire, corps: texte);
      if (mounted) Navigator.of(context).pop(recu);
    } on ErreurCahier catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsEcoleProvider(widget.ficheEleveId));
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: contacts.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              e is ErreurCahier ? e.message : 'Impossible de charger les contacts de l’école. Réessayez.',
              textAlign: TextAlign.center,
            ),
          ),
          data: (c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Écrire à l’école', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Au sujet de ${widget.nomEleve}', style: theme.textTheme.bodyMedium),
              if (c.heures != null) ...[
                const SizedBox(height: 12),
                _BandeauHeures(heures: c.heures!),
              ],
              const SizedBox(height: 16),
              Text('À qui ?', style: theme.textTheme.titleSmall),
              if (c.destinataires.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Aucun enseignant n’est encore affecté à la classe. Réessayez plus tard.'),
                ),
              RadioGroup<String>(
                groupValue: _destinataire,
                onChanged: (v) => setState(() {
                  _destinataire = v;
                  _erreur = null;
                }),
                child: Column(
                  children: [
                    for (final d in c.destinataires)
                      RadioListTile<String>(
                        key: Key('destinataire_${d.id}'),
                        value: d.id,
                        contentPadding: EdgeInsets.zero,
                        title: Text(d.nom),
                        subtitle: Text(d.role),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('champ_message_ecole'),
                controller: _texte,
                minLines: 3,
                maxLines: 8,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Votre message',
                  hintText: 'Bonjour, …',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_erreur != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_erreur!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              Text(
                'Le message est lu par la personne choisie et par la direction de l’école. '
                'Pour une urgence, appelez l’école.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('bouton_envoyer_ecole'),
                  onPressed: _enCours || c.destinataires.isEmpty ? null : _envoyer,
                  icon: const Icon(Icons.send),
                  label: const Text('Envoyer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandeauHeures extends StatelessWidget {
  const _BandeauHeures({required this.heures});

  final HeuresMessagerie heures;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Container(
      key: const Key('bandeau_heures'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: heures.ouverte ? schema.secondaryContainer : schema.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(heures.ouverte ? Icons.schedule : Icons.bedtime_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              heures.ouverte
                  ? 'L’école lit ses messages ${heures.libelle}.'
                  : 'L’école lit ses messages ${heures.libelle}. Vous pouvez écrire maintenant : '
                      'votre message sera remis à l’ouverture.',
            ),
          ),
        ],
      ),
    );
  }
}
