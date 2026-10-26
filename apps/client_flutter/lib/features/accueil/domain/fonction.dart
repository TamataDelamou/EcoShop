import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../auth/domain/profil.dart';
import '../../etablissement/domain/etablissement.dart';
import '../../scolarite/domain/fiche_eleve.dart';

/// Couleur d'une pastille (maquettes REG-21) : fond clair et icône foncée en
/// mode clair ; l'inverse, atténué, en mode sombre. Contraste de l'icône sur
/// son fond ≥ 4,5:1 dans les deux modes.
enum Teinte {
  vert(Color(0xFFE3F2EA), Color(0xFF17603C), Color(0xFF1F3A2C), Color(0xFF8FD3AE)),
  bleu(Color(0xFFE6F0FB), Color(0xFF1E4FA8), Color(0xFF1C2A44), Color(0xFF9DBDF2)),
  sarcelle(Color(0xFFE1F3F4), Color(0xFF136B72), Color(0xFF173638), Color(0xFF86D1D7)),
  violet(Color(0xFFEEE9FB), Color(0xFF5233A8), Color(0xFF2B2445), Color(0xFFBCA8F2)),
  rose(Color(0xFFFBE4E8), Color(0xFFA3233B), Color(0xFF41222A), Color(0xFFF2A3B2)),
  orange(Color(0xFFFCEBDD), Color(0xFFA2460D), Color(0xFF43291A), Color(0xFFF2B48A)),
  jaune(Color(0xFFFFF1D6), Color(0xFF855004), Color(0xFF3D3019), Color(0xFFEDC77E)),
  gris(Color(0xFFEDEFEC), Color(0xFF3B4541), Color(0xFF2C312F), Color(0xFFC3CBC7));

  const Teinte(this.fondClair, this.iconeClair, this.fondSombre, this.iconeSombre);

  final Color fondClair;
  final Color iconeClair;
  final Color fondSombre;
  final Color iconeSombre;
}

/// Ce que l'accueil sait du compte pour décider des pastilles.
class ContexteAccueil {
  const ContexteAccueil({
    required this.profil,
    this.etablissement,
    this.droits = const {},
    this.enfant,
    this.maFiche,
    this.anneeId,
    this.chauffeur = false,
  });

  final Profil profil;
  final Etablissement? etablissement;

  /// Droits du poste (rôle « personnel »).
  final Set<String> droits;

  /// Parent : enfant actif.
  final FicheEleve? enfant;

  /// Élève : sa fiche.
  final FicheEleve? maFiche;
  final String? anneeId;

  /// Un circuit de transport lui est confié.
  final bool chauffeur;

  RoleRacine? get role => profil.roleRacine;
  bool get direction => role == RoleRacine.direction;
  bool get enseignant => role == RoleRacine.enseignant;
  bool get parent => role == RoleRacine.parent;
  bool get eleve => role == RoleRacine.eleve;
  bool get personnel => role == RoleRacine.personnel;
  bool get ecole => etablissement != null;

  /// Direction, ou poste qui porte l'un des codes.
  bool peut(List<String> codes) => direction || codes.any(droits.contains);

  /// Fiche concernée : l'enfant (parent) ou sa propre fiche (élève).
  FicheEleve? get fiche => parent ? enfant : (eleve ? maFiche : null);
}

typedef Ouvrir = void Function(BuildContext context, WidgetRef ref, ContexteAccueil c);

/// Une fonction de l'application, montrée en pastille sur l'accueil.
class Fonction {
  const Fonction({
    required this.id,
    required this.libelle,
    required this.icone,
    required this.teinte,
    required this.groupe,
    required this.visible,
    required this.ouvrir,
    this.motsCles = const [],
    this.badge,
    this.libelleBadge = 'nouveau',
    this.ancienne,
  });

  /// Identifiant stable (raccourcis gardés sur l'appareil, clés de test).
  final String id;

  /// Deux mots au plus, si possible.
  final String libelle;
  final IconData icone;
  final Teinte teinte;

  /// Groupe de la direction (« Finances »…) ; les autres rôles n'ont qu'un
  /// groupe.
  final String groupe;

  /// Mots-clés de la recherche (« reçu » → Encaissements).
  final List<String> motsCles;

  /// Clé du résumé serveur qui donne le badge (`accueil_resume`).
  final String? badge;

  /// Lu par TalkBack : « Annonces, 3 nouvelles ».
  final String libelleBadge;

  /// Ancienne entrée de « Mon profil » (table de correspondance).
  final String? ancienne;

  final bool Function(ContexteAccueil c) visible;
  final Ouvrir ouvrir;
}
