import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/sync/entites_differees.dart';
import '../../../core/sync/sync_engine.dart';

/// Rejeu des opérations mises en file par le lot 4 (REG-35) : ce qui
/// exigeait encore le réseau et se fait désormais aussi sans lui.
///
/// Trois règles, tirées de la recherche (Stripe, Replicache, retours
/// d'expérience des applications hors ligne) :
///
/// 1. **Exactement une fois.** Une création porte un identifiant tiré sur
///    le téléphone (clé d'idempotence, comme chez Stripe) : rejouée deux
///    fois, la seconde se heurte à la clé primaire (23505) et vaut succès.
/// 2. **Jamais d'écrasement silencieux d'une décision.** Une décision
///    (congé, sanction) n'est appliquée que si l'état est encore celui que
///    l'utilisateur a vu (« demande », « proposée »…) — l'équivalent d'un
///    `If-Match`. Prise entre-temps par quelqu'un d'autre : refus visible,
///    sauf si la même décision a déjà été prise (rien à faire).
/// 3. **Un refus reste visible.** Droits, contrôles, conflit : [RejetDefinitif]
///    (journal des refus, bandeau) ; une panne de réseau est retentée.
class RejeuActionsDifferees {
  RejeuActionsDifferees(this._client);

  final SupabaseClient _client;

  static const evaluationCreation = EntitesDifferees.evaluationCreation;
  static const evaluationPublication = EntitesDifferees.evaluationPublication;
  static const sanctionProposition = EntitesDifferees.sanctionProposition;
  static const sanctionValidation = EntitesDifferees.sanctionValidation;
  static const sanctionStatut = EntitesDifferees.sanctionStatut;
  static const congeDecision = EntitesDifferees.congeDecision;
  static const inscriptionBoursier = EntitesDifferees.inscriptionBoursier;
  static const progressionStatut = EntitesDifferees.progressionStatut;
  static const lignePanierSuppression = EntitesDifferees.lignePanierSuppression;

  static const entites = EntitesDifferees.toutes;

  /// États d'où l'on peut passer à chaque statut de sanction.
  static const predecesseursSanction = {
    'notifiee': ['proposee'],
    'executee': ['notifiee'],
    'annulee': ['proposee', 'notifiee'],
  };

  /// Libellé d'une opération refusée, pour le journal des refus.
  static String libelle(SyncEntree entree) => switch (entree.entite) {
        evaluationCreation => 'Création d’une évaluation',
        evaluationPublication => 'Publication des notes',
        sanctionProposition => 'Proposition de sanction',
        sanctionValidation => 'Validation d’une sanction',
        sanctionStatut => 'Changement d’état d’une sanction',
        congeDecision => 'Décision sur un congé',
        inscriptionBoursier => 'Statut boursier',
        progressionStatut => 'Progression pédagogique',
        lignePanierSuppression => 'Article retiré du panier',
        _ => 'Opération',
      };

  Future<void> rejouer(SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      switch (entree.entite) {
        case evaluationCreation:
          await _creer('evaluations', p);
        case sanctionProposition:
          await _creer('sanctions', p);
        case evaluationPublication:
          await _client
              .from('evaluations')
              .update({'statut': 'publiee', 'publie_le': p['publie_le']})
              .eq('id', p['id'] as String)
              .isFilter('publie_le', null);
        case sanctionValidation:
          await _client
              .from('sanctions')
              .update({'validee_par': p['validee_par'], 'validee_le': p['validee_le']})
              .eq('id', p['id'] as String)
              .isFilter('validee_le', null);
        case sanctionStatut:
          await _decider(
            table: 'sanctions',
            id: p['id'] as String,
            valeurs: {'statut': p['statut']},
            statutVoulu: p['statut'] as String,
            statutsAttendus: predecesseursSanction[p['statut']] ?? const [],
            codeConflit: 'SANCTION_DEJA_TRAITEE',
            messageConflit: 'Cette sanction a changé entre-temps (décision prise par quelqu’un d’autre) : '
                'votre choix n’a pas été appliqué. Vérifiez son état actuel.',
          );
        case congeDecision:
          await _decider(
            table: 'conges',
            id: p['id'] as String,
            valeurs: {
              'statut': p['statut'],
              'valide_par': p['valide_par'],
              'date_validation': p['date_validation'],
            },
            statutVoulu: p['statut'] as String,
            statutsAttendus: const ['demande'],
            codeConflit: 'CONGE_DEJA_TRAITE',
            messageConflit: 'Ce congé a été traité entre-temps par quelqu’un d’autre : '
                'votre décision n’a pas été appliquée. Vérifiez son état actuel.',
          );
        case inscriptionBoursier:
          // Un seul champ, décidé par la Direction : la dernière décision
          // l'emporte, comme en ligne.
          await _client.from('inscriptions').update({'boursier': p['boursier']}).eq('id', p['id'] as String);
        case progressionStatut:
          await _client.from('progression_pedagogique').update({'statut': p['statut']}).eq('id', p['id'] as String);
        case lignePanierSuppression:
          // Supprimer deux fois revient au même.
          await _client.from('lignes_paniers').delete().eq('id', p['id'] as String);
      }
    } on PostgrestException catch (e) {
      final code = e.code ?? '';
      if (code == '42501' || code.startsWith('23') || code.startsWith('22') || code == 'P0001') {
        final premier = e.message.trim().split(RegExp(r'\s+')).first;
        final metier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier);
        throw RejetDefinitif(
          metier ? premier : (code == '42501' ? 'PERMISSION_REFUSEE' : 'REFUS'),
          code == '42501'
              ? 'Le serveur a refusé cette opération : vos droits ne la permettent plus.'
              : 'Le serveur a refusé cette opération : ${e.message}',
        );
      }
      rethrow;
    }
  }

  /// Insertion avec l'identifiant tiré sur le téléphone ; déjà présente
  /// (rejeu après une coupure) : rien à faire.
  Future<void> _creer(String table, Map<String, dynamic> ligne) async {
    try {
      await _client.from(table).insert(ligne);
    } on PostgrestException catch (e) {
      if (e.code == '23505') return;
      rethrow;
    }
  }

  /// Décision appliquée seulement depuis un état attendu ; sinon refus
  /// visible, sauf si la même décision est déjà en place.
  Future<void> _decider({
    required String table,
    required String id,
    required Map<String, dynamic> valeurs,
    required String statutVoulu,
    required List<String> statutsAttendus,
    required String codeConflit,
    required String messageConflit,
  }) async {
    final modifiees = await _client
        .from(table)
        .update(valeurs)
        .eq('id', id)
        .inFilter('statut', statutsAttendus)
        .select('id');
    if (modifiees.isNotEmpty) return;
    final actuelle = await _client.from(table).select('statut').eq('id', id).maybeSingle();
    if (actuelle == null) {
      throw const RejetDefinitif('INTROUVABLE', 'L’élément concerné n’existe plus : votre décision n’a pas été appliquée.');
    }
    if (actuelle['statut'] == statutVoulu) return; // même décision déjà prise
    if (statutsAttendus.contains(actuelle['statut'])) {
      // État inchangé mais rien de modifié : les droits ne le permettent pas.
      throw const RejetDefinitif('PERMISSION_REFUSEE',
          'Le serveur a refusé cette décision : vos droits ne la permettent plus.');
    }
    throw RejetDefinitif(codeConflit, messageConflit);
  }
}
