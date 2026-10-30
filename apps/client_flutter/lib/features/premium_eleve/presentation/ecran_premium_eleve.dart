import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/widgets/choisir_date.dart';
import '../data/premium_eleve_repository.dart';
import '../domain/premium_eleve.dart';

final premiumEleveRepositoryProvider = Provider<PremiumEleveRepository>((ref) {
  return PremiumEleveRepository(
    ref.watch(supabaseClientProvider),
    LectureHorsLigne(
      CacheDocumentStore(ref.watch(databaseProvider), 'premium_eleve_hl'),
      ref.watch(fraicheurHorsLigneProvider),
    ),
  );
});

final etatPremiumProvider = FutureProvider.autoDispose.family<EtatPremium, String>(
  (ref, ficheId) => ref.watch(premiumEleveRepositoryProvider).etat(ficheId),
);

/// Heure courante, remplaçable en test.
final maintenantPremiumProvider = Provider<DateTime Function()>((ref) => DateTime.now);

String _montant(num v, String devise) {
  final entier = v.round().toString();
  final groupes = <String>[];
  for (var i = entier.length; i > 0; i -= 3) {
    groupes.insert(0, entier.substring(i - 3 < 0 ? 0 : i - 3, i));
  }
  return '${groupes.join(' ')} $devise';
}

/// Premium élève (REG-36) : où en est l'abonnement, combien il coûte, et le
/// prolonger d'un mois ou d'une année (mobile money). Pas de prélèvement
/// automatique : rappel 7 jours avant la fin, temps payé jamais perdu.
class EcranPremiumEleve extends ConsumerStatefulWidget {
  const EcranPremiumEleve({super.key, required this.ficheEleveId, required this.prenom, this.parent = false});

  final String ficheEleveId;
  final String prenom;
  final bool parent;

  @override
  ConsumerState<EcranPremiumEleve> createState() => _EcranPremiumEleveState();
}

class _EcranPremiumEleveState extends ConsumerState<EcranPremiumEleve> with WidgetsBindingObserver {
  FormulePremium _formule = FormulePremium.annuel;
  bool _envoi = false;
  bool _paiementOuvert = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Retour de la page de paiement : relire l'état (le webhook a pu passer).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _paiementOuvert) {
      ref.invalidate(etatPremiumProvider(widget.ficheEleveId));
    }
  }

  Future<void> _payer() async {
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      final url = await ref.read(premiumEleveRepositoryProvider).payer(widget.ficheEleveId, _formule);
      _paiementOuvert = true;
      final ouvert = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ouvert) throw const ErreurPremium('URL_PAIEMENT_INDISPONIBLE');
    } on ErreurPremium catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(etatPremiumProvider(widget.ficheEleveId));
    final maintenant = ref.watch(maintenantPremiumProvider)();
    final schema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.parent ? 'Premium de ${widget.prenom}' : 'Mon Premium')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(etatPremiumProvider(widget.ficheEleveId)),
        child: etat.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: const [
            Padding(padding: EdgeInsets.all(16), child: Text('État indisponible pour le moment. Tirez pour réessayer.')),
          ]),
          data: (e) {
            final actif = e.actifLe(maintenant);
            final jours = e.joursRestants(maintenant);
            final tarif = e.tarif(_formule);
            final economie = e.economieAnnuelle();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Card(
                  color: actif ? schema.primaryContainer : schema.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(actif ? Icons.workspace_premium : Icons.workspace_premium_outlined,
                            color: actif ? schema.primary : schema.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(actif ? 'Premium actif' : 'Sans Premium',
                            key: const Key('premium_statut'), style: Theme.of(context).textTheme.titleMedium),
                      ]),
                      const SizedBox(height: 6),
                      if (actif)
                        Text('Jusqu’au ${formaterDate(e.expireLe!.toLocal())}'
                            '${jours == 0 ? ' (dernier jour)' : ' — encore $jours jour${jours! > 1 ? 's' : ''}'}')
                      else if (e.expireLe != null)
                        Text('Terminé le ${formaterDate(e.expireLe!.toLocal())}.')
                      else
                        const Text('Pas encore d’abonnement.'),
                    ]),
                  ),
                ),
                if (e.aRappeler(maintenant))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'La fin approche : prolongez maintenant, les jours restants sont gardés.',
                      key: const Key('premium_rappel'),
                      style: TextStyle(color: schema.tertiary, fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Ce que Premium apporte', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(e.quotaGratuit == null
                    ? '• Le Tuteur IA sans limite mensuelle.'
                    : '• Le Tuteur IA sans limite (sans Premium : ${e.quotaGratuit} questions par mois).'),
                const Text('• Valable pour un élève, payé par lui ou par un parent relié.'),
                const Text('• Pas de prélèvement automatique : vous choisissez quand prolonger.'),
                const SizedBox(height: 16),
                Text(actif ? 'Prolonger' : 'S’abonner', style: Theme.of(context).textTheme.titleSmall),
                RadioGroup<FormulePremium>(
                  groupValue: _formule,
                  onChanged: (f) => setState(() => _formule = f ?? _formule),
                  child: Column(children: [
                    for (final f in FormulePremium.values)
                      RadioListTile<FormulePremium>(
                        key: ValueKey('premium_${f.code}'),
                        contentPadding: EdgeInsets.zero,
                        value: f,
                        title: Text(f.libelle),
                        subtitle: Text([
                          e.tarif(f) == null ? 'Prix pas encore fixé' : _montant(e.tarif(f)!, e.devise),
                          if (f == FormulePremium.annuel && economie != null) '$economie % d’économie',
                        ].join(' — ')),
                      ),
                  ]),
                ),
                Text('Actif jusqu’au ${formaterDate(e.finSiPaye(_formule, maintenant))} après paiement.',
                    key: const Key('premium_fin_prevue'), style: TextStyle(color: schema.onSurfaceVariant)),
                if (_erreur != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_erreur!, key: const Key('premium_erreur'), style: TextStyle(color: schema.error)),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('premium_payer'),
                  onPressed: _envoi || tarif == null ? null : _payer,
                  icon: const Icon(Icons.phone_android),
                  label: Text(_envoi
                      ? 'Ouverture du paiement…'
                      : tarif == null
                          ? 'Prix pas encore fixé'
                          : 'Payer ${_montant(tarif, e.devise)} par mobile money'),
                ),
                if (_paiementOuvert)
                  TextButton(
                    key: const Key('premium_actualiser'),
                    onPressed: () => ref.invalidate(etatPremiumProvider(widget.ficheEleveId)),
                    child: const Text('J’ai payé : actualiser'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
