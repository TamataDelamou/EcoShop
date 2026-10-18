import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../paiement_mobile/presentation/widgets/identite_orange_money.dart' show formaterMontantMobile;
import '../../domain/inscription_en_ligne.dart';

String dateCourte(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String montant(double v, [String devise = 'GNF']) => formaterMontantMobile(v, devise);

/// Couleur d'une étape de dossier.
Color couleurStatut(BuildContext context, StatutDemandeInscription s) {
  final p = context.palette;
  return switch (s) {
    StatutDemandeInscription.inscrite => p.succes,
    StatutDemandeInscription.acceptee => p.primaire,
    StatutDemandeInscription.incomplete || StatutDemandeInscription.convoquee => p.accent,
    StatutDemandeInscription.refusee || StatutDemandeInscription.expiree => p.erreur,
    StatutDemandeInscription.listeAttente || StatutDemandeInscription.aExaminer => p.premium,
    _ => p.encreSecondaire,
  };
}

/// Pastille d'étape (« Acceptée — à régler », « Liste d'attente »…).
class PastilleStatut extends StatelessWidget {
  const PastilleStatut({super.key, required this.statut, this.enAttenteEnvoi = false});

  final StatutDemandeInscription statut;
  final bool enAttenteEnvoi;

  @override
  Widget build(BuildContext context) {
    final couleur = enAttenteEnvoi ? context.palette.encreSecondaire : couleurStatut(context, statut);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (enAttenteEnvoi) ...[
            Icon(Icons.schedule_send_outlined, size: 14, color: couleur),
            const SizedBox(width: 4),
          ],
          Text(
            enAttenteEnvoi ? "En attente d'envoi" : statut.libelle,
            style: TextStyle(color: couleur, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Ce que la famille doit comprendre et faire, selon l'étape du dossier.
String explicationStatut(DemandeInscription d) {
  if (d.enAttenteEnvoi) {
    return "Dossier enregistré sur ce téléphone. Il partira tout seul dès qu'il y aura du réseau ; "
        "vous recevrez alors le numéro définitif.";
  }
  return switch (d.statut) {
    StatutDemandeInscription.soumise => "L'école a reçu le dossier et va l'examiner.",
    StatutDemandeInscription.aExaminer => "L'école examine le dossier ; elle vous répondra ici.",
    StatutDemandeInscription.incomplete => "L'école attend des pièces : ajoutez-les ci-dessous.",
    StatutDemandeInscription.convoquee => "L'école vous convoque (voir le message ci-dessous).",
    StatutDemandeInscription.acceptee => d.montantARegler > 0
        ? 'Place réservée${d.offreExpireLe == null ? '' : " jusqu'au ${dateCourte(d.offreExpireLe!)}"}. '
            "Réglez les frais d'inscription par Orange Money, ou à l'école avec le numéro de dossier."
        : "Place réservée : l'inscription va être confirmée.",
    StatutDemandeInscription.listeAttente =>
      "Le niveau est complet. Le dossier est en liste d'attente${d.rangAttente == null ? '' : ' (rang ${d.rangAttente})'} : "
          'vous serez prévenu dès qu\'une place se libère.',
    StatutDemandeInscription.inscrite => "L'inscription est confirmée. Bienvenue !",
    StatutDemandeInscription.refusee => "L'école n'a pas retenu la demande.",
    StatutDemandeInscription.expiree =>
      "Le délai de réservation est dépassé : la place a été libérée. Contactez l'école si vous souhaitez toujours l'inscription.",
    StatutDemandeInscription.desistement => "Vous avez indiqué que l'élève ne revient pas l'an prochain.",
    StatutDemandeInscription.retiree => 'Vous avez retiré cette demande.',
  };
}

/// Carte d'un dossier (familles et Direction).
class CarteDossier extends StatelessWidget {
  const CarteDossier({super.key, required this.demande, this.onTap, this.actionEnAttente = false});

  final DemandeInscription demande;
  final VoidCallback? onTap;

  /// Une décision ou un paiement au guichet attend l'envoi (Direction).
  final bool actionEnAttente;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final d = demande;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: palette.primaire.withValues(alpha: 0.12),
                    child: Icon(d.estReinscription ? Icons.autorenew : Icons.person_add_alt_1_outlined,
                        size: 18, color: palette.primaire),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.nomComplet, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                          [
                            d.estReinscription ? 'Réinscription' : 'Nouvel élève',
                            if (d.niveauNom != null) d.niveauNom!,
                            if (d.etablissementNom != null) d.etablissementNom!,
                          ].join(' · '),
                          style: TextStyle(color: palette.encreSecondaire, fontSize: 12),
                        ),
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
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PastilleStatut(statut: d.statut, enAttenteEnvoi: d.enAttenteEnvoi),
                  Text('Dossier ${d.numeroDossier}', style: TextStyle(color: palette.encreSecondaire, fontSize: 12)),
                  if (d.aRegler)
                    Text('À régler : ${montant(d.montantARegler, d.devise)}',
                        style: TextStyle(color: palette.primaire, fontWeight: FontWeight.w700, fontSize: 12)),
                  if (d.impaye != null) _Signal(icone: Icons.money_off_outlined, texte: 'Impayé ${montant(d.impaye!, d.devise)}'),
                  if (d.sanctionActive) const _Signal(icone: Icons.gavel_outlined, texte: 'Sanction en cours'),
                  if (d.doublonPossible) const _Signal(icone: Icons.content_copy_outlined, texte: 'Doublon possible'),
                  if (d.piecesManquantes.isNotEmpty && !d.statut.estClos)
                    _Signal(icone: Icons.attach_file, texte: '${d.piecesManquantes.length} pièce(s) manquante(s)'),
                  if (actionEnAttente) const _Signal(icone: Icons.schedule_send_outlined, texte: 'Décision en attente d\'envoi'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Signal extends StatelessWidget {
  const _Signal({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final couleur = context.palette.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 14, color: couleur),
        const SizedBox(width: 3),
        Text(texte, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Encadré d'information ou d'erreur.
class Encadre extends StatelessWidget {
  const Encadre({super.key, required this.texte, this.icone = Icons.info_outline, this.couleur});

  final String texte;
  final IconData icone;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final c = couleur ?? context.palette.primaire;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: c, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(texte, style: TextStyle(color: context.palette.encre))),
        ],
      ),
    );
  }
}

/// Message d'une erreur, quelle qu'elle soit.
String messageErreur(Object e) =>
    e is ErreurInscriptionEnLigne ? e.messageUtilisateur : 'Opération impossible pour le moment. Réessayez.';
