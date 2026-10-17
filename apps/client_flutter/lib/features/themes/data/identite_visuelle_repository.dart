import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Bucket public des logos d'établissement (migration 20260906001531).
const bucketLogosEtablissements = 'logos-etablissements';

/// Port d'écriture de l'identité visuelle d'un établissement (REG-07 B).
/// Toujours réseau direct : réservé à la Direction, jamais mis en file.
abstract interface class IdentiteVisuelleRepository {
  /// Dépose le logo dans le dossier de l'établissement ; renvoie son chemin.
  Future<String> televerserLogo(String etablissementId, Uint8List octets, String extension);

  /// Enregistre couleur (`#RRGGBB`) et logo ; null = retour au défaut.
  Future<void> enregistrer({required String etablissementId, String? couleurHex, String? logoChemin});
}

class ErreurIdentiteVisuelle implements Exception {
  const ErreurIdentiteVisuelle(this.code);

  final String code;

  String get messageUtilisateur => switch (code) {
        'ACCES_REFUSE' => "Seule la Direction de l'établissement peut modifier son identité visuelle.",
        'COULEUR_INVALIDE' => 'Couleur invalide : utilisez le format #RRGGBB.',
        'LOGO_TROP_LOURD' => 'Le logo dépasse 1 Mo. Choisissez une image plus légère.',
        _ => 'Enregistrement impossible pour le moment. Vérifiez votre connexion et réessayez.',
      };

  @override
  String toString() => 'ErreurIdentiteVisuelle($code)';
}

class SupabaseIdentiteVisuelleRepository implements IdentiteVisuelleRepository {
  const SupabaseIdentiteVisuelleRepository(this._client);

  final SupabaseClient _client;

  static const tailleMaxOctets = 1024 * 1024;

  @override
  Future<String> televerserLogo(String etablissementId, Uint8List octets, String extension) async {
    if (octets.length > tailleMaxOctets) throw const ErreurIdentiteVisuelle('LOGO_TROP_LOURD');
    final ext = extension == 'png' ? 'png' : 'jpg';
    final chemin = '$etablissementId/logo-${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await _client.storage.from(bucketLogosEtablissements).uploadBinary(
            chemin,
            octets,
            fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg', upsert: true),
          );
      return chemin;
    } on StorageException catch (e) {
      throw ErreurIdentiteVisuelle(e.statusCode == '403' ? 'ACCES_REFUSE' : 'ERREUR_RESEAU');
    }
  }

  @override
  Future<void> enregistrer({required String etablissementId, String? couleurHex, String? logoChemin}) async {
    try {
      await _client.rpc<dynamic>('definir_identite_visuelle', params: {
        'p_etablissement_id': etablissementId,
        'p_couleur': couleurHex,
        'p_logo_chemin': logoChemin,
      });
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      throw ErreurIdentiteVisuelle(RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier) ? premier : 'ERREUR_RESEAU');
    }
  }
}
