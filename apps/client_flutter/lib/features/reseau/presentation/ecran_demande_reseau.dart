import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../referentiel/application/referentiel_providers.dart';
import '../application/reseau_providers.dart';
import '../domain/reseau.dart';
import 'elements_reseau.dart';

/// Demande de création d'un réseau d'établissements (cahier 28.3) :
/// examinée par Global Service Groupe ; les frais de création, exigés une
/// seule fois, sont réglés avant la validation. Fonctionne sans réseau : la
/// demande part dès que le téléphone retrouve la connexion.
class EcranDemandeReseau extends ConsumerStatefulWidget {
  const EcranDemandeReseau({super.key});

  @override
  ConsumerState<EcranDemandeReseau> createState() => _EcranDemandeReseauState();
}

class _EcranDemandeReseauState extends ConsumerState<EcranDemandeReseau> {
  final _cle = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _denomination = TextEditingController();
  final _courriel = TextEditingController();
  final _telephone = TextEditingController(text: '+224 ');
  final _adresse = TextEditingController();
  final _responsable = TextEditingController();
  final _message = TextEditingController();
  String _type = 'confessionnel';
  String? _pays = 'GN';
  String _devise = 'GNF';
  bool _enCours = false;
  String? _erreur;

  static const _devises = ['GNF', 'XOF', 'XAF', 'NGN', 'GHS', 'SLE', 'LRD', 'GMD', 'CVE', 'MRU', 'EUR', 'USD'];

  @override
  void dispose() {
    for (final c in [_nom, _denomination, _courriel, _telephone, _adresse, _responsable, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (!(_cle.currentState?.validate() ?? false)) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final demande = await ref.read(reseauRepositoryProvider).soumettreDemande(
            SaisieDemandeReseau(
              nom: _nom.text.trim(),
              denomination: _denomination.text.trim(),
              typeReseau: _type,
              paysCode: _pays!,
              deviseCode: _devise,
              courriel: _courriel.text.trim(),
              telephone: _telephone.text.trim(),
              adresse: _adresse.text.trim(),
              premierResponsable: _responsable.text.trim(),
              message: _message.text.trim().isEmpty ? null : _message.text.trim(),
            ),
          );
      ref.invalidate(maDemandeReseauProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(demande.enAttenteEnvoi
            ? 'Demande gardée sur le téléphone : elle partira dès le retour du réseau.'
            : 'Demande envoyée. Un courriel de confirmation arrive à ${_courriel.text.trim()}.'),
      ));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreurReseau(e));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  InputDecoration _deco(String libelle, {String? aide}) =>
      InputDecoration(labelText: libelle, helperText: aide, border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pays = ref.watch(paysPedagogiquesProvider);
    String? requis(String? v, [int min = 3]) => (v == null || v.trim().length < min) ? 'Au moins $min caractères' : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Créer un réseau d’établissements')),
      body: Form(
        key: _cle,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(colors: [palette.primaire, Color.lerp(palette.primaire, palette.accent, 0.35)!]),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hub_rounded, color: Colors.white, size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Regroupez vos écoles sous une Direction Générale : vue consolidée, circulaires, '
                      'calendrier commun. Chaque école garde ses données et son autonomie.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('champ_nom_reseau'),
              controller: _nom,
              textCapitalization: TextCapitalization.words,
              decoration: _deco('Nom du réseau *', aide: 'Ex. Écoles protestantes de Guinée'),
              validator: requis,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _denomination,
              textCapitalization: TextCapitalization.sentences,
              decoration: _deco('Dénomination officielle *', aide: 'Organisation propriétaire (Église, fondation, société…)'),
              validator: requis,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: _deco('Type de réseau'),
              items: [for (final t in typesReseau.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
              onChanged: _enCours ? null : (v) => setState(() => _type = v ?? 'autre'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: pays.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Liste des pays indisponible.', style: TextStyle(color: palette.erreur)),
                    data: (liste) => DropdownButtonFormField<String>(
                      initialValue: liste.any((p) => p.codeIso == _pays) ? _pays : null,
                      decoration: _deco('Pays *'),
                      items: [for (final p in liste) DropdownMenuItem(value: p.codeIso, child: Text(p.nom))],
                      onChanged: _enCours ? null : (v) => setState(() => _pays = v),
                      validator: (v) => v == null ? 'Choisissez le pays' : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: _devise,
                    decoration: _deco('Devise'),
                    items: [for (final d in _devises) DropdownMenuItem(value: d, child: Text(d))],
                    onChanged: _enCours ? null : (v) => setState(() => _devise = v ?? 'GNF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _adresse, decoration: _deco('Adresse du siège *'), validator: requis),
            const SizedBox(height: 12),
            TextFormField(
              controller: _responsable,
              textCapitalization: TextCapitalization.words,
              decoration: _deco('Premier responsable *', aide: 'Nom et fonction (ex. Pasteur A. Diallo, secrétaire général)'),
              validator: requis,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _courriel,
              keyboardType: TextInputType.emailAddress,
              decoration: _deco('Courriel *', aide: 'Reçoit la confirmation et la décision'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Courriel invalide',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              decoration: _deco('Téléphone *'),
              validator: (v) =>
                  RegExp(r'^\+?[0-9 ]{8,20}$').hasMatch((v ?? '').trim()) ? null : 'Numéro invalide (ex. +224 620 00 00 00)',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _message,
              maxLines: 3,
              maxLength: 1000,
              decoration: _deco('Message pour Global Service Groupe'),
            ),
            Text(
              'Des frais de création, exigés une seule fois dans la vie du réseau, sont réglés auprès de Global Service '
              'Groupe avant la validation.',
              style: TextStyle(color: palette.encreSecondaire, fontSize: 13),
            ),
            if (_erreur != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.erreur.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_erreur!, style: TextStyle(color: palette.erreur)),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            key: const Key('bouton_envoyer_demande_reseau'),
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
