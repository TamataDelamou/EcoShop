import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import 'ecran_connexion.dart';

/// Accueil pré-authentification — orientation vers l'un des espaces de
/// l'application avant la connexion OTP (cahier v4.1, doc M15 §2.1).
///
/// Un seul mécanisme d'authentification existe (OTP, ch. 5.4) : ce choix est
/// une aide à l'orientation, pas un embranchement technique. Toute action au
/// delà de cet écran — y compris le Marketplace — exige un compte
/// authentifié ; un compte « Parent » auto-inscrit sans enfant rattaché reste
/// un client Marketplace valide (aucun établissement requis tant qu'il n'a
/// pas plus d'un rattachement, cf. `GardeSession.resoudre`).
class EcranChoixEspace extends StatefulWidget {
  const EcranChoixEspace({super.key});

  @override
  State<EcranChoixEspace> createState() => _EcranChoixEspaceState();
}

class _EcranChoixEspaceState extends State<EcranChoixEspace> {
  bool _espaceChoisi = false;

  @override
  Widget build(BuildContext context) {
    if (_espaceChoisi) return const EcranConnexion();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('EcoShop', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Quel espace souhaitez-vous rejoindre ?',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  _CarteEspace(
                    icone: Icons.storefront_outlined,
                    couleur: context.palette.accent,
                    titre: 'Marketplace',
                    description: 'Parcourir le catalogue et commander — un compte suffit, sans établissement requis.',
                    onTap: () => setState(() => _espaceChoisi = true),
                  ),
                  _CarteEspace(
                    icone: Icons.apartment_outlined,
                    couleur: context.palette.primaire,
                    titre: 'Espace Établissement',
                    description: 'Direction et personnel administratif.',
                    onTap: () => setState(() => _espaceChoisi = true),
                  ),
                  _CarteEspace(
                    icone: Icons.groups_outlined,
                    couleur: context.palette.primaire,
                    titre: 'Espace Enseignant',
                    description: 'Notes, présences et progression pédagogique.',
                    onTap: () => setState(() => _espaceChoisi = true),
                  ),
                  _CarteEspace(
                    icone: Icons.family_restroom_outlined,
                    couleur: context.palette.succes,
                    titre: 'Espace Parent / Élève',
                    description: 'Suivi de la scolarité et révision.',
                    onTap: () => setState(() => _espaceChoisi = true),
                  ),
                  _CarteEspace(
                    icone: Icons.admin_panel_settings_outlined,
                    couleur: context.palette.premium,
                    titre: 'Administration',
                    description: 'Réseau GSG et contenu pédagogique.',
                    onTap: () => setState(() => _espaceChoisi = true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CarteEspace extends StatelessWidget {
  const _CarteEspace({
    required this.icone,
    required this.couleur,
    required this.titre,
    required this.description,
    required this.onTap,
  });

  final IconData icone;
  final Color couleur;
  final String titre;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: couleur.withValues(alpha: 0.12), child: Icon(icone, color: couleur)),
        title: Text(titre, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
