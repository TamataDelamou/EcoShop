import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/app_colors.dart';
import 'package:ecoshop_client/main.dart';

void main() {
  group('Charte graphique (AppColors)', () {
    test('couleurs conformes à la charte Innovation & Énergie', () {
      expect(AppColors.fond, const Color(0xFFF8FAFC));
      expect(AppColors.bleuElectrique, const Color(0xFF2563EB));
      expect(AppColors.orangePop, const Color(0xFFFF6B00));
      expect(AppColors.vertMenthe, const Color(0xFF10B981));
      expect(AppColors.dore, const Color(0xFFE1A100));
    });
  });

  testWidgets('EcoShopApp démarre en mode diagnostic sans Supabase', (tester) async {
    await tester.pumpWidget(const EcoShopApp());

    expect(find.text('EcoShop'), findsOneWidget);
    expect(find.textContaining('Supabase'), findsOneWidget);
  });
}
