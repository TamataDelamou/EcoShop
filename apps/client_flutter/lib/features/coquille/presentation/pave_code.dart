import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/securite/code_secret.dart';
import '../application/verrou_controller.dart';

/// Pavé numérique du code secret (REG-18) : 6 points, chiffres, effacement,
/// bouton empreinte facultatif. Le code part tout seul au 6ᵉ chiffre.
class PaveCode extends StatefulWidget {
  const PaveCode({super.key, required this.titre, required this.surCode, this.sousTitre, this.surBiometrie});

  final String titre;
  final String? sousTitre;

  /// Reçoit le code complet ; renvoie un message d'erreur, ou null si le
  /// code est accepté.
  final Future<String?> Function(String code) surCode;

  /// Null : pas de bouton empreinte.
  final VoidCallback? surBiometrie;

  @override
  State<PaveCode> createState() => _PaveCodeState();
}

class _PaveCodeState extends State<PaveCode> {
  String _code = '';
  String? _erreur;
  bool _enCours = false;

  Future<void> _ajouter(String chiffre) async {
    if (_enCours || _code.length >= ReglesCode.longueur) return;
    HapticFeedback.selectionClick();
    setState(() {
      _code += chiffre;
      _erreur = null;
    });
    if (_code.length < ReglesCode.longueur) return;
    setState(() => _enCours = true);
    final erreur = await widget.surCode(_code);
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _code = '';
      _erreur = erreur;
    });
    if (erreur != null) HapticFeedback.heavyImpact();
  }

  void _effacer() {
    if (_enCours || _code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleur = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.titre, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        if (widget.sousTitre != null) ...[
          const SizedBox(height: 4),
          Text(widget.sousTitre!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        Semantics(
          label: '${_code.length} chiffres saisis sur ${ReglesCode.longueur}',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < ReglesCode.longueur; i++)
                Container(
                  key: ValueKey('point_$i'),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _code.length ? couleur.primary : Colors.transparent,
                    border: Border.all(color: _erreur != null ? couleur.error : couleur.outline, width: 2),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: Center(
            child: _enCours
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : _erreur == null
                ? null
                : Text(
                    _erreur!,
                    style: theme.textTheme.bodySmall?.copyWith(color: couleur.error),
                    textAlign: TextAlign.center,
                  ),
          ),
        ),
        for (final ligne in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final c in ligne) _Touche(texte: c, onTap: () => _ajouter(c))],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            widget.surBiometrie == null
                ? const _Touche()
                : _Touche(
                    icone: Icons.fingerprint,
                    libelle: 'Empreinte ou visage',
                    onTap: _enCours ? null : widget.surBiometrie,
                  ),
            _Touche(texte: '0', onTap: () => _ajouter('0')),
            _Touche(icone: Icons.backspace_outlined, libelle: 'Effacer', onTap: _effacer),
          ],
        ),
      ],
    );
  }
}

class _Touche extends StatelessWidget {
  const _Touche({this.texte, this.icone, this.libelle, this.onTap});

  final String? texte;
  final IconData? icone;
  final String? libelle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vide = texte == null && icone == null;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 72,
        height: 60,
        child: vide
            ? null
            : Semantics(
                button: true,
                label: libelle ?? texte,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child: Center(
                    child: texte != null
                        ? Text(texte!, style: Theme.of(context).textTheme.headlineSmall)
                        : Icon(icone, size: 28),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Message d'un code faux, avec les essais restants.
String messageCodeFaux(int essaisRestants) => essaisRestants == 1
    ? 'Code incorrect. Dernier essai avant la déconnexion.'
    : 'Code incorrect. Encore $essaisRestants essais.';

/// Action sensible (paiement, notes, comptabilité…) : code ou empreinte
/// demandés à chaque fois, dans une feuille qui monte du bas de l'écran.
/// Vrai si confirmé. Au 5ᵉ code faux, la session est fermée.
Future<bool> demanderCodeAction(BuildContext context, WidgetRef ref, String motif) async {
  final etat = ref.read(verrouControllerProvider);
  if (etat.phase == PhaseVerrou.inactif) return true;
  final controleur = ref.read(verrouControllerProvider.notifier);
  final confirme = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (feuille) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: PaveCode(
        titre: motif,
        sousTitre: 'Confirmez avec votre code secret',
        surBiometrie: etat.biometrieActivee
            ? () async {
                if (await controleur.deverrouillerParBiometrie(pourAction: true) && feuille.mounted) {
                  Navigator.of(feuille).pop(true);
                }
              }
            : null,
        surCode: (code) async {
          final resultat = await controleur.saisirCode(code, pourAction: true);
          switch (resultat) {
            case CodeBon():
              if (feuille.mounted) Navigator.of(feuille).pop(true);
              return null;
            case CodeFaux(:final essaisRestants):
              return messageCodeFaux(essaisRestants);
            case CodeBloque():
              if (feuille.mounted) Navigator.of(feuille).pop(false);
              return null;
          }
        },
      ),
    ),
  );
  return confirme ?? false;
}
