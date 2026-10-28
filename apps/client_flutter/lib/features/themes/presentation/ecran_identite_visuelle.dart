import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_palettes.dart';
import '../../../core/theme/app_theme_variant.dart';
import '../../../core/theme/couleur_identite.dart';
import '../../auth/application/auth_providers.dart';
import '../../etablissement/domain/etablissement.dart';
import '../application/theme_providers.dart';
import '../data/identite_visuelle_repository.dart';

/// Identité visuelle de l'établissement (REG-07 B) — réservé à la Direction.
///
/// La couleur choisie est appliquée à toute l'application et aux documents
/// imprimés ; elle est AJUSTÉE automatiquement pour rester lisible (WCAG AA)
/// en mode clair comme en mode sombre, ce que l'aperçu montre en direct.
class EcranIdentiteVisuelle extends ConsumerStatefulWidget {
  const EcranIdentiteVisuelle({super.key, required this.etablissement});

  final Etablissement etablissement;

  /// Nuancier proposé : teintes franches, toutes ajustables en lisibilité.
  static const nuancier = <Color>[
    Color(0xFF2563EB), Color(0xFF1E3A8A), Color(0xFF0B6E99), Color(0xFF0E7490),
    Color(0xFF0E6B5C), Color(0xFF15803D), Color(0xFF4D7C0F), Color(0xFFA16207),
    Color(0xFFC2410C), Color(0xFFB91C1C), Color(0xFFBE185D), Color(0xFF7E22CE),
    Color(0xFF4338CA), Color(0xFF374151), Color(0xFF7C2D12), Color(0xFF065F46),
  ];

  @override
  ConsumerState<EcranIdentiteVisuelle> createState() => _EcranIdentiteVisuelleState();
}

class _EcranIdentiteVisuelleState extends ConsumerState<EcranIdentiteVisuelle> {
  late Color? _couleur = CouleurIdentite.depuisHex(widget.etablissement.couleurIdentite);
  late String? _logoChemin = widget.etablissement.logoChemin;
  late final _hex = TextEditingController(
    text: widget.etablissement.couleurIdentite ?? '',
  );
  late final _slogan = TextEditingController(text: widget.etablissement.slogan ?? '');
  /// Image choisie, pas encore déposée.
  Uint8List? _nouveauLogo;

  /// Image affichée localement (reste visible après l'enregistrement).
  Uint8List? _apercuLocal;
  String _extensionLogo = 'png';
  bool _enCours = false;

  @override
  void dispose() {
    _hex.dispose();
    _slogan.dispose();
    super.dispose();
  }

  void _choisirCouleur(Color? couleur) {
    setState(() {
      _couleur = couleur;
      _hex.text = couleur == null ? '' : CouleurIdentite.versHex(couleur);
    });
  }

  Future<void> _choisirLogo() async {
    final image = await ref.read(selecteurLogoProvider)();
    if (image == null || !mounted) return;
    if (image.octets.length > SupabaseIdentiteVisuelleRepository.tailleMaxOctets) {
      _signaler(const ErreurIdentiteVisuelle('LOGO_TROP_LOURD').messageUtilisateur);
      return;
    }
    setState(() {
      _nouveauLogo = image.octets;
      _apercuLocal = image.octets;
      _extensionLogo = image.extension;
    });
  }

  void _retirerLogo() => setState(() {
        _nouveauLogo = null;
        _apercuLocal = null;
        _logoChemin = null;
      });

