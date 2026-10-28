import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/widgets/choisir_date.dart';
import '../../configuration/presentation/ecran_configuration_etablissement.dart';
import '../../creation_etablissement/presentation/ecran_validation_etablissements_gsg.dart';
import '../../themes/data/identite_visuelle_repository.dart';
import '../data/ecoles_gsg_repository.dart';

String _depuis(DateTime? d) {
  if (d == null) return 'jamais';
  final ecart = DateTime.now().difference(d);
  if (ecart.inMinutes < 60) return 'à l’instant';
  if (ecart.inHours < 24) return 'il y a ${ecart.inHours} h';
  if (ecart.inDays < 30) return 'il y a ${ecart.inDays} j';
  return 'le ${formaterDate(d)}';
}

String _nombre(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// Administration GSG (REG-23) : toutes les écoles confirmées, leurs
/// renseignements et leurs chiffres clés ; chacune ouvre son tableau de
/// bord. Les demandes en attente sont à un toucher (barre du haut).
class EcranEcolesGsg extends ConsumerStatefulWidget {
  const EcranEcolesGsg({super.key});

  @override
  ConsumerState<EcranEcolesGsg> createState() => _EcranEcolesGsgState();
}

class _EcranEcolesGsgState extends ConsumerState<EcranEcolesGsg> {
  String _texte = '';
  String _tri = 'nom';

  @override
  Widget build(BuildContext context) {
    final ecoles = ref.watch(ecolesGsgProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Écoles'),
        actions: [
          TextButton.icon(
            key: const Key('bouton_demandes_gsg'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const EcranValidationEtablissementsGsg()))
                .then((_) => ref.invalidate(ecolesGsgProvider)),
            icon: const Icon(Icons.inbox_outlined),
            label: const Text('Demandes'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(ecolesGsgProvider),
        child: ecoles.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(32),
                child: Text('Liste des écoles indisponible pour le moment. Tirez pour réessayer.', textAlign: TextAlign.center),
              ),
            ],
          ),
          data: (toutes) {
            final t = _texte.trim().toLowerCase();
            int comparer(EcoleGsg a, EcoleGsg b) {
              if (_tri == 'eleves') return b.eleves.compareTo(a.eleves);
              if (_tri == 'activite') {
                return (b.derniereActivite ?? DateTime(2000)).compareTo(a.derniereActivite ?? DateTime(2000));
              }
              return a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
            }

            final liste = toutes
                .where((e) => t.isEmpty || '${e.nom} ${e.ville ?? ''} ${e.direction ?? ''}'.toLowerCase().contains(t))
                .toList()
              ..sort(comparer);
            final eleves = toutes.fold<int>(0, (s, e) => s + e.eleves);
            final actifs = toutes.fold<int>(0, (s, e) => s + e.comptesActifs30j);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Chiffre(valeur: _nombre(toutes.length), libelle: 'écoles'),
                        _Chiffre(valeur: _nombre(eleves), libelle: 'élèves inscrits'),
                        _Chiffre(valeur: _nombre(actifs), libelle: 'comptes actifs (30 j)'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Nom, ville, directeur…',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onChanged: (v) => setState(() => _texte = v),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final e in const {'nom': 'Nom', 'eleves': 'Élèves', 'activite': 'Activité récente'}.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(e.value),
                            selected: _tri == e.key,
                            onSelected: (_) => setState(() => _tri = e.key),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (liste.isEmpty)
                  const Padding(padding: EdgeInsets.all(24), child: Text('Aucune école.', textAlign: TextAlign.center)),
                for (final e in liste) _CarteEcole(ecole: e),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.valeur, required this.libelle});

  final String valeur;
  final String libelle;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(valeur, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text(libelle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _LogoEcole extends ConsumerWidget {
  const _LogoEcole({required this.ecole, this.rayon = 22});

  final EcoleGsg ecole;
  final double rayon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chemin = ecole.logoChemin;
    String? url;
    if (chemin != null) {
      try {
        url = ref.watch(supabaseClientProvider).storage.from(bucketLogosEtablissements).getPublicUrl(chemin);
      } catch (_) {}
    }
    return CircleAvatar(
      radius: rayon,
      backgroundImage: url == null ? null : NetworkImage(url),
      child: url == null ? Icon(Icons.school_outlined, size: rayon) : null,
    );
  }
}

class _CarteEcole extends StatelessWidget {
  const _CarteEcole({required this.ecole});

  final EcoleGsg ecole;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    final inactive = ecole.derniereActivite == null || DateTime.now().difference(ecole.derniereActivite!).inDays > 14;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: Key('ecole_${ecole.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EcranTableauEcoleGsg(ecole: ecole))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _LogoEcole(ecole: ecole),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ecole.nom, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        if (ecole.localisation.isNotEmpty) Text(ecole.localisation),
                        if (ecole.direction != null) Text('Direction : ${ecole.direction}', style: TextStyle(color: schema.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Pastille(icone: Icons.school_outlined, texte: '${_nombre(ecole.eleves)} élèves'),
                  _Pastille(icone: Icons.class_outlined, texte: '${ecole.classes} classes'),
                  _Pastille(icone: Icons.badge_outlined, texte: '${ecole.personnel} personnel'),
                  _Pastille(icone: Icons.family_restroom_outlined, texte: '${ecole.parents} parents'),
                  _Pastille(
                    icone: inactive ? Icons.bedtime_outlined : Icons.bolt_outlined,
                    texte: 'Activité ${_depuis(ecole.derniereActivite)}',
                    alerte: inactive,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.icone, required this.texte, this.alerte = false});

  final IconData icone;
  final String texte;
  final bool alerte;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    final fond = alerte ? schema.errorContainer : schema.surfaceContainerHighest;
    final encre = alerte ? schema.onErrorContainer : schema.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: encre),
          const SizedBox(width: 4),
          Text(texte, style: TextStyle(fontSize: 12, color: encre)),
        ],
      ),
    );
  }
}

/// Tableau de bord d'une école (REG-23) : renseignements, effectifs,
/// utilisation jour par jour, finances, mise en route.
class EcranTableauEcoleGsg extends ConsumerWidget {
  const EcranTableauEcoleGsg({super.key, required this.ecole});

  final EcoleGsg ecole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tableau = ref.watch(tableauEcoleGsgProvider(ecole.id));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(ecole.nom)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(tableauEcoleGsgProvider(ecole.id)),
        child: tableau.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(children: const [
            Padding(padding: EdgeInsets.all(32), child: Text('Tableau de bord indisponible. Tirez pour réessayer.')),
          ]),
          data: (t) {
            final d = t.demande;
            final config = t.configuration;
            final etapes = etapesConfiguration(ecole.versEtablissement(), config).where((e) => !e.facultative).toList();
            final faites = etapes.where((e) => e.faite).length;
            final devise = t.finances['devise'] as String? ?? ecole.deviseCode;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Row(
                  children: [
                    _LogoEcole(ecole: ecole, rayon: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ecole.nom, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          if (ecole.slogan != null)
                            Text('« ${ecole.slogan} »', style: const TextStyle(fontStyle: FontStyle.italic)),
                          Text([ecole.localisation, if (t.annee != null) 'année ${t.annee}'].where((x) => x.isNotEmpty).join(' · ')),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(titre: 'Effectifs', enfants: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Tuile(valeur: _nombre(t.effectif('eleves')), libelle: 'élèves inscrits'),
                      _Tuile(valeur: _nombre(t.effectif('classes')), libelle: 'classes'),
                      _Tuile(valeur: _nombre(t.effectif('parents')), libelle: 'parents liés'),
                      _Tuile(valeur: _nombre(t.effectif('eleves_avec_compte')), libelle: 'élèves avec compte'),
                    ],
                  ),
                  if (t.parRole.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Comptes : ${t.parRole.entries.map((e) => '${e.value} ${e.key}').join(' · ')}'),
                  ],
                ]),
                _Section(titre: 'Utilisation', enfants: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Tuile(valeur: _nombre(t.usage('comptes_actifs_7j')), libelle: 'actifs sur 7 jours'),
                      _Tuile(valeur: _nombre(t.usage('comptes_actifs_30j')), libelle: 'actifs sur 30 jours'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Actions par jour (appels, notes, pointages, reçus) — 30 derniers jours'),
                  const SizedBox(height: 8),
                  _Histogramme(points: t.parJour),
                  const SizedBox(height: 12),
                  Text('Sur 30 jours : ${t.usage('appels_30j')} présences saisies · ${t.usage('notes_30j')} notes · '
                      '${t.usage('pointages_30j')} passages au portail · ${t.usage('annonces_30j')} annonces · '
                      '${t.usage('encaissements_30j')} reçus.'),
                ]),
                _Section(titre: 'Finances', enfants: [
                  Text('Encaissé sur 30 jours : ${_nombre((t.finances['encaisse_30j'] as num?) ?? 0)} $devise'),
                  Text('Encaissé sur l’année : ${_nombre((t.finances['encaisse_annee'] as num?) ?? 0)} $devise'),
                  Text('Paiements Orange Money (30 j) : ${(t.finances['paiements_mobiles_30j'] as num?) ?? 0}'),
                  Text('Crédits SMS : ${(t.finances['credits_sms'] as num?) ?? 0}'),
                ]),
                _Section(titre: 'Mise en route : $faites / ${etapes.length}', enfants: [
                  LinearProgressIndicator(value: etapes.isEmpty ? 0 : faites / etapes.length, minHeight: 8),
                  const SizedBox(height: 8),
                  for (final e in etapes)
                    Row(
                      children: [
                        Icon(e.faite ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 18, color: e.faite ? theme.colorScheme.primary : theme.colorScheme.outline),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${e.titre} — ${e.etat}')),
                      ],
                    ),
                ]),
                _Section(titre: 'Renseignements', enfants: [
                  if (d['demandeur'] != null) Text('Demandeur : ${d['demandeur']}'),
                  if (ecole.direction != null) Text('Direction : ${ecole.direction}'),
                  if (d['adresse'] != null) Text('Adresse : ${d['adresse']}'),
                  if (d['numero_autorisation'] != null) Text('Autorisation : ${d['numero_autorisation']}'),
                  if (d['effectif_estime'] != null) Text('Effectif annoncé à la demande : ${d['effectif_estime']}'),
                  if (ecole.valideLe != null) Text('Validée le ${formaterDate(ecole.valideLe!)}'),
                  if (ecole.creeLe != null) Text('Créée le ${formaterDate(ecole.creeLe!)}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (ecole.telephone != null)
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri(scheme: 'tel', path: ecole.telephone!.replaceAll(' ', ''))),
                          icon: const Icon(Icons.call_outlined),
                          label: Text(ecole.telephone!),
                        ),
                      if (ecole.email != null)
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri(scheme: 'mailto', path: ecole.email)),
                          icon: const Icon(Icons.mail_outline),
                          label: Text(ecole.email!),
                        ),
                    ],
                  ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.titre, required this.enfants});

  final String titre;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titre, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ...enfants,
            ],
          ),
        ),
      );
}

class _Tuile extends StatelessWidget {
  const _Tuile({required this.valeur, required this.libelle});

  final String valeur;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: schema.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valeur, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          Text(libelle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Barres des 30 derniers jours (aucune bibliothèque : léger, hors ligne).
class _Histogramme extends StatelessWidget {
  const _Histogramme({required this.points});

  final List<({DateTime jour, int actions})> points;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    if (points.isEmpty) return const Text('Aucune donnée.');
    final maxi = points.fold<int>(1, (m, p) => p.actions > m ? p.actions : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 90,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final p in points)
                Expanded(
                  child: Tooltip(
                    message: '${formaterDate(p.jour)} : ${p.actions} action${p.actions > 1 ? 's' : ''}',
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: p.actions == 0 ? 2 : 6 + 84 * p.actions / maxi,
                      decoration: BoxDecoration(
                        color: p.actions == 0 ? schema.outlineVariant : schema.primary,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formaterDate(points.first.jour), style: Theme.of(context).textTheme.labelSmall),
            Text('max. $maxi / jour', style: Theme.of(context).textTheme.labelSmall),
            Text(formaterDate(points.last.jour), style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}
