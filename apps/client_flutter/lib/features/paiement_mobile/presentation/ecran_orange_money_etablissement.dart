import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';

import '../application/paiement_mobile_providers.dart';
import '../domain/paiement_mobile_repository.dart';
import '../domain/rapprochement_mobile_money.dart';
import '../domain/transaction_mobile_money.dart';
import 'widgets/identite_orange_money.dart';

/// Espace Orange Money de la Direction (REG-02, lot L5) : activation du
/// compte marchand PROPRE à l'établissement, indicateurs du jour et suivi en
/// direct des derniers paiements.
///
/// Les identifiants saisis partent directement au serveur, qui les stocke
/// hors de portée de tout client ; ils ne sont jamais réaffichés, pas même
/// à la Direction (seule la référence publique `OM-xxxx` l'est).
class EcranOrangeMoneyEtablissement extends ConsumerWidget {
  const EcranOrangeMoneyEtablissement({super.key, required this.etablissementId, this.devise = 'GNF'});

  final String etablissementId;
  final String devise;

  Future<void> _actualiser(WidgetRef ref) async {
    ref.invalidate(etatOrangeMoneyProvider(etablissementId));
    ref.invalidate(transactionsMobilesEtablissementProvider(etablissementId));
    ref.invalidate(rapprochementMobileMoneyProvider);
    await ref.read(transactionsMobilesEtablissementProvider(etablissementId).future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(etatOrangeMoneyProvider(etablissementId));
    final transactions = ref.watch(transactionsMobilesEtablissementProvider(etablissementId));
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Orange Money')),
      body: RefreshIndicator(
        onRefresh: () => _actualiser(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            BandeauOrangeMoney(
              titre: 'Paiements en ligne de l’établissement',
              sousTitre: switch (etat) {
                AsyncData(value: final e) when e.active =>
                  'Activé — compte marchand ${e.referencePublique ?? ''}'.trim(),
                AsyncData() => 'Non activé : les familles ne peuvent pas encore payer en ligne.',
                AsyncError() => 'État indisponible hors connexion.',
                _ => 'Vérification…',
              },
            ),
            const SizedBox(height: 20),
            transactions.when(
              loading: () => const ShimmerCarteListe(),
              error: (e, _) => const SizedBox.shrink(),
              data: (liste) => _Indicateurs(
                indicateurs: IndicateursMobileMoney.depuis(liste, DateTime.now()),
                devise: liste.isEmpty ? devise : liste.first.devise,
              ),
            ),
            const SizedBox(height: 24),
            _CarteRapprochement(etablissementId: etablissementId),
            const SizedBox(height: 24),
            Text('Compte marchand', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            etat.when(
              loading: () => const ShimmerCarteListe(),
              error: (e, _) => Text(
                'Configuration indisponible hors connexion pour le moment.',
                style: TextStyle(color: palette.encreSecondaire),
              ),
              data: (e) => _FormulaireActivation(etablissementId: etablissementId, dejaActive: e.active),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: Text('Derniers paiements', style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  tooltip: 'Actualiser',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => _actualiser(ref),
                ),
              ],
            ),
            transactions.when(
              loading: () => const ShimmerCarteListe(),
              error: (e, _) => Text(
                'Paiements indisponibles hors connexion pour le moment.',
                style: TextStyle(color: palette.encreSecondaire),
              ),
              data: (liste) => liste.isEmpty
                  ? const _AucunPaiement()
                  : Column(
                      children: [
                        for (var i = 0; i < liste.length; i++)
                          EntreeAnimee(index: i, enfant: _LignePaiement(transaction: liste[i])),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Indicateurs extends StatelessWidget {
  const _Indicateurs({required this.indicateurs, required this.devise});

  final IndicateursMobileMoney indicateurs;
  final String devise;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        _Tuile(
          icone: Icons.account_balance_wallet_outlined,
          couleur: palette.succes,
          libelle: "Confirmé aujourd'hui",
          valeur: MontantAnime(
            montant: indicateurs.montantConfirmeDuJour,
            devise: devise,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: palette.encre),
          ),
          large: true,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Tuile(
                icone: Icons.check_circle_outline_rounded,
                couleur: palette.succes,
                libelle: 'Paiements du jour',
                valeur: _Compteur(valeur: indicateurs.confirmeesDuJour),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Tuile(
                icone: Icons.schedule_rounded,
                couleur: CouleursOrangeMoney.orange,
                libelle: 'En cours',
                valeur: _Compteur(valeur: indicateurs.enCours),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Tuile(
                icone: Icons.cancel_outlined,
                couleur: palette.erreur,
                libelle: 'Non aboutis',
                valeur: _Compteur(valeur: indicateurs.nonAbouties),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Rapprochement d'une journée, à confronter au relevé Orange Money : on
/// navigue de jour en jour, les écarts éventuels sont listés en clair.
class _CarteRapprochement extends ConsumerStatefulWidget {
  const _CarteRapprochement({required this.etablissementId});

  final String etablissementId;

  @override
  ConsumerState<_CarteRapprochement> createState() => _CarteRapprochementState();
}

class _CarteRapprochementState extends ConsumerState<_CarteRapprochement> {
  late DateTime _jour = _aujourdhui();

  static DateTime _aujourdhui() {
    final m = DateTime.now();
    return DateTime(m.year, m.month, m.day);
  }

  bool get _estAujourdhui => _jour == _aujourdhui();

  void _decaler(int jours) => setState(() => _jour = DateTime(_jour.year, _jour.month, _jour.day + jours));

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rappro = ref.watch(
      rapprochementMobileMoneyProvider((etablissementId: widget.etablissementId, jour: _jour)),
    );
    final libelleJour = _estAujourdhui
        ? "Aujourd'hui"
        : '${_jour.day.toString().padLeft(2, '0')}/${_jour.month.toString().padLeft(2, '0')}/${_jour.year}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: palette.primaire),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Rapprochement', style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Jour précédent',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _decaler(-1),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    libelleJour,
                    key: ValueKey(_jour),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Jour suivant',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _estAujourdhui ? null : () => _decaler(1),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: rappro.when(
                  loading: () => const Padding(
                    key: ValueKey('chargement'),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: LinearProgressIndicator(),
                  ),
                  error: (e, _) => Padding(
                    key: const ValueKey('erreur'),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Rapprochement indisponible hors connexion pour le moment.',
                      style: TextStyle(color: palette.encreSecondaire),
                    ),
                  ),
                  data: (r) => _ContenuRapprochement(key: ValueKey(r.jour), rapprochement: r),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContenuRapprochement extends StatelessWidget {
  const _ContenuRapprochement({super.key, required this.rapprochement});

  final RapprochementMobileMoney rapprochement;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final r = rapprochement;
    Widget ligne(String libelle, String valeur, {bool fort = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(libelle, style: TextStyle(color: palette.encreSecondaire))),
              Text(valeur, style: TextStyle(fontWeight: fort ? FontWeight.w900 : FontWeight.w600)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        ligne(
          'Confirmé par Orange (${r.nombreConfirmes})',
          formaterMontantMobile(r.montantConfirme, r.devise),
          fort: true,
        ),
        ligne('dont scolarité', formaterMontantMobile(r.montantScolarite, r.devise)),
        ligne('dont marketplace', formaterMontantMobile(r.montantMarketplace, r.devise)),
        ligne('Non aboutis', '${r.nonAboutis}'),
        ligne('En cours (tous jours)', '${r.enCours}'),
        const SizedBox(height: 12),
        if (r.anomalies.isEmpty)
          Row(
            children: [
              Icon(Icons.verified_rounded, color: palette.succes, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Aucun écart : chaque paiement confirmé a produit son écriture.',
                  style: TextStyle(color: palette.succes, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          )
        else ...[
          Text(
            '${r.anomalies.length} écart(s) à vérifier avec le relevé Orange Money',
            style: TextStyle(color: palette.erreur, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final a in r.anomalies)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.erreur.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.erreur.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: palette.erreur, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.libelle, style: TextStyle(color: palette.encre, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            formaterMontantMobile(a.montant, r.devise),
                            if (a.reference != null) a.reference!,
                          ].join(' · '),
                          style: TextStyle(color: palette.encreSecondaire, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile({
    required this.icone,
    required this.couleur,
    required this.libelle,
    required this.valeur,
    this.large = false,
  });

  final IconData icone;
  final Color couleur;
  final String libelle;
  final Widget valeur;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(large ? 18 : 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icone, size: 18, color: couleur),
          ),
          const SizedBox(height: 10),
          valeur,
          const SizedBox(height: 2),
          Text(libelle, style: TextStyle(fontSize: 12, color: palette.encreSecondaire)),
        ],
      ),
    );
  }
}

class _Compteur extends StatelessWidget {
  const _Compteur({required this.valeur});

  final int valeur;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valeur.toDouble()),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        '${v.round()}',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: context.palette.encre),
      ),
    );
  }
}

class _LignePaiement extends StatelessWidget {
  const _LignePaiement({required this.transaction});

  final TransactionMobileMoney transaction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final t = transaction.creeLe.toLocal();
    final date = '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: CouleursOrangeMoney.orange.withValues(alpha: 0.15),
          child: Icon(
            transaction.objet == ObjetPaiementMobile.scolarite
                ? Icons.school_outlined
                : Icons.shopping_bag_outlined,
            color: CouleursOrangeMoney.encre,
          ),
        ),
        title: Text(
          formaterMontantMobile(transaction.montant, transaction.devise),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            transaction.objet == ObjetPaiementMobile.scolarite ? 'Scolarité' : 'Marketplace',
            date,
            if (transaction.referenceOperateur != null) transaction.referenceOperateur!,
          ].join(' · '),
          style: TextStyle(color: palette.encreSecondaire, fontSize: 12),
        ),
        trailing: PastilleStatutTransaction(statut: transaction.statut),
      ),
    );
  }
}

class _AucunPaiement extends StatelessWidget {
  const _AucunPaiement();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: palette.encreSecondaire.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text('Aucun paiement Orange Money pour le moment.', style: TextStyle(color: palette.encreSecondaire)),
        ],
      ),
    );
  }
}

/// Saisie des identifiants marchands. Masquée par défaut quand le compte est
/// déjà actif : on ne remplace des identifiants qu'à dessein.
class _FormulaireActivation extends ConsumerStatefulWidget {
  const _FormulaireActivation({required this.etablissementId, required this.dejaActive});

