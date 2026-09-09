import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/app_palettes.dart';
import 'package:ecoshop_client/main.dart';

void main() {
  group('Charte graphique (AppPalettes)', () {
    test('francophone_cfa clair conforme à la charte Innovation & Énergie', () {
      final palette = AppPalettes.francophoneCfaLight;
      expect(palette.fond, const Color(0xFFF8FAFC));
      expect(palette.primaire, const Color(0xFF2563EB));
      expect(palette.accent, const Color(0xFFFF6B00));
      expect(palette.succes, const Color(0xFF10B981));
      expect(palette.premium, const Color(0xFFE1A100));
    });
  });

  testWidgets('EcoShopApp démarre en mode diagnostic sans Supabase', (tester) async {
    await tester.pumpWidget(const EcoShopApp());

    expect(find.text('EcoShop'), findsOneWidget);
    expect(find.textContaining('Supabase'), findsOneWidget);
  });
}
