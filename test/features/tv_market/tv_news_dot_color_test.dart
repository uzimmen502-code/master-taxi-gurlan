import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_market_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга 2026-11-19: «Кун янгиликлари» ўқилмаганлик нуқтаси — ҚИЗИЛ.
void main() {
  Future<void> pump(WidgetTester t, Tab tab) => t.pumpWidget(MaterialApp(
        home: DefaultTabController(
          length: 1,
          child: Scaffold(appBar: AppBar(bottom: TabBar(tabs: [tab]))),
        ),
      ));

  testWidgets('нуқта бор ва ранги қизил (AppColors.error)', (t) async {
    await pump(t, tvFeedTabLabel('Кун янгиликлари', badgeKey: const ValueKey('dot'), showBadge: true));
    final box = t.widget<Container>(find.byKey(const ValueKey('dot')));
    final color = (box.decoration! as BoxDecoration).color!;
    expect(color, AppColors.error);
    // Қизил: R устун, G ва B паст.
    expect(color.r > 0.6 && color.g < 0.35 && color.b < 0.35, isTrue, reason: '$color');
  });

  testWidgets('ўқилмаган йўқ — нуқта йўқ', (t) async {
    await pump(t, tvFeedTabLabel('Кун янгиликлари', badgeKey: const ValueKey('dot')));
    expect(find.byKey(const ValueKey('dot')), findsNothing);
  });
}
