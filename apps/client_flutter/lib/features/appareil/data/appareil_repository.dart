import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/etat_appareil.dart';

/// Accès au serveur pour le code du compte et les appareils (REG-22).
/// Surchargé par un double en test.
abstract interface class AppareilRepository {
  /// Décrit l'appareil (après chaque connexion) et renvoie son état.
  Future<EtatAppareil> enregistrer({required String modele, required String systeme, required String version});
  Future<EtatAppareil> etat();

  Future<void> definirCode(String code);
  Future<ResultatCodeCompte> verifierCode(String code);
  Future<int> changerCode(String ancien, String nouveau);

  Future<DemandeAppareil> demanderApprobation();
  Future<void> approuver(String demandeId);
  Future<void> refuser(String demandeId);
  Future<int> choisirCodeApresAutorisation(String nouveau);

  Future<DemandeAppareil> lancerRecuperation();
  Future<void> annulerRecuperation(String demandeId);
  Future<int> finaliserRecuperation(String nouveau);

  Future<List<PersonneDebloquable>> personnesDebloquables(String etablissementId, String recherche);
  Future<List<PersonneDebloquable>> chercherCompteGsg(String recherche);
  Future<DateTime> debloquer({required String compteId, required String motif, String? etablissementId});

  Future<List<AppareilConnecte>> mesAppareils();
  Future<void> deconnecterAppareil(String sessionId);
  Future<int> deconnecterAutres();
}

class SupabaseAppareilRepository implements AppareilRepository {
  const SupabaseAppareilRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _objet(String fonction, [Map<String, dynamic>? params]) => _executer(() async {
    final r = await _client.rpc<dynamic>(fonction, params: params);
    return (r as Map).cast<String, dynamic>();
  });

  @override
  Future<EtatAppareil> enregistrer({required String modele, required String systeme, required String version}) async =>
      EtatAppareil.depuisJson(
        await _objet('enregistrer_appareil', {'p_modele': modele, 'p_systeme': systeme, 'p_version': version}),
      );

  @override
  Future<EtatAppareil> etat() async => EtatAppareil.depuisJson(await _objet('etat_appareil'));

  @override
  Future<void> definirCode(String code) => _objet('definir_code_compte', {'p_code': code});

  @override
  Future<ResultatCodeCompte> verifierCode(String code) async {
    try {
      final r = await _objet('verifier_code_compte', {'p_code': code});
      return switch (r['resultat']) {
        'bon' => CodeCompteBon((r['version_code'] as num?)?.toInt() ?? 1),
        'faux' => CodeCompteFaux((r['essais_restants'] as num?)?.toInt() ?? 0),
        _ => CodeCompteBloque(DateTime.tryParse('${r['jusqu_a']}')?.toLocal()),
      };
    } on ErreurCodeCompte catch (e) {
      if (e.code == 'CODE_BLOQUE') return const CodeCompteBloque(null);
      rethrow;
    }
  }

  @override
  Future<int> changerCode(String ancien, String nouveau) async =>
      ((await _objet('changer_code_compte', {'p_ancien': ancien, 'p_nouveau': nouveau}))['version_code'] as num).toInt();

  @override
  Future<DemandeAppareil> demanderApprobation() async {
    final r = await _objet('demander_approbation_appareil');
    return DemandeAppareil(
      id: r['id'] as String,
      type: TypeDemandeAppareil.approbation,
      echeance: DateTime.parse(r['echeance'] as String).toLocal(),
      statut: 'en_attente',
    );
  }

  @override
  Future<void> approuver(String demandeId) =>
      _executer(() => _client.rpc<dynamic>('approuver_appareil', params: {'p_demande': demandeId}));

  @override
  Future<void> refuser(String demandeId) =>
      _executer(() => _client.rpc<dynamic>('refuser_appareil', params: {'p_demande': demandeId}));

  @override
  Future<int> choisirCodeApresAutorisation(String nouveau) async =>
      ((await _objet('choisir_code_apres_autorisation', {'p_nouveau': nouveau}))['version_code'] as num).toInt();

  @override
  Future<DemandeAppareil> lancerRecuperation() async {
    final r = await _objet('lancer_recuperation_code');
    return DemandeAppareil(
      id: r['id'] as String,
      type: TypeDemandeAppareil.recuperation,
      echeance: DateTime.parse(r['echeance'] as String).toLocal(),
      statut: 'en_attente',
    );
  }

  @override
  Future<void> annulerRecuperation(String demandeId) =>
      _executer(() => _client.rpc<dynamic>('annuler_recuperation', params: {'p_demande': demandeId}));

  @override
  Future<int> finaliserRecuperation(String nouveau) async =>
      ((await _objet('finaliser_recuperation_code', {'p_nouveau': nouveau}))['version_code'] as num).toInt();

  @override
  Future<List<PersonneDebloquable>> personnesDebloquables(String etablissementId, String recherche) =>
      _executer(() async {
        final r = await _client.rpc<dynamic>('personnes_debloquables',
            params: {'p_etablissement': etablissementId, 'p_recherche': recherche});
        return [for (final l in (r as List)) PersonneDebloquable.depuisJson((l as Map).cast<String, dynamic>())];
      });

  @override
  Future<List<PersonneDebloquable>> chercherCompteGsg(String recherche) => _executer(() async {
    final r = await _client.rpc<dynamic>('chercher_compte_gsg', params: {'p_recherche': recherche});
    return [for (final l in (r as List)) PersonneDebloquable.depuisJson((l as Map).cast<String, dynamic>())];
  });

  @override
  Future<DateTime> debloquer({required String compteId, required String motif, String? etablissementId}) async {
    final r = await _objet('debloquer_code_membre',
        {'p_compte': compteId, 'p_motif': motif, 'p_etablissement': etablissementId});
    return DateTime.parse(r['echeance'] as String).toLocal();
  }

  @override
  Future<List<AppareilConnecte>> mesAppareils() => _executer(() async {
    final r = await _client.rpc<dynamic>('mes_appareils');
    return [for (final l in (r as List)) AppareilConnecte.depuisJson((l as Map).cast<String, dynamic>())];
  });

  @override
  Future<void> deconnecterAppareil(String sessionId) =>
      _executer(() => _client.rpc<dynamic>('deconnecter_appareil', params: {'p_session': sessionId}));

  @override
  Future<int> deconnecterAutres() => _executer(() async {
    final r = await _client.rpc<dynamic>('deconnecter_autres_appareils');
    return (r as num?)?.toInt() ?? 0;
  });

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      final code = codeErreurServeur(e.message);
      throw ErreurCodeCompte(code, ErreurCodeCompte.messagePour(code));
    }
  }
}

/// Code d'erreur métier (en majuscules) contenu dans le message du serveur.
String codeErreurServeur(String message) =>
    RegExp(r'[A-Z][A-Z_]{3,}').firstMatch(message)?.group(0) ?? message;
