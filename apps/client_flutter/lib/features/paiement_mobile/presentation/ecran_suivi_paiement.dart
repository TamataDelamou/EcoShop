import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../application/paiement_mobile_providers.dart';
import '../domain/transaction_mobile_money.dart';
import 'widgets/identite_orange_money.dart';

/// Suivi en direct d'un paiement Orange Money (REG-02, lot L5).
///
/// L'écran ne décide jamais lui-même du résultat : il relit le statut tenu à
/// jour par le serveur (notification Orange authentifiée PUIS reconfirmée),
/// à intervalle régulier et dès que l'application revient au premier plan
/// (retour depuis la page Orange Money).
class EcranSuiviPaiement extends ConsumerStatefulWidget {
  const EcranSuiviPaiement({
    super.key,
    required this.transactionId,
    required this.urlPaiement,
    required this.titre,
    required this.montant,
    required this.devise,
    required this.objet,
    this.pageOuverte = true,
    this.auSucces,
  });

  final String transactionId;
  final Uri urlPaiement;
  final String titre;
  final double montant;
  final String devise;
  final ObjetPaiementMobile objet;

  /// Faux si la page Orange Money n'a pas pu s'ouvrir automatiquement.
  final bool pageOuverte;
  final void Function(WidgetRef ref)? auSucces;

  /// Au-delà, un message rassurant explique que la confirmation tarde.
  static const delaiAvantAide = Duration(minutes: 5);

  @override
  ConsumerState<EcranSuiviPaiement> createState() => _EcranSuiviPaiementState();
}

class _EcranSuiviPaiementState extends ConsumerState<EcranSuiviPaiement> with WidgetsBindingObserver {
  final _debut = DateTime.now();
  Timer? _chrono;
  Duration _ecoule = Duration.zero;
  bool _succesSignale = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chrono = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _ecoule = DateTime.now().difference(_debut));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chrono?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour depuis la page Orange Money : relecture immédiate du statut.
    if (state == AppLifecycleState.resumed) {
      final actuel = ref.read(suiviTransactionProvider(widget.transactionId)).value;
      if (actuel == null || !actuel.statut.estFinal) {
        ref.invalidate(suiviTransactionProvider(widget.transactionId));
      }
    }
  }

  void _surStatutFinal(TransactionMobileMoney tx) {
    _chrono?.cancel();
    if (tx.statut == StatutTransactionMobile.reussi && !_succesSignale) {
      _succesSignale = true;
      widget.auSucces?.call(ref);
    }
  }

  Future<void> _rouvrir() async {
    final ok = await ref.read(lanceurUrlProvider).ouvrir(widget.urlPaiement);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La page Orange Money n'a pas pu s'ouvrir sur cet appareil.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<TransactionMobileMoney>>(suiviTransactionProvider(widget.transactionId), (_, suivant) {
      final tx = suivant.value;
      if (tx != null && tx.statut.estFinal) _surStatutFinal(tx);
    });

    final suivi = ref.watch(suiviTransactionProvider(widget.transactionId));
    final tx = suivi.value;
    final statut = tx?.statut ?? StatutTransactionMobile.initie;

    final Widget contenu = switch (statut) {
      StatutTransactionMobile.reussi => _VueSucces(
          key: const ValueKey('succes'),
          transaction: tx!,
          objet: widget.objet,
        ),
      StatutTransactionMobile.echoue => _VueEchec(key: const ValueKey('echec'), transaction: tx!),
      _ => _VueAttente(
          key: const ValueKey('attente'),
          ecoule: _ecoule,
          pageOuverte: widget.pageOuverte,
          surRouvrir: _rouvrir,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi du paiement'),
        automaticallyImplyLeading: statut.estFinal,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          BandeauOrangeMoney(
            titre: widget.titre,
            sousTitre: statut.libelle,
            montant: widget.montant,
            devise: widget.devise,
          ),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOutBack,
            transitionBuilder: (enfant, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(animation), child: enfant),
            ),
            child: contenu,
          ),
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: EtapesPaiement(
                etapeActive: statut == StatutTransactionMobile.reussi ? 3 : 1,
                echec: statut == StatutTransactionMobile.echoue,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: statut.estFinal
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  key: const Key('bouton_terminer'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(statut == StatutTransactionMobile.reussi ? 'Terminer' : 'Fermer'),
                ),
              ),
            )
          : null,
    );
  }
}

class _VueAttente extends StatefulWidget {
  const _VueAttente({super.key, required this.ecoule, required this.pageOuverte, required this.surRouvrir});

  final Duration ecoule;
  final bool pageOuverte;
  final Future<void> Function() surRouvrir;

  @override
  State<_VueAttente> createState() => _VueAttenteState();
}

