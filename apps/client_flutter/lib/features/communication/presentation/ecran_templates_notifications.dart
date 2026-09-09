import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/comm_providers.dart';
import '../domain/enums_comm.dart';
import '../domain/template_notification.dart';

/// Modèles de messages d'un établissement (M9, gestion direction/
/// communication). Toujours en ligne — les modèles sont lus par tous les
/// membres, une modification locale non confirmée serait trompeuse.
class EcranTemplatesNotifications extends ConsumerWidget {
  const EcranTemplatesNotifications({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesEtablissementProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Modèles de messages')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nouveau modèle'),
        onPressed: () => _ouvrirFormulaire(context, ref),
      ),
      body: templates.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(4, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Modèles indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucun modèle enregistré.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) => EntreeAnimee(
                  index: i,
                  enfant: _CarteTemplate(
                    template: liste[i],
                    onModifier: () => _ouvrirFormulaire(context, ref, template: liste[i]),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _ouvrirFormulaire(BuildContext context, WidgetRef ref, {TemplateNotification? template}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FormulaireTemplate(etablissementId: etablissementId, template: template),
    );
    ref.invalidate(templatesEtablissementProvider(etablissementId));
  }
}

class _CarteTemplate extends StatelessWidget {
  const _CarteTemplate({required this.template, required this.onModifier});

  final TemplateNotification template;
  final VoidCallback onModifier;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          template.actif ? Icons.check_circle_outline : Icons.pause_circle_outline,
          color: template.actif ? context.palette.succes : context.palette.encreSecondaire,
        ),
        title: Text('${template.type} — ${template.canal.libelle}'),
        subtitle: Text(template.contenu, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.edit_outlined),
        onTap: onModifier,
      ),
    );
  }
}

class _FormulaireTemplate extends ConsumerStatefulWidget {
  const _FormulaireTemplate({required this.etablissementId, this.template});

  final String etablissementId;
  final TemplateNotification? template;

  @override
  ConsumerState<_FormulaireTemplate> createState() => _FormulaireTemplateState();
}

class _FormulaireTemplateState extends ConsumerState<_FormulaireTemplate> {
  late final _typeCtrl = TextEditingController(text: widget.template?.type ?? '');
  late final _contenuCtrl = TextEditingController(text: widget.template?.contenu ?? '');
  late CanalNotification _canal = widget.template?.canal ?? CanalNotification.sms;
  late bool _actif = widget.template?.actif ?? true;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _typeCtrl.dispose();
    _contenuCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (_typeCtrl.text.trim().isEmpty) {
      setState(() => _erreur = 'Le type de message est requis.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      await ref.read(commRepositoryProvider).creerOuModifierTemplate(
            TemplateNotification(
              id: widget.template?.id ?? '',
              etablissementId: widget.etablissementId,
              type: _typeCtrl.text.trim(),
              canal: _canal,
              contenu: _contenuCtrl.text.trim(),
              actif: _actif,
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = 'Enregistrement impossible : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.template == null ? 'Nouveau modèle' : 'Modifier le modèle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _typeCtrl,
              decoration: const InputDecoration(labelText: 'Type (ex. absence_parent)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CanalNotification>(
              initialValue: _canal,
              decoration: const InputDecoration(labelText: 'Canal'),
              items: [
                for (final canal in CanalNotification.values)
                  DropdownMenuItem(value: canal, child: Text(canal.libelle)),
              ],
              onChanged: (v) => setState(() => _canal = v ?? _canal),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contenuCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Contenu (variables entre {{ }})',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Actif'),
              value: _actif,
              onChanged: (v) => setState(() => _actif = v),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(_erreur!, style: TextStyle(color: context.palette.erreur)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _enCours ? null : _enregistrer,
          child: _enCours
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
