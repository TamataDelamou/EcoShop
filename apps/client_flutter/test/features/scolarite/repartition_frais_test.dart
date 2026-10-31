import 'package:ecoshop_client/features/scolarite/data/frais_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// REG-39 : répartition automatique des frais en tranches ou en mois.
void main() {
  test('3 tranches égales : la dernière complète à 100 %', () {
    final p = repartitionTranches(3);
    expect(p.map((x) => x.nom), ['Tranche 1', 'Tranche 2', 'Tranche 3']);
    expect(p.map((x) => x.pourcentage), [33.33, 33.33, 33.34]);
  });

  test('9 mois à partir d’octobre : octobre à juin, échéance le 10, année suivante pour janvier', () {
    final p = repartitionMensuelle(premierMois: 10, n: 9, annee: 2026);
    expect(p.first.nom, 'Octobre');
    expect(p.last.nom, 'Juin');
    expect(p.first.dateLimite, DateTime(2026, 10, 10));
    expect(p[3].dateLimite, DateTime(2027, 1, 10));
    expect(p.fold<double>(0, (s, x) => s + x.pourcentage), closeTo(100, 0.001));
  });

  test('montants au franc près : la somme fait exactement le tarif', () {
    final m = montantsParPalier(1000000, partsEgales(3));
    expect(m, [333300, 333300, 333400]);
    expect(m.reduce((a, b) => a + b), 1000000);
  });
}
