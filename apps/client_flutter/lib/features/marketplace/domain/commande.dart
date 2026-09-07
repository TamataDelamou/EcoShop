import 'enums_marketplace.dart';

/// Projection cliente de `public.commandes` (M13). Pas de colonne
/// `modifie_le`/`device_id` côté serveur (contrairement à `paniers`) : une
/// commande est un acte transactionnel créé en ligne, jamais rejouée
/// hors-ligne (cohérent avec l'absence de tolérance hors-ligne du DDL réel).
class Commande {
  const Commande({
    required this.id,
    required this.etablissementId,
    required this.commercantId,
    required this.profileId,
    this.panierId,
    required this.reference,
    this.statut = StatutCommande.brouillon,
    this.montantTotal = 0,
    this.montantFrais = 0,
    this.devise = 'XOF',
    this.nomCommercant,
  });

  factory Commande.depuisJson(Map<String, dynamic> json) {
    final commercant = json['commercants'] as Map<String, dynamic>?;
    return Commande(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      commercantId: json['commercant_id'] as String,
      profileId: json['profile_id'] as String,
      panierId: json['panier_id'] as String?,
      reference: json['reference'] as String,
      statut: StatutCommande.depuisCode(json['statut'] as String?),
      montantTotal: (json['montant_total'] as num?)?.toDouble() ?? 0,
      montantFrais: (json['montant_frais'] as num?)?.toDouble() ?? 0,
      devise: json['devise'] as String? ?? 'XOF',
      nomCommercant: commercant?['nom'] as String?,
    );
  }

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'commercant_id': commercantId,
        'profile_id': profileId,
        'panier_id': panierId,
        'reference': reference,
        'statut': statut.code,
        'montant_total': montantTotal,
        'montant_frais': montantFrais,
        'devise': devise,
        'nom_commercant': nomCommercant,
      };

  factory Commande.depuisJsonCache(Map<String, dynamic> json) => Commande(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        commercantId: json['commercant_id'] as String,
        profileId: json['profile_id'] as String,
        panierId: json['panier_id'] as String?,
        reference: json['reference'] as String,
        statut: StatutCommande.depuisCode(json['statut'] as String?),
        montantTotal: (json['montant_total'] as num?)?.toDouble() ?? 0,
        montantFrais: (json['montant_frais'] as num?)?.toDouble() ?? 0,
        devise: json['devise'] as String? ?? 'XOF',
        nomCommercant: json['nom_commercant'] as String?,
      );

  /// Colonnes réelles de `public.commandes` — pour la création (insert
  /// uniquement, jamais d'upsert : une commande n'est jamais rejouée).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'commercant_id': commercantId,
        'profile_id': profileId,
        'panier_id': panierId,
        'reference': reference,
        'statut': statut.code,
        'montant_total': montantTotal,
        'montant_frais': montantFrais,
        'devise': devise,
      };

  final String id;
  final String etablissementId;
  final String commercantId;
  final String profileId;
  final String? panierId;
  final String reference;
  final StatutCommande statut;
  final double montantTotal;
  final double montantFrais;
  final String devise;

  /// Peuplé via l'embed PostgREST — affichage uniquement.
  final String? nomCommercant;
}
