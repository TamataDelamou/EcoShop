/// Invitations du personnel et des vendeurs (REG-18, suite).
///
/// La direction invite une adresse e-mail (voie privilégiée : un courriel
/// part aussitôt) ou un numéro de téléphone (aucun SMS). Après sa connexion,
/// l'invité voit les invitations adressées à ses identifiants et les accepte
/// ou les refuse. Règle REG-16 : seul un identifiant prouvé vaut — l'adresse
/// par la connexion, le numéro par l'école (« Numéros à confirmer »).
library;

import '../../../core/auth/role_racine.dart';

/// Rôles qu'une école peut proposer par invitation. « Direction » est
/// réservé au fondateur et au directeur (REG-22) ; secrétaire, caissier,
/// comptable, surveillant… sont du personnel, avec leur poste.
const rolesInvitables = [RoleRacine.enseignant, RoleRacine.personnel, RoleRacine.direction, RoleRacine.vendeur];

String libelleRoleInvitation(String? code) => switch (code) {
      'enseignant' => 'Enseignant',
      'direction' => 'Direction (fondateur, directeur)',
      'personnel' => 'Personnel administratif et technique',
      'vendeur' => 'Vendeur',
      _ => code ?? '',
    };

/// Invitation reçue par le compte connecté (`mes_invitations`).
class InvitationRecue {
  const InvitationRecue({
    required this.id,
    required this.etablissement,
    required this.roleCible,
    required this.identifiant,
    required this.parTelephone,
    required this.verifie,
    this.poste,
    this.invitePar,
    this.expireLe,
  });

  factory InvitationRecue.depuisJson(Map<String, dynamic> j) => InvitationRecue(
        id: j['id'] as String,
        etablissement: (j['etablissement'] as String?) ?? 'Établissement',
        roleCible: j['role_cible'] as String? ?? '',
        identifiant: j['identifiant'] as String? ?? '',
        parTelephone: j['par_telephone'] == true,
        verifie: j['verifie'] == true,
        poste: j['poste'] as String?,
        invitePar: j['invite_par'] as String?,
        expireLe: DateTime.tryParse(j['expire_le'] as String? ?? '')?.toLocal(),
      );

  final String id;
  final String etablissement;
  final String roleCible;

  /// Adresse ou numéro auquel l'invitation a été envoyée.
  final String identifiant;
  final bool parTelephone;

  /// Faux : numéro seulement déclaré, l'école doit le confirmer avant que
  /// l'invitation puisse être acceptée ou refusée.
  final bool verifie;
  final String? poste;
  final String? invitePar;
  final DateTime? expireLe;
}

enum StatutInvitation {
  enAttente('en_attente', 'En attente'),
  acceptee('acceptee', 'Acceptée'),
  refusee('refusee', 'Refusée'),
  revoquee('revoquee', 'Retirée'),
  expiree('expiree', 'Expirée');

  const StatutInvitation(this.code, this.libelle);
  final String code;
  final String libelle;

  static StatutInvitation depuisCode(String? code) =>
      StatutInvitation.values.firstWhere((s) => s.code == code, orElse: () => StatutInvitation.expiree);
}

/// Invitation suivie par la direction (`invitations_etablissement`).
class InvitationEnvoyee {
  const InvitationEnvoyee({
    required this.id,
    required this.identifiant,
    required this.roleCible,
    required this.statut,
    this.poste,
    this.creeLe,
    this.expireLe,
    this.membre,
    this.code,
    this.parCode = false,
  });

  factory InvitationEnvoyee.depuisJson(Map<String, dynamic> j) => InvitationEnvoyee(
        id: j['id'] as String,
        identifiant: j['identifiant'] as String? ?? '',
        roleCible: j['role_cible'] as String? ?? '',
        statut: StatutInvitation.depuisCode(j['statut'] as String?),
        poste: j['poste'] as String?,
        creeLe: DateTime.tryParse(j['cree_le'] as String? ?? '')?.toLocal(),
        expireLe: DateTime.tryParse(j['expire_le'] as String? ?? '')?.toLocal(),
        membre: j['membre'] as String?,
        code: j['code'] as String?,
        parCode: j['par_code'] == true,
      );

