import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../referentiel/application/referentiel_providers.dart';
import '../application/creation_etablissement_providers.dart';
import '../domain/demande_etablissement.dart';

/// Formulaire de demande de création d'un établissement (REG-04, cahier
/// §5.3). La demande est examinée par Global Service Groupe : le rôle
/// Direction n'est attribué qu'après validation, jamais à la soumission.
class EcranDemandeEtablissement extends ConsumerStatefulWidget {
  const EcranDemandeEtablissement({super.key});

  @override
  ConsumerState<EcranDemandeEtablissement> createState() => _EcranDemandeEtablissementState();
}

class _EcranDemandeEtablissementState extends ConsumerState<EcranDemandeEtablissement> {
  final _cle = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _ville = TextEditingController();
  final _adresse = TextEditingController();
  final _telephone = TextEditingController(text: '+224 ');
  final _email = TextEditingController();
  final _effectif = TextEditingController();
  final _autorisation = TextEditingController();
  final _message = TextEditingController();
  String? _pays;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    for (final c in [_nom, _ville, _adresse, _telephone, _email, _effectif, _autorisation, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _texte(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _envoyer() async {
    if (!(_cle.currentState?.validate() ?? false)) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await ref.read(creationEtablissementRepositoryProvider).soumettre(
            SaisieDemandeEtablissement(
              nom: _nom.text.trim(),
              paysCode: _pays!,
              ville: _ville.text.trim(),
              telephone: _telephone.text.trim(),
              adresse: _texte(_adresse),
              email: _texte(_email),
              effectifEstime: int.tryParse(_effectif.text.trim()),
              numeroAutorisation: _texte(_autorisation),
              message: _texte(_message),
            ),
          );
      ref.invalidate(maDemandeEtablissementProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ErreurCreationEtablissement catch (e) {
      if (mounted) setState(() => _erreur = e.messageUtilisateur);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pays = ref.watch(paysPedagogiquesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Créer mon établissement')),
      body: Form(
        key: _cle,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [palette.primaire, Color.lerp(palette.primaire, palette.accent, 0.35)!],
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.school_rounded, color: Colors.white, size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Présentez votre école. Global Service Groupe examine chaque demande, '
                      'puis ouvre votre espace de Direction.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const _Titre(icone: Icons.apartment_rounded, texte: "L'établissement"),
            TextFormField(
              key: const Key('champ_nom_etablissement'),
              controller: _nom,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: "Nom de l'établissement *", border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().length < 3) ? 'Au moins 3 caractères' : null,
            ),
            const SizedBox(height: 12),
            pays.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Liste des pays indisponible hors connexion.', style: TextStyle(color: palette.erreur)),
              data: (liste) => DropdownButtonFormField<String>(
                key: const Key('champ_pays'),
                initialValue: _pays,
                decoration: const InputDecoration(labelText: 'Pays *', border: OutlineInputBorder()),
                items: [
                  for (final p in liste) DropdownMenuItem(value: p.codeIso, child: Text(p.nom)),
                ],
                onChanged: _enCours ? null : (v) => setState(() => _pays = v),
                validator: (v) => v == null ? 'Choisissez le pays' : null,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('champ_ville'),
                    controller: _ville,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Ville *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Ville requise' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _effectif,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: "Nombre d'élèves", border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _adresse,
              decoration: const InputDecoration(labelText: 'Adresse / quartier', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _autorisation,
              decoration: const InputDecoration(
                labelText: "N° d'autorisation d'ouverture",
                helperText: 'Accélère la validation si vous l’avez déjà',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const _Titre(icone: Icons.contact_phone_outlined, texte: 'Contact'),
            TextFormField(
              key: const Key('champ_telephone'),
              controller: _telephone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone *', border: OutlineInputBorder()),
              validator: (v) =>
                  RegExp(r'^\+?[0-9 ]{8,20}$').hasMatch((v ?? '').trim()) ? null : 'Numéro invalide (ex. +224 620 00 00 00)',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Courriel', border: OutlineInputBorder()),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Courriel invalide';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _message,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Message pour Global Service Groupe',
                border: OutlineInputBorder(),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _erreur == null
                  ? const SizedBox.shrink()
                  : Container(
                      key: ValueKey(_erreur),
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.erreur.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_erreur!, style: TextStyle(color: palette.erreur)),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            key: const Key('bouton_envoyer_demande'),
            onPressed: _enCours ? null : _envoyer,
            icon: _enCours
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: const Text('Envoyer la demande'),
          ),
        ),
      ),
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icone, size: 20, color: palette.primaire),
          const SizedBox(width: 8),
          Text(texte, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
