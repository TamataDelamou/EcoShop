import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/profil.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../scolarite/presentation/widgets/ajouter_enfant_sheet.dart';
import '../../scolarite/presentation/widgets/selecteur_enfant.dart';
import '../../themes/application/theme_providers.dart';
import '../../auth/application/espace_providers.dart';

/// Rôle utilisé à ce moment : celui du compte dans l'établissement actif
/// (un parent invité comme enseignant y est enseignant), sinon son rôle
/// principal.
String libelleRoleUtilise(Profil profil, Etablissement? actif) {
  final code = actif?.roleDansEtablissement;
  if (code != null && code.isNotEmpty) {
    return RoleRacine.depuisCode(code)?.libelle ?? '${code[0].toUpperCase()}${code.substring(1)}';
  }
  return profil.roleRacine?.libelle ?? 'Compte';
}

/// En-tête de l'application, pour tous les rôles : nom en grands
/// caractères, puis rôle utilisé (étiquette) et établissement actif. Le
/// parent a sur la même ligne son bouton « Ajouter » (un enfant), et ses
/// enfants en dessous.
class EnteteUtilisateur extends ConsumerWidget {
  const EnteteUtilisateur({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Espace utilisé (REG-27) : parent ou enseignant, au choix.
    final profil = ref.watch(profilAfficheProvider);
    if (profil == null) return const SizedBox.shrink();
    final espaces = ref.watch(espacesDisponiblesProvider);
    final role = ref.watch(roleUtiliseProvider);
    final actif = ref.watch(etablissementActifProvider);
    final logoUrl = actif == null ? null : ref.watch(identiteEtablissementProvider).logoUrl;
    final parent = profil.roleRacine == RoleRacine.parent;
    final slogan = actif?.slogan;
    final theme = Theme.of(context);
    final schema = theme.colorScheme;

    return Material(
      color: schema.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profil.nomAffiche,
                        key: const Key('entete_nom'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (espaces.length > 1)
                            // Plusieurs espaces : toucher l'étiquette pour changer.
                            PopupMenuButton<RoleRacine>(
                              key: const Key('entete_changer_espace'),
                              tooltip: 'Changer d’espace',
                              initialValue: role,
                              onSelected: (r) => ref.read(espaceChoisiProvider.notifier).choisir(r),
                              itemBuilder: (_) => [
                                for (final e in espaces)
                                  PopupMenuItem<RoleRacine>(
                                    key: Key('espace_${e.code}'),
                                    value: e,
                                    child: Text('Espace ${e.libelle.toLowerCase()}'),
                                  ),
                              ],
                              child: Container(
                                key: const Key('entete_role'),
                                padding: const EdgeInsets.fromLTRB(10, 3, 4, 3),
                                decoration: BoxDecoration(
                                  color: schema.secondaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      role?.libelle ?? libelleRoleUtilise(profil, actif),
                                      style: theme.textTheme.labelMedium?.copyWith(color: schema.onSecondaryContainer),
                                    ),
                                    Icon(Icons.arrow_drop_down, size: 18, color: schema.onSecondaryContainer),
                                  ],
                                ),
                              ),
                            )
                          else
                            Container(
                              key: const Key('entete_role'),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: schema.secondaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                libelleRoleUtilise(profil, actif),
                                style: theme.textTheme.labelMedium?.copyWith(color: schema.onSecondaryContainer),
                              ),
                            ),
                          if (actif != null)
                            Row(
                              key: const Key('entete_etablissement'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (logoUrl != null) ...[
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Colors.transparent,
                                    backgroundImage: NetworkImage(logoUrl),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 220),
                                  child: Text(
                                    actif.nom,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(color: schema.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (parent)
                  TextButton.icon(
                    key: const Key('entete_ajouter_enfant'),
                    onPressed: () => afficherAjouterEnfant(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter'),
                  ),
              ],
            ),
          ),
          // Slogan de l'école (REG-23), sous l'en-tête.
          if (slogan != null && slogan.isNotEmpty)
            Padding(
              key: const Key('entete_slogan'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
              child: Text(
                '« $slogan »',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: schema.primary),
              ),
            ),
          if (parent) const SelecteurEnfant(avecAjouter: false),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
