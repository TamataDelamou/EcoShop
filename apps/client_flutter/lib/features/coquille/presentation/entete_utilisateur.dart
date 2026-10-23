import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/profil.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../scolarite/presentation/widgets/ajouter_enfant_sheet.dart';
import '../../scolarite/presentation/widgets/selecteur_enfant.dart';
import '../../themes/application/theme_providers.dart';

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
    final profil = ref.watch(profilProvider).valueOrNull;
    if (profil == null) return const SizedBox.shrink();
    final actif = ref.watch(etablissementActifProvider);
    final logoUrl = actif == null ? null : ref.watch(identiteEtablissementProvider).logoUrl;
    final parent = profil.roleRacine == RoleRacine.parent;
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
          if (parent) const SelecteurEnfant(avecAjouter: false),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