  final String etablissementId;
  final bool dejaActive;

  @override
  ConsumerState<_FormulaireActivation> createState() => _FormulaireActivationState();
}

class _FormulaireActivationState extends ConsumerState<_FormulaireActivation> {
  final _cle = GlobalKey<FormState>();
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _merchantKey = TextEditingController();
  bool _production = false;
  bool _ouvert = false;
  bool _secretVisible = false;
  bool _enCours = false;

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    _merchantKey.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!(_cle.currentState?.validate() ?? false)) return;
    if (_production) {
      final confirme = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Passer en production ?'),
          content: const Text(
            'Les familles pourront payer réellement par Orange Money. Vérifiez que ces identifiants '
            "sont bien ceux du compte marchand de l'établissement.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirmer')),
          ],
        ),
      );
      if (confirme != true || !mounted) return;
    }

    setState(() => _enCours = true);
    try {
      await ref.read(paiementMobileRepositoryProvider).activerOrangeMoney(
            etablissementId: widget.etablissementId,
            clientId: _clientId.text,
            clientSecret: _clientSecret.text,
            merchantKey: _merchantKey.text,
            production: _production,
          );
      _clientId.clear();
      _clientSecret.clear();
      _merchantKey.clear();
      ref.invalidate(etatOrangeMoneyProvider(widget.etablissementId));
      if (!mounted) return;
      setState(() => _ouvert = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orange Money est activé pour l’établissement.')),
      );
    } on ErreurPaiementMobile catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageUtilisateur)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  String? _requis(String? valeur) => (valeur == null || valeur.trim().isEmpty) ? 'Champ requis' : null;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final formulaireVisible = !widget.dejaActive || _ouvert;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    widget.dejaActive ? Icons.verified_rounded : Icons.info_outline_rounded,
                    color: widget.dejaActive ? palette.succes : CouleursOrangeMoney.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.dejaActive
                          ? 'Identifiants enregistrés et protégés côté serveur. Ils ne sont jamais réaffichés.'
                          : 'Renseignez les identifiants remis par Orange Money à l’ouverture du compte marchand '
                              'de l’établissement.',
                      style: TextStyle(fontSize: 13, color: palette.encre),
                    ),
                  ),
                ],
              ),
              if (widget.dejaActive && !_ouvert) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _ouvert = true),
                  icon: const Icon(Icons.key_rounded),
                  label: const Text('Remplacer les identifiants'),
                ),
              ],
              if (formulaireVisible)
                Form(
                  key: _cle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('champ_client_id'),
                        controller: _clientId,
                        enabled: !_enCours,
                        decoration: const InputDecoration(
                          labelText: 'Client ID',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: _requis,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('champ_client_secret'),
                        controller: _clientSecret,
                        enabled: !_enCours,
                        obscureText: !_secretVisible,
                        decoration: InputDecoration(
                          labelText: 'Client secret',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _secretVisible ? 'Masquer' : 'Afficher',
                            icon: Icon(_secretVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setState(() => _secretVisible = !_secretVisible),
                          ),
                        ),
                        validator: _requis,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('champ_merchant_key'),
                        controller: _merchantKey,
                        enabled: !_enCours,
                        obscureText: !_secretVisible,
                        decoration: const InputDecoration(
                          labelText: 'Clé marchand (merchant key)',
                          prefixIcon: Icon(Icons.storefront_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: _requis,
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Test'), icon: Icon(Icons.science_outlined)),
                          ButtonSegment(value: true, label: Text('Production'), icon: Icon(Icons.bolt_rounded)),
                        ],
                        selected: {_production},
                        onSelectionChanged: _enCours ? null : (s) => setState(() => _production = s.first),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _production
                            ? 'Production : les paiements sont réels.'
                            : 'Test : bac à sable Orange Money, aucun argent réel ne circule.',
                        style: TextStyle(fontSize: 12, color: palette.encreSecondaire),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          key: const Key('bouton_activer_orange'),
                          style: FilledButton.styleFrom(
                            backgroundColor: CouleursOrangeMoney.orange,
                            foregroundColor: CouleursOrangeMoney.encre,
                            textStyle: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          onPressed: _enCours ? null : _enregistrer,
                          icon: _enCours
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: CouleursOrangeMoney.encre),
                                )
                              : const Icon(Icons.power_settings_new_rounded),
                          label: Text(widget.dejaActive ? 'Mettre à jour les identifiants' : 'Activer Orange Money'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