  final String id;
  final String identifiant;
  final String roleCible;
  final StatutInvitation statut;
  final String? poste;
  final DateTime? creeLe;
  final DateTime? expireLe;

  /// Nom du compte qui a accepté.
  final String? membre;

  /// Code à remettre à la personne (REG-27), tant que l'invitation attend.
  final String? code;

  /// Acceptée avec le code (et non avec l'identifiant invité).
  final bool parCode;

  /// « K7Q2M9XD » → « K7Q2-M9XD ».
  String? get codeAffiche => code == null || code!.length != 8 ? code : '${code!.substring(0, 4)}-${code!.substring(4)}';
}

/// Invitation acceptée avec un code (REG-27).
class InvitationAcceptee {
  const InvitationAcceptee({required this.etablissementId, required this.etablissement, required this.role});

  final String etablissementId;
  final String etablissement;
  final String role;
}

class PosteInvitable {
  const PosteInvitable(this.id, this.nom);
  final String id;
  final String nom;
}

class ErreurInvitations implements Exception {
  const ErreurInvitations(this.code, [this.detail]);

  final String code;
  final String? detail;

  String get message => switch (code) {
        'IDENTIFIANT_NON_VERIFIE' =>
          'Ce numéro n’est pas encore confirmé. Faites-le confirmer par l’école, en sa présence, puis réessayez.',
        'INVITATION_AUTRE_DESTINATAIRE' => 'Cette invitation ne vous est pas destinée.',
        'INVITATION_DEJA_TRAITEE' => 'Cette invitation a déjà reçu une réponse.',
        'INVITATION_EXPIREE' => 'Cette invitation a expiré. Demandez à l’école de vous en envoyer une nouvelle.',
        'INVITATION_INTROUVABLE' => 'Invitation introuvable : elle a peut-être été retirée.',
        'IDENTIFIANT_INVALIDE' => 'Saisissez une adresse e-mail, ou un numéro avec l’indicatif (+224…).',
        'ROLE_NON_INVITABLE' => 'Ce rôle ne s’obtient pas par invitation.',
        'POSTE_INVALIDE' => 'Ce poste n’existe plus. Actualisez la liste.',
        'POSTE_OBLIGATOIRE' => 'Choisissez le poste de cette personne : ses droits en dépendent.',
        'DEJA_MEMBRE' => 'Cette personne est déjà membre de l’école avec ce rôle.',
        'PERMISSION_REFUSEE' => 'Réservé à la direction de l’école.',
        'CODE_INVALIDE' => 'Le code compte 8 caractères (lettres et chiffres), par exemple K7Q2-M9XD.',
        'CODE_INCONNU' => 'Code inconnu, déjà utilisé ou retiré. Vérifiez-le auprès de l’école.',
        'TROP_D_ESSAIS' => 'Trop d’essais. Réessayez dans une heure, ou demandez un nouveau code à l’école.',
        'ERREUR_RESEAU' => 'Pas de connexion. Réessayez une fois en ligne.',
        _ => 'Une erreur est survenue. Réessayez.',
      };

  @override
  String toString() => 'ErreurInvitations($code)';
}

abstract interface class InvitationsRepository {
  Future<List<InvitationRecue>> mesInvitations();

  /// Accepte (vrai) ou refuse l'invitation.
  Future<void> repondre(String invitationId, {required bool accepter});

  Future<List<InvitationEnvoyee>> invitationsEtablissement(String etablissementId);

  Future<List<PosteInvitable>> postes(String etablissementId);

  Future<void> inviter({
    required String etablissementId,
    required String identifiant,
    required RoleRacine role,
    String? posteId,
  });

  Future<void> revoquer(String invitationId);

  /// Accepte l'invitation dont la Direction a remis le code (REG-27).
  Future<InvitationAcceptee> accepterParCode(String code);
}

/// Normalise la saisie de la direction : adresse en minuscules, ou numéro
/// E.164 (« +224 620 00 00 00 » → « +224620000000 »). Null si invalide.
String? normaliserIdentifiantInvitation(String saisie) {
  final v = saisie.trim();
  if (v.contains('@')) {
    final e = v.toLowerCase();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e) ? e : null;
  }
  final t = v.replaceAll(RegExp(r'[\s.\-()]'), '');
  return RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(t) ? t : null;
}
