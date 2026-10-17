import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/transaction_mobile_money.dart';

/// Couleurs du parcours Orange Money. Le texte posé sur l'orange est
/// toujours NOIR : le blanc sur #FF7900 n'atteint pas le contraste WCAG AA.
abstract final class CouleursOrangeMoney {
  static const orange = Color(0xFFFF7900);
  static const orangeClair = Color(0xFFFFA040);
  static const encre = Color(0xFF111111);
}

/// Formate un montant avec séparateurs de milliers, ex. `1 500 000 GNF`.
String formaterMontantMobile(double montant, String devise) =>
    '${NumberFormat.decimalPattern('fr').format(montant)} $devise';

/// Bandeau d'en-tête du parcours : identité du moyen de paiement, contexte
/// du paiement et, en option, le montant mis en valeur et animé.
class BandeauOrangeMoney extends StatelessWidget {
  const BandeauOrangeMoney({
    super.key,
    required this.titre,
    required this.sousTitre,
    this.montant,
    this.devise = 'GNF',
  });

  final String titre;
  final String sousTitre;
  final double? montant;
  final String devise;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CouleursOrangeMoney.orange, CouleursOrangeMoney.orangeClair],
        ),
        boxShadow: [
          BoxShadow(
            color: CouleursOrangeMoney.orange.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: CouleursOrangeMoney.encre, shape: BoxShape.circle),
                child: const Icon(Icons.phone_iphone_rounded, color: CouleursOrangeMoney.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Orange Money',
                      style: TextStyle(
                        color: CouleursOrangeMoney.encre,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: 0.2,
                      ),
                    ),
                    Text(
                      titre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: CouleursOrangeMoney.encre.withValues(alpha: 0.8), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const _PastilleSecurise(),
            ],
          ),
          if (montant != null) ...[
            const SizedBox(height: 20),
            MontantAnime(
              montant: montant!,
              devise: devise,
              style: const TextStyle(
                color: CouleursOrangeMoney.encre,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            sousTitre,
            style: TextStyle(color: CouleursOrangeMoney.encre.withValues(alpha: 0.75), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PastilleSecurise extends StatelessWidget {
  const _PastilleSecurise();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CouleursOrangeMoney.encre.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 14, color: CouleursOrangeMoney.encre),
          SizedBox(width: 4),
          Text(
            'Sécurisé',
            style: TextStyle(color: CouleursOrangeMoney.encre, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Montant qui « défile » jusqu'à sa valeur (micro-animation, charte ch. 2).
class MontantAnime extends StatelessWidget {
  const MontantAnime({super.key, required this.montant, required this.devise, this.style});

  final double montant;
  final String devise;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: montant),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, valeur, _) => Text(
        formaterMontantMobile(valeur.roundToDouble(), devise),
        style: style,
      ),
    );
  }
}

/// Pastille de statut d'une transaction.
class PastilleStatutTransaction extends StatelessWidget {
  const PastilleStatutTransaction({super.key, required this.statut});

  final StatutTransactionMobile statut;

  @override
  Widget build(BuildContext context) {
    final (couleur, icone, libelle) = switch (statut) {
      StatutTransactionMobile.reussi => (const Color(0xFF0E9F6E), Icons.check_circle_rounded, 'Confirmé'),
      StatutTransactionMobile.echoue => (const Color(0xFFDC2626), Icons.cancel_rounded, 'Non abouti'),
      _ => (const Color(0xFFB45309), Icons.schedule_rounded, 'En cours'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: couleur),
          const SizedBox(width: 4),
          Text(libelle, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Frise des trois étapes du paiement, mise à jour en direct.
class EtapesPaiement extends StatelessWidget {
  const EtapesPaiement({super.key, required this.etapeActive, this.echec = false});

  /// 0 = demande créée, 1 = validation sur Orange Money, 2 = confirmé.
  final int etapeActive;
  final bool echec;

  static const _libelles = [
    ('Demande de paiement créée', 'Montant vérifié par EcoShop'),
    ('Validation sur Orange Money', 'Saisissez votre code secret Orange Money'),
    ('Paiement confirmé', "Reçu remis automatiquement à l'établissement"),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < _libelles.length; i++)
          _LigneEtape(
            titre: _libelles[i].$1,
            detail: _libelles[i].$2,
            etat: echec && i == etapeActive
                ? _EtatEtape.echec
                : i < etapeActive
                    ? _EtatEtape.faite
                    : i == etapeActive
                        ? _EtatEtape.enCours
                        : _EtatEtape.aVenir,
            derniere: i == _libelles.length - 1,
            couleurTexte: theme.colorScheme.onSurface,
          ),
      ],
    );
  }
}

enum _EtatEtape { faite, enCours, aVenir, echec }

class _LigneEtape extends StatelessWidget {
  const _LigneEtape({
    required this.titre,
    required this.detail,
    required this.etat,
    required this.derniere,
    required this.couleurTexte,
  });

  final String titre;
  final String detail;
  final _EtatEtape etat;
  final bool derniere;
  final Color couleurTexte;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (etat) {
      _EtatEtape.faite => const Color(0xFF0E9F6E),
      _EtatEtape.enCours => CouleursOrangeMoney.orange,
      _EtatEtape.echec => const Color(0xFFDC2626),
      _EtatEtape.aVenir => couleurTexte.withValues(alpha: 0.25),
    };
    final icone = switch (etat) {
      _EtatEtape.faite => Icons.check_rounded,
      _EtatEtape.echec => Icons.close_rounded,
      _ => null,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: etat == _EtatEtape.aVenir ? Colors.transparent : couleur,
                  shape: BoxShape.circle,
                  border: Border.all(color: couleur, width: 2),
                ),
                child: icone == null
                    ? (etat == _EtatEtape.enCours
                        ? const Padding(
                            padding: EdgeInsets.all(5),
                            child: CircularProgressIndicator(strokeWidth: 2, color: CouleursOrangeMoney.encre),
                          )
                        : null)
                    : Icon(icone, size: 16, color: Colors.white),
              ),
              if (!derniere)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: etat == _EtatEtape.faite ? couleur : couleurTexte.withValues(alpha: 0.15),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: derniere ? 0 : 18, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titre,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: etat == _EtatEtape.aVenir ? couleurTexte.withValues(alpha: 0.5) : couleurTexte,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(detail, style: TextStyle(fontSize: 12, color: couleurTexte.withValues(alpha: 0.6))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
