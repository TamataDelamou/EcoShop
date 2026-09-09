import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/comm_providers.dart';
import '../domain/enums_comm.dart';
import '../domain/taux_lecture_canal.dart';
import 'ecran_templates_notifications.dart';
import 'widgets/badge_signal_ia.dart';

/// Tableau de bord communication (M9, vue direction) — taux de lecture par
/// canal sur les 30 derniers jours (RPC `analyser_envois`, IA descriptive) et
/// un outil d'analyse de sentiment pour les retours reçus (RPC
/// `analyser_feedback`, IA prescriptive) — signal d'aide, jamais un verdict.
class EcranTableauBordCommunication extends ConsumerWidget {
  const EcranTableauBordCommunication({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aujourdHui = DateTime.now();
    final maintenant = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day);
    final debut = maintenant.subtract(const Duration(days: 30));
    final analyse = ref.watch(analyserEnvoisProvider((etablissementId: etablissementId, debut: debut, fin: maintenant)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord communication'),
        actions: [
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: 'Modèles de messages',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EcranTemplatesNotifications(etablissementId: etablissementId)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Taux de lecture (30 derniers jours)', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          analyse.when(
            loading: () => const ShimmerCarteListe(),
            error: (erreur, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Tableau de bord indisponible hors connexion pour le moment.'),
            ),
            data: (liste) => liste.isEmpty
                ? const Text('Aucun envoi sur la période.')
                : Column(
                    children: [
                      for (var i = 0; i < liste.length; i++)
                        EntreeAnimee(index: i, enfant: _CarteTauxLecture(taux: liste[i])),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          const _OutilAnalyseSentiment(),
        ],
      ),
    );
  }
}

class _CarteTauxLecture extends StatelessWidget {
  const _CarteTauxLecture({required this.taux});

  final TauxLectureCanal taux;

  @override
  Widget build(BuildContext context) {
    final pourcentage = (taux.tauxLecture * 100).toStringAsFixed(0);
    final couleur = taux.tauxLecture >= 0.7
        ? context.palette.succes
        : (taux.tauxLecture >= 0.4 ? context.palette.accent : context.palette.erreur);

    return GlassCard(
      padding: const EdgeInsets.all(12),
      enfant: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  CanalNotification.depuisCode(taux.canal).libelle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${taux.nbLus} lues / ${taux.nbEnvoyes} envoyées',
                  style: TextStyle(color: context.palette.encreSecondaire, fontSize: 12),
                ),
              ],
            ),
          ),
          Text('$pourcentage %', style: TextStyle(color: couleur, fontSize: 20, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _OutilAnalyseSentiment extends ConsumerStatefulWidget {
  const _OutilAnalyseSentiment();

  @override
  ConsumerState<_OutilAnalyseSentiment> createState() => _OutilAnalyseSentimentState();
}

class _OutilAnalyseSentimentState extends ConsumerState<_OutilAnalyseSentiment> {
  final _texteCtrl = TextEditingController();
  String? _sentiment;
  bool _enCours = false;

  @override
  void dispose() {
    _texteCtrl.dispose();
    super.dispose();
  }

  Future<void> _analyser() async {
    final texte = _texteCtrl.text.trim();
    if (texte.isEmpty) return;
    setState(() => _enCours = true);
    try {
      final resultat = await ref.read(commRepositoryProvider).analyserFeedback(texte);
      if (!mounted) return;
      setState(() {
        _sentiment = resultat;
        _enCours = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Analyser un retour', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const BadgeSignalIa(texte: 'Signal IA — lexique léger, pas un jugement définitif'),
            const SizedBox(height: 8),
            TextField(
              controller: _texteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Coller le retour d\'un parent ou d\'un enseignant…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: _enCours ? null : _analyser,
                  child: _enCours
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Analyser'),
                ),
                const SizedBox(width: 12),
                if (_sentiment != null) _PastilleSentiment(sentiment: _sentiment!),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PastilleSentiment extends StatelessWidget {
  const _PastilleSentiment({required this.sentiment});

  final String sentiment;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (sentiment) {
      'positif' => context.palette.succes,
      'negatif' => context.palette.erreur,
      _ => context.palette.encreSecondaire,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(sentiment, style: TextStyle(color: couleur, fontWeight: FontWeight.w600)),
    );
  }
}
