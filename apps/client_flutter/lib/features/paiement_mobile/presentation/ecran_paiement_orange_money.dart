import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../application/paiement_mobile_providers.dart';
import '../domain/paiement_mobile_repository.dart';
import '../domain/transaction_mobile_money.dart';
import 'ecran_suivi_paiement.dart';
import 'widgets/identite_orange_money.dart';

/// Écran de paiement Orange Money (REG-02, lot L5) — circuit établissement.
///
/// Récapitule ce qui est payé, laisse choisir le montant quand un paiement
/// partiel est permis (scolarité), puis crée la transaction côté serveur et
/// ouvre la page Orange Money. Le montant affiché n'est qu'une demande : le
/// serveur le borne au reste à payer (scolarité) ou l'impose (commande).
class EcranPaiementOrangeMoney extends ConsumerStatefulWidget {
  const EcranPaiementOrangeMoney({
    super.key,
    required this.objet,
    required this.cibleId,
    required this.titre,
    required this.sousTitre,
    required this.montantMaximal,
    this.devise = 'GNF',
    this.montantModifiable = false,
    this.auSucces,
  });

  /// Paiement des frais de scolarité d'une inscription (montant partiel permis).
  const EcranPaiementOrangeMoney.scolarite({
    super.key,
    required String inscriptionId,
    required String nomEleve,
    required double resteAPayer,
    this.devise = 'GNF',
    this.auSucces,
  })  : objet = ObjetPaiementMobile.scolarite,
        cibleId = inscriptionId,
        titre = 'Frais de scolarité',
        sousTitre = 'Élève : $nomEleve',
        montantMaximal = resteAPayer,
        montantModifiable = true;

  /// Paiement d'une commande marketplace (montant imposé).
  const EcranPaiementOrangeMoney.commande({
    super.key,
    required String commandeId,
    required String referenceCommande,
    required double montant,
    this.devise = 'GNF',
    this.auSucces,
  })  : objet = ObjetPaiementMobile.commandeMarketplace,
        cibleId = commandeId,
        titre = 'Commande marketplace',
        sousTitre = 'Référence $referenceCommande',
        montantMaximal = montant,
        montantModifiable = false;

  /// Frais d'inscription d'un dossier accepté (REG-08) : montant fixé par
  /// l'école, réglé en une fois ; le paiement confirme l'inscription.
  const EcranPaiementOrangeMoney.fraisInscription({
    super.key,
    required String demandeId,
    required String nomEleve,
    required String numeroDossier,
    required double montant,
    this.devise = 'GNF',
    this.auSucces,
  })  : objet = ObjetPaiementMobile.fraisInscription,
        cibleId = demandeId,
        titre = "Frais d'inscription",
        sousTitre = '$nomEleve · dossier $numeroDossier',
        montantMaximal = montant,
        montantModifiable = false;

  final ObjetPaiementMobile objet;
  final String cibleId;
  final String titre;
  final String sousTitre;
  final double montantMaximal;
  final String devise;
  final bool montantModifiable;

  /// Appelé une fois le paiement confirmé (rafraîchir solde, commandes…).
  final void Function(WidgetRef ref)? auSucces;

  @override
  ConsumerState<EcranPaiementOrangeMoney> createState() => _EcranPaiementOrangeMoneyState();
}

enum _Formule { totalite, moitie, libre }