  void _signaler(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _enregistrer() async {
    final slogan = _slogan.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (slogan.length == 1 || slogan.length > 120) {
      _signaler(const ErreurIdentiteVisuelle('SLOGAN_INVALIDE').messageUtilisateur);
      return;
    }
    setState(() => _enCours = true);
    final depot = ref.read(identiteVisuelleRepositoryProvider);
    try {
      var chemin = _logoChemin;
      final logo = _nouveauLogo;
      if (logo != null) {
        chemin = await depot.televerserLogo(widget.etablissement.id, logo, _extensionLogo);
      }
      await depot.enregistrer(
        etablissementId: widget.etablissement.id,
        couleurHex: _couleur == null ? null : CouleurIdentite.versHex(_couleur!),
        logoChemin: chemin,
        // Chaîne vide : slogan retiré.
        slogan: slogan,
      );
      // L'établissement relu porte la nouvelle identité : toute l'application
      // change de couleur et affiche le logo aussitôt.
      ref.invalidate(mesEtablissementsProvider);
      ref.invalidate(identitePdfProvider);
      if (!mounted) return;
      setState(() {
        _logoChemin = chemin;
        _nouveauLogo = null;
      });
      _signaler("Identité enregistrée : elle s'applique à toute l'application et aux documents.");
    } on ErreurIdentiteVisuelle catch (e) {
      if (mounted) _signaler(e.messageUtilisateur);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final variante = ref.watch(themeVariantProvider);
    final logoUrl = _logoChemin == null || _logoChemin != widget.etablissement.logoChemin
        ? null
        : ref.watch(identiteEtablissementProvider).logoUrl;
    final ImageProvider? imageLogo = _apercuLocal != null
        ? MemoryImage(_apercuLocal!)
        : (logoUrl != null ? NetworkImage(logoUrl) : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Identité visuelle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('Aperçu', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Apercu(
                  variante: variante,
                  brightness: Brightness.light,
                  couleur: _couleur,
                  nom: widget.etablissement.nom,
                  slogan: _slogan.text.trim(),
                  logo: imageLogo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Apercu(
                  variante: variante,
                  brightness: Brightness.dark,
                  couleur: _couleur,
                  nom: widget.etablissement.nom,
                  slogan: _slogan.text.trim(),
                  logo: imageLogo,
                ),
              ),
            ],
          ),
          _NoteAjustement(variante: variante, couleur: _couleur),
          const SizedBox(height: 24),
          Text('Slogan', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "La devise de l'école, affichée sous son nom dans l'application et sur les documents.",
            style: TextStyle(color: palette.encreSecondaire, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('champ_slogan'),
            controller: _slogan,
            enabled: !_enCours,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Slogan (facultatif)',
              hintText: 'Travail – Discipline – Réussite',
              prefixIcon: Icon(Icons.format_quote_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text('Couleur principale', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "Choisissez la couleur de l'école. Elle est corrigée automatiquement si nécessaire pour rester lisible.",
            style: TextStyle(color: palette.encreSecondaire, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Pastille(
                key: const Key('couleur_defaut'),
                couleur: AppPalettes.pour(variante, Brightness.light).primaire,
                selectionnee: _couleur == null,
                libelle: 'Charte du pays',
                surTap: () => _choisirCouleur(null),
              ),
              for (final c in EcranIdentiteVisuelle.nuancier)
                _Pastille(
                  key: Key('couleur_${CouleurIdentite.versHex(c)}'),
                  couleur: c,
                  selectionnee: _couleur == c,
                  surTap: () => _choisirCouleur(c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('champ_hex'),
            controller: _hex,
            enabled: !_enCours,
            decoration: const InputDecoration(
              labelText: 'Code couleur (#RRGGBB)',
              prefixIcon: Icon(Icons.tag_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              final c = CouleurIdentite.depuisHex(v);
              if (c != null) setState(() => _couleur = c);
            },
          ),
          const SizedBox(height: 24),
          Text('Logo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'PNG ou JPEG, 1 Mo maximum. Un fond transparent rend mieux sur les documents.',
            style: TextStyle(color: palette.encreSecondaire, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: palette.bordure),
                  image: imageLogo == null ? null : DecorationImage(image: imageLogo, fit: BoxFit.contain),
                ),
                child: imageLogo == null
                    ? Icon(Icons.add_photo_alternate_outlined, color: palette.encreSecondaire, size: 32)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('bouton_choisir_logo'),
                      onPressed: _enCours ? null : _choisirLogo,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(imageLogo == null ? 'Choisir une image' : "Changer d'image"),
                    ),
                    if (imageLogo != null)
                      TextButton.icon(
                        onPressed: _enCours ? null : _retirerLogo,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Retirer le logo'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            key: const Key('bouton_enregistrer_identite'),
            onPressed: _enCours ? null : _enregistrer,
            icon: _enCours
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded),
            label: const Text("Enregistrer l'identité"),
          ),
        ),
      ),
    );
  }
}

/// Mini-maquette d'écran dans une luminosité donnée, avec la palette
/// effective (couleur ajustée comprise).
class _Apercu extends StatelessWidget {
  const _Apercu({
    required this.variante,
    required this.brightness,
    required this.couleur,
    required this.nom,
    required this.logo,
    this.slogan = '',
  });

  final AppThemeVariant variante;
  final Brightness brightness;
  final Color? couleur;
  final String nom;
  final String slogan;
  final ImageProvider? logo;

  @override
  Widget build(BuildContext context) {
    final p = AppPalettes.resoudre(variante, brightness, couleurEtablissement: couleur);
    final sombre = brightness == Brightness.dark;
    const duree = Duration(milliseconds: 300);
    return AnimatedContainer(
      duration: duree,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.fond,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(sombre ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 14, color: p.encreSecondaire),
              const SizedBox(width: 4),
              Text(sombre ? 'Sombre' : 'Clair', style: TextStyle(fontSize: 11, color: p.encreSecondaire)),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: duree,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: p.primaire.withValues(alpha: 0.15),
                  backgroundImage: logo,
                  child: logo == null ? Icon(Icons.school_rounded, size: 12, color: p.primaire) : null,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.encre),
                      ),
                      if (slogan.isNotEmpty)
                        Text(
                          slogan,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: p.encreSecondaire),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('Reste à payer', style: TextStyle(fontSize: 10, color: p.encreSecondaire)),
          Text('750 000 GNF', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.primaire)),
          const SizedBox(height: 10),
          AnimatedContainer(
            duration: duree,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.primaire, borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Valider',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sombre ? p.fond : Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Signale, couleurs à l'appui, quand la teinte choisie a été corrigée.
class _NoteAjustement extends StatelessWidget {
  const _NoteAjustement({required this.variante, required this.couleur});

  final AppThemeVariant variante;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final c = couleur;
    if (c == null) return const SizedBox(height: 8);
    final clair = AppPalettes.resoudre(variante, Brightness.light, couleurEtablissement: c).primaire;
    final sombre = AppPalettes.resoudre(variante, Brightness.dark, couleurEtablissement: c).primaire;
    if (clair == c && sombre == c) return const SizedBox(height: 8);
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high_rounded, size: 18, color: palette.primaire),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Teinte ajustée automatiquement pour rester lisible'
              '${clair != c && sombre != c ? ' en clair et en sombre' : clair != c ? ' en mode clair' : ' en mode sombre'}.',
              style: TextStyle(fontSize: 12, color: palette.encreSecondaire),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({
    super.key,
    required this.couleur,
    required this.selectionnee,
    required this.surTap,
    this.libelle,
  });

  final Color couleur;
  final bool selectionnee;
  final VoidCallback surTap;
  final String? libelle;

  @override
  Widget build(BuildContext context) {
    final pastille = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: couleur,
        shape: BoxShape.circle,
        border: Border.all(
          color: selectionnee ? context.palette.encre : Colors.transparent,
          width: 3,
        ),
        boxShadow: selectionnee
            ? [BoxShadow(color: couleur.withValues(alpha: 0.45), blurRadius: 10)]
            : const [],
      ),
      child: selectionnee ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
    );
    return Semantics(
      button: true,
      selected: selectionnee,
      label: libelle ?? CouleurIdentite.versHex(couleur),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: surTap,
        child: libelle == null
            ? pastille
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  pastille,
                  const SizedBox(height: 2),
                  Text(libelle!, style: const TextStyle(fontSize: 10)),
                ],
              ),
      ),
    );
  }
}
