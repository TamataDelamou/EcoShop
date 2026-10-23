import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/annonces_providers.dart';
import '../domain/annonce.dart';
import '../../../core/widgets/dialogue_masquage.dart';
import 'ecran_annonces.dart' show dateAnnonce;

/// Annonces de l'école, pour la direction : publier (toute l'école, un
/// niveau, une classe), voir combien de familles ont lu, masquer une annonce
/// (modération, journalisée).
class EcranAnnoncesDirection extends ConsumerWidget {
  const EcranAnnoncesDirection({super.key, required this.etablissementId});

  final String etablissementId;

  Future<void> _publier(BuildContext context) async {
    final resultat = await showModalBottomSheet<ResultatPublication>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormulaireAnnonce(etablissementId: etablissementId),
    );
    if (resultat == null || !context.mounted) return;
    final texte = !resultat.recue
        ? 'Sans réseau : l’annonce partira dès le retour de la connexion.'
        : [
            'Annonce publiée pour ${resultat.familles ?? 0} famille(s).',
            if ((resultat.sms ?? 0) > 0) '${resultat.sms} SMS envoyé(s).',
            if ((resultat.smsNonEnvoyes ?? 0) > 0) '${resultat.smsNonEnvoyes} SMS non envoyé(s) : crédits épuisés.',
          ].join(' ');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annonces = ref.watch(annoncesEtablissementProvider(etablissementId));
    return Scaffold(
      appBar: AppBar(title: const Text('Annonces de l’école')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bouton_nouvelle_annonce'),
        onPressed: () => _publier(context),
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('Publier'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(annoncesEtablissementProvider(etablissementId)),
        child: annonces.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: [
            Text(e is ErreurAnnonces ? e.message : 'Annonces indisponibles. Tirez pour réessayer.',
                textAlign: TextAlign.center),
          ]),
          data: (liste) => ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              if (liste.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Publiez votre première annonce : les familles concernées sont prévenues aussitôt.',
                      textAlign: TextAlign.center),
                ),
              for (final a in liste) _LigneAnnonce(annonce: a, etablissementId: etablissementId),
            ],
          ),
        ),
      ),
    );
  }
}

class _LigneAnnonce extends ConsumerWidget {
  const _LigneAnnonce({required this.annonce, required this.etablissementId});

  final Annonce annonce;
  final String etablissementId;

  Future<void> _masquer(BuildContext context, WidgetRef ref) async {
    final texte = await showDialog<String>(context: context, builder: (_) => const DialogueMasquage());
    if (texte == null || !context.mounted) return;
    final messager = ScaffoldMessenger.of(context);
    try {
      await ref.read(annoncesRepositoryProvider).masquer(annonce.id, texte);
      ref.invalidate(annoncesEtablissementProvider(etablissementId));
      messager.showSnackBar(const SnackBar(content: Text('Annonce masquée.')));
    } on ErreurAnnonces catch (e) {
      messager.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = annonce;
    final theme = Theme.of(context);
    final etat = a.enAttenteEnvoi
        ? 'En attente d’envoi'
        : a.masquee
            ? 'Masquée${a.motifMasquage != null ? ' : ${a.motifMasquage}' : ''}'
            : '${a.famillesLues ?? 0}/${a.familles ?? 0} familles ont lu';
    return Card(
      key: ValueKey('annonce_direction_${a.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(a.titre, style: TextStyle(decoration: a.masquee ? TextDecoration.lineThrough : null)),
        subtitle: Text('${a.cible} · ${dateAnnonce(a.publieeLe)}\n$etat'),
        isThreeLine: true,
        leading: Icon(a.importante ? Icons.priority_high : Icons.campaign_outlined,
            color: a.importante ? theme.colorScheme.error : null),
        trailing: a.masquee || a.enAttenteEnvoi
            ? null
            : IconButton(
                key: Key('masquer_${a.id}'),
                tooltip: 'Masquer',
                icon: const Icon(Icons.visibility_off_outlined),
                onPressed: () => _masquer(context, ref),
              ),
      ),
    );
  }
}

class _FormulaireAnnonce extends ConsumerStatefulWidget {
  const _FormulaireAnnonce({required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<_FormulaireAnnonce> createState() => _FormulaireAnnonceState();
}

class _FormulaireAnnonceState extends ConsumerState<_FormulaireAnnonce> {
  final _titre = TextEditingController();
  final _corps = TextEditingController();
  final _formulaire = GlobalKey<FormState>();
  PorteeAnnonce _portee = PorteeAnnonce.ecole;
  String? _cible;
  bool _importante = false;
  bool _parSms = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _titre.dispose();
    _corps.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (!(_formulaire.currentState?.validate() ?? false)) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final r = await ref.read(annoncesRepositoryProvider).publier(
            etablissementId: widget.etablissementId,
            portee: _portee,
            cibleId: _cible,
            titre: _titre.text,
            corps: _corps.text,
            importante: _importante,
            parSms: _parSms,
          );
      ref.invalidate(annoncesEtablissementProvider(widget.etablissementId));
      if (mounted) Navigator.of(context).pop(r);
    } on ErreurAnnonces catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  String? _longueur(String? v, int max) {
    final t = (v ?? '').trim();
    if (t.length < 3) return '3 caractères au moins.';
    if (t.length > max) return '$max caractères au plus.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final portees = ref.watch(porteesAnnonceProvider(widget.etablissementId)).valueOrNull ?? const PorteesDisponibles();
    final cibles = _portee == PorteeAnnonce.classe ? portees.classes : portees.niveaux;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formulaire,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nouvelle annonce', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              SegmentedButton<PorteeAnnonce>(
                key: const Key('choix_portee'),
                segments: [
                  for (final p in PorteeAnnonce.values)
                    ButtonSegment(value: p, label: Text(p == PorteeAnnonce.ecole ? 'École' : p == PorteeAnnonce.niveau ? 'Niveau' : 'Classe')),
                ],
                selected: {_portee},
                onSelectionChanged: (s) => setState(() {
                  _portee = s.first;
                  _cible = null;
                }),
              ),
              if (_portee != PorteeAnnonce.ecole) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('choix_cible'),
                  initialValue: _cible,
                  decoration: InputDecoration(labelText: _portee == PorteeAnnonce.classe ? 'Classe' : 'Niveau'),
                  items: [for (final c in cibles) DropdownMenuItem(value: c.id, child: Text(c.nom))],
                  onChanged: (v) => setState(() => _cible = v),
                  validator: (v) => v == null ? 'Choisissez ${_portee == PorteeAnnonce.classe ? 'une classe' : 'un niveau'}.' : null,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('champ_titre_annonce'),
                controller: _titre,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Titre'),
                validator: (v) => _longueur(v, 120),
              ),
              TextFormField(
                key: const Key('champ_corps_annonce'),
                controller: _corps,
                maxLength: 2000,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Texte', alignLabelWithHint: true),
                validator: (v) => _longueur(v, 2000),
              ),
              SwitchListTile(
                key: const Key('interrupteur_important'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Important'),
                subtitle: const Text('Signalée en tête de la notification'),
                value: _importante,
                onChanged: (v) => setState(() => _importante = v),
              ),
              SwitchListTile(
                key: const Key('interrupteur_sms'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Prévenir aussi par SMS'),
                subtitle: const Text('Un SMS par parent, sur les crédits de l’école. Sans crédit, seule la notification part.'),
                value: _parSms,
                onChanged: (v) => setState(() => _parSms = v),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 8),
                Text(_erreur!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('bouton_publier_annonce'),
                onPressed: _enCours ? null : _envoyer,
                child: const Text('Publier'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
