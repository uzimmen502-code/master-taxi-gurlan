import 'package:ava_gurlan/core/widgets/app_launch_splash.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Splash креатив майдони (эга 2026-11-28: рекламачи учун аниқ ўлчам). Креатив `BoxFit.contain` билан
/// шу майдонга жойлашади (КЕСИЛМАЙДИ). Майдон = экран − SafeArea (статус/навигация) − 40 dp эн ва
/// ≈150 dp бўй (AVA сарлавҳа, оралиқлар, «Реклама бериш» тугмаси).
/// Бу тест ҳисоботдаги спецификацияни қулфлайди: layout ўзгарса — спецификация ҳам янгиланади.
Future<Size> _creativeBox(WidgetTester t, Size screen, {double top = 0, double bottom = 0}) async {
  t.view.physicalSize = screen;
  t.view.devicePixelRatio = 1;
  t.view.padding = FakeViewPadding(top: top, bottom: bottom);
  addTearDown(t.view.reset);
  await t.pumpWidget(AppLaunchSplash(key: UniqueKey(), child: const SizedBox()));
  final box = t.getSize(find.ancestor(of: find.byKey(AppLaunchSplash.placeholderKey), matching: find.byType(Center)).first);
  await t.pump(AppLaunchSplash.displayDuration);
  return box;
}

void main() {
  test('креатив талаби 3 тилда: 1080×1920, 9:16, 1,5 МБ; лотин янги алифбода', () {
    for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) {
      final s = SplashAdTexts.creativeSpec(l);
      expect(s, contains('1080×1920'));
      expect(s, contains('9:16'));
      expect(s, contains('1,5'));
    }
    expect(SplashAdTexts.creativeSpec('uz_Latn'), isNot(matches(RegExp(r"o'|g'|sh|ch", caseSensitive: false))));
    expect(SplashAdTexts.creativeSpec('xx'), SplashAdTexts.creativeSpec('uz_Cyrl'));
  });

  testWidgets('креатив майдони: 360×800 (статус 24, навигация 48) — эн 320, бўй = 800−72−chrome', (t) async {
    final b = await _creativeBox(t, const Size(360, 800), top: 24, bottom: 48);
    final chrome = 800 - 72 - b.height;
    expect(b.width, 320);
    // Сарлавҳа (AVA 26 pt) + 16 + 16 + тугма 50 + 16 юқори + 20 пастки ҳошия.
    expect(chrome, inInclusiveRange(145, 160));
    // ignore: avoid_print
    print('splash creative box 360x800: ${b.width}x${b.height} chrome=$chrome');
  });

  testWidgets('қисқа (360×640) ва узун (412×915) экранлар, web 1280×720', (t) async {
    for (final s in const [(Size(360, 640), 24.0, 48.0), (Size(412, 915), 32.0, 16.0), (Size(1280, 720), 0.0, 0.0)]) {
      final b = await _creativeBox(t, s.$1, top: s.$2, bottom: s.$3);
      expect(b.width, s.$1.width - 40);
      // ignore: avoid_print
      print('splash creative box ${s.$1.width}x${s.$1.height}: ${b.width}x${b.height} ratio=${(b.width / b.height).toStringAsFixed(3)}');
    }
  });
}