class _EcranPaiementOrangeMoneyState extends ConsumerState<EcranPaiementOrangeMoney> {
  _Formule _formule = _Formule.totalite;
  final _montantLibre = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _montantLibre.dispose();
    super.dispose();
  }

  double? get _montantChoisi => switch (_formule) {
        _Formule.totalite => widget.montantMaximal,
        _Formule.moitie => (widget.montantMaximal / 2).roundToDouble(),
        _Formule.libre => double.tryParse(_montantLibre.text.replaceAll(RegExp(r'\s'), '')),
      };

  String? get _erreurMontant {
    final m = _montantChoisi;
    if (m == null || m <= 0) return 'Saisissez un montant.';
    if (m > widget.montantMaximal) {
      return 'Maximum : ${formaterMontantMobile(widget.montantMaximal, widget.devise)}';
    }
    if (m != m.roundToDouble()) return 'Montant entier uniquement.';
    return null;
  }

  Future<void> _payer() async {
    final montant = _montantChoisi;
    if (montant == null || _erreurMontant != null) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final initiation = await ref.read(paiementMobileRepositoryProvider).initierPaiementOrange(
            objet: widget.objet,
            cibleId: widget.cibleId,
            montant: widget.montantModifiable ? montant : null,
          );
      final ouverte = await ref.read(lanceurUrlProvider).ouvrir(initiation.urlPaiement);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EcranSuiviPaiement(
            transactionId: initiation.transactionId,
            urlPaiement: initiation.urlPaiement,
            titre: widget.titre,
            montant: initiation.montant,
            devise: initiation.devise,
            pageOuverte: ouverte,
            objet: widget.objet,
            auSucces: widget.auSucces,
          ),
        ),
      );
    } on ErreurPaiementMobile catch (e) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _erreur = e.messageUtilisateur;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final montant = _montantChoisi;
    final erreurMontant = _erreurMontant;

    return Scaffold(
      appBar: AppBar(title: const Text('Payer avec Orange Money')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          BandeauOrangeMoney(
            titre: widget.titre,
            sousTitre: widget.sousTitre,
            montant: montant != null && erreurMontant == null ? montant : widget.montantMaximal,
            devise: widget.devise,
          ),
          const SizedBox(height: 24),
          if (widget.montantModifiable) ...[
            Text('Montant à payer', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Reste à payer : ${formaterMontantMobile(widget.montantMaximal, widget.devise)}',
              style: TextStyle(color: palette.encreSecondaire),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _choix(_Formule.totalite, 'Totalité'),
                if (widget.montantMaximal >= 2) _choix(_Formule.moitie, 'Moitié'),
                _choix(_Formule.libre, 'Autre montant'),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: _formule == _Formule.libre
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        key: const Key('montant_libre'),
                        controller: _montantLibre,
                        enabled: !_enCours,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Montant (${widget.devise})',
                          prefixIcon: const Icon(Icons.payments_outlined),
                          errorText: _montantLibre.text.isEmpty ? null : erreurMontant,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 24),
          ],
          Text('Comment ça marche', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const _Etape(numero: 1, texte: 'Vous confirmez le montant ci-dessous.'),
          const _Etape(numero: 2, texte: "La page Orange Money s'ouvre : saisissez votre code secret pour valider."),
          const _Etape(numero: 3, texte: 'Le paiement est confirmé et le reçu est remis automatiquement.'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.succes.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.succes.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined, color: palette.succes),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "L'argent est versé directement sur le compte Orange Money de l'établissement. "
                    "EcoShop ne détient jamais vos fonds et ne voit jamais votre code secret.",
                    style: TextStyle(fontSize: 13, color: palette.encre),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _erreur == null
                ? const SizedBox.shrink()
                : Container(
                    key: ValueKey(_erreur),
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.erreur.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: palette.erreur),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_erreur!, style: TextStyle(color: palette.erreur))),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 56,
          child: FilledButton(
            key: const Key('bouton_payer_orange'),
            style: FilledButton.styleFrom(
              backgroundColor: CouleursOrangeMoney.orange,
              foregroundColor: CouleursOrangeMoney.encre,
              disabledBackgroundColor: CouleursOrangeMoney.orange.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            onPressed: _enCours || erreurMontant != null ? null : _payer,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _enCours
                  ? const SizedBox(
                      key: ValueKey('chargement'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: CouleursOrangeMoney.encre),
                    )
                  : Text(
                      montant == null || erreurMontant != null
                          ? 'Payer avec Orange Money'
                          : 'Payer ${formaterMontantMobile(montant, widget.devise)}',
                      key: const ValueKey('libelle'),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _choix(_Formule formule, String libelle) {
    final selectionne = _formule == formule;
    return ChoiceChip(
      label: Text(libelle),
      selected: selectionne,
      onSelected: _enCours ? null : (_) => setState(() => _formule = formule),
      selectedColor: CouleursOrangeMoney.orange.withValues(alpha: 0.2),
      side: BorderSide(color: selectionne ? CouleursOrangeMoney.orange : Theme.of(context).dividerColor),
      labelStyle: TextStyle(fontWeight: selectionne ? FontWeight.w700 : FontWeight.w500),
    );
  }
}

class _Etape extends StatelessWidget {
  const _Etape({required this.numero, required this.texte});

  final int numero;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CouleursOrangeMoney.orange.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$numero',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: CouleursOrangeMoney.encre),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(texte))),
        ],
      ),
    );
  }
}
