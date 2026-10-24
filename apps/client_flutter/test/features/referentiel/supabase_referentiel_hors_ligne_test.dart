import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ecoshop_client/features/referentiel/data/supabase_referentiel_repository.dart';
import 'package:ecoshop_client/features/referentiel/domain/referentiel_repository.dart';

void main() {
  test('serveur injoignable : ErreurReferentiel HORS_LIGNE (le cache peut prendre le relais)', () async {
    // Port fermé sur la machine : vraie panne de transport, sans Internet.
    final client = SupabaseClient('http://127.0.0.1:9', 'cle-de-test');
    addTearDown(client.dispose);
    final depot = SupabaseReferentielRepository(client);

    await expectLater(
      depot.paysPedagogiques(),
      throwsA(isA<ErreurReferentiel>().having((e) => e.code, 'code', ErreurReferentiel.horsLigne)),
    );
  });
}
