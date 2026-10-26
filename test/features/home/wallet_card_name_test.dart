import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/wallet_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Бош экран ҳамён картаси: фойдаланувчи исми баланс билан бир хил тўқ рангда (эга, 2026-10-26: 3-вариант #171717).
void main() {
  testWidgets('исм — катта ҳарфда, AppColors.onPrimary (#171717), олтин градиент (ShaderMask) йўқ', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: WalletCard(
            balanceAmount: '19 562',
            balanceCurrency: 'сўм',
            lastTxAmount: '—',
            displayName: 'Азиз Каримов',
            dateText: '26.10.2026',
            locationText: 'Гурлан',
          ),
        ),
      ),
    ));
    await t.pump();
    final name = t.widget<Text>(find.byKey(const ValueKey('wallet_display_name')));
    expect(name.data, 'АЗИЗ КАРИМОВ');
    expect(name.style?.color, AppColors.onPrimary);
    expect(AppColors.onPrimary, const Color(0xFF171717));
    expect(find.descendant(of: find.byType(WalletCard), matching: find.byType(ShaderMask)), findsNothing);
  });
}