class _VueAttenteState extends State<_VueAttente> with SingleTickerProviderStateMixin {
  late final AnimationController _pulsation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _pulsation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final minutes = widget.ecoule.inMinutes.toString().padLeft(2, '0');
    final secondes = (widget.ecoule.inSeconds % 60).toString().padLeft(2, '0');
    final tarde = widget.ecoule >= EcranSuiviPaiement.delaiAvantAide;

    return Column(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: AnimatedBuilder(
            animation: _pulsation,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                for (final decalage in const [0.0, 0.5])
                  _Onde(progression: (_pulsation.value + decalage) % 1),
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(color: CouleursOrangeMoney.orange, shape: BoxShape.circle),
                  child: const Icon(Icons.phonelink_lock_rounded, size: 36, color: CouleursOrangeMoney.encre),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.pageOuverte ? 'Validez le paiement sur Orange Money' : 'Ouvrez la page Orange Money',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Saisissez votre code secret sur la page Orange Money, puis revenez ici. '
          "Cet écran se met à jour tout seul dès que l'opérateur confirme.",
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.encreSecondaire),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, size: 16, color: palette.encreSecondaire),
            const SizedBox(width: 4),
            Text(
              '$minutes:$secondes',
              style: TextStyle(
                color: palette.encreSecondaire,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        if (tarde) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.premium.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              "La confirmation tarde. Si vous avez déjà validé et reçu le SMS d'Orange Money, "
              "vous pouvez fermer cet écran : le paiement sera enregistré automatiquement dès "
              "que l'opérateur le confirmera.",
              style: TextStyle(fontSize: 13, color: palette.encre),
            ),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('bouton_rouvrir'),
          onPressed: widget.surRouvrir,
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(widget.pageOuverte ? 'Rouvrir la page Orange Money' : 'Ouvrir la page Orange Money'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer, je vérifierai plus tard'),
        ),
      ],
    );
  }
}

class _Onde extends StatelessWidget {
  const _Onde({required this.progression});

  final double progression;

  @override
  Widget build(BuildContext context) {
    final taille = 76 + 64 * progression;
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CouleursOrangeMoney.orange.withValues(alpha: 0.28 * (1 - progression)),
      ),
    );
  }
}

class _VueSucces extends StatelessWidget {
  const _VueSucces({super.key, required this.transaction, required this.objet});

  final TransactionMobileMoney transaction;
  final ObjetPaiementMobile objet;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final quand = transaction.traiteLe ?? transaction.creeLe;
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.elasticOut,
          builder: (context, v, enfant) => Transform.scale(scale: v, child: enfant),
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: palette.succes,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: palette.succes.withValues(alpha: 0.35), blurRadius: 24)],
            ),
            child: const Icon(Icons.check_rounded, size: 56, color: Colors.white),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Paiement confirmé',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          switch (objet) {
            ObjetPaiementMobile.scolarite => "Le reçu est disponible dans les encaissements de l'élève.",
            ObjetPaiementMobile.fraisInscription =>
              "L'inscription est confirmée. Le reçu est disponible dans les encaissements de l'élève.",
            ObjetPaiementMobile.commandeMarketplace => 'Votre commande est payée. Le vendeur est prévenu.',
          },
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.encreSecondaire),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              _LigneDetail(
                libelle: 'Montant',
                valeur: formaterMontantMobile(transaction.montant, transaction.devise),
              ),
              if (transaction.referenceOperateur != null)
                _LigneDetail(libelle: 'Référence Orange Money', valeur: transaction.referenceOperateur!),
              _LigneDetail(
                libelle: 'Date',
                valeur: '${quand.toLocal().day.toString().padLeft(2, '0')}/'
                    '${quand.toLocal().month.toString().padLeft(2, '0')}/${quand.toLocal().year} '
                    '${quand.toLocal().hour.toString().padLeft(2, '0')}:'
                    '${quand.toLocal().minute.toString().padLeft(2, '0')}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VueEchec extends StatelessWidget {
  const _VueEchec({super.key, required this.transaction});

  final TransactionMobileMoney transaction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(color: palette.erreur.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(Icons.close_rounded, size: 56, color: palette.erreur),
        ),
        const SizedBox(height: 16),
        Text(
          "Le paiement n'a pas abouti",
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          "Orange Money n'a pas confirmé ce paiement. Vous pouvez recommencer depuis le dossier. "
          "Si votre compte a malgré tout été débité, contactez l'établissement avec la référence "
          "du SMS reçu d'Orange Money.",
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.encreSecondaire),
        ),
      ],
    );
  }
}

class _LigneDetail extends StatelessWidget {
  const _LigneDetail({required this.libelle, required this.valeur});

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(libelle, style: TextStyle(color: context.palette.encreSecondaire))),
          Text(valeur, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
