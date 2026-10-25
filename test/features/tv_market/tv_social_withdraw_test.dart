import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_social_withdraw_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 7-босқич давоми (2026-10-25): эга AVA саҳифаларига жойлаш розилигини қайтариб олади.
TvClip _clip({
  String category = 'product',
  bool consent = true,
  List<String> nets = const ['telegram'],
  Map<String, dynamic> post = const {},
}) =>
    TvClip(
      id: 'c1', videoUrl: '', posterUrl: '', title: 'Нон', price: 0, districtId: '', districtLabel: '',
      ownerPhone: '998900000000', ownerName: '', category: category,
      socialConsent: consent, socialNetworks: nets, socialPost: post,
    );

Future<void> _pump(WidgetTester tester, TvClip clip, Future<void> Function() onWithdraw) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: TvSocialWithdrawCard(clip: clip, onWithdraw: onWithdraw)),
  ));
}

void main() {
  group('tvSocialTargets — сервер қоидаси билан бир хил', () {
    test('танланган тармоқлар фақат розилик билан', () {
      expect(tvSocialTargets(_clip()), ['telegram']);
      expect(tvSocialTargets(_clip(consent: false)), isEmpty);
    });
    test('эски клип: тармоқсиз + розилик — барча тармоқ', () {
      expect(tvSocialTargets(_clip(nets: const [])), ['instagram', 'facebook', 'youtube', 'telegram']);
    });
    test('пуллик реклама — қайтариб олиш йўқ', () {
      expect(tvSocialTargets(_clip(category: 'ad')), isEmpty);
    });
    test('жойланганлари — фақат status posted', () {
      final c = _clip(nets: const ['instagram', 'telegram'], post: {
        'networks': {'instagram': {'status': 'posted'}, 'telegram': {'status': 'error'}},
      });
      expect(tvSocialPostedNetworks(c), ['instagram']);
    });
  });

  group('TvSocialWithdrawCard', () {
    testWidgets('тасдиқласа — чақирилади, карточка йўқолади', (tester) async {
      var calls = 0;
      await _pump(tester, _clip(), () async => calls++);
      expect(find.byKey(const ValueKey('tv_social_withdraw_card')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tv_social_withdraw')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tv_social_withdraw_yes')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byKey(const ValueKey('tv_social_withdraw_card')), findsNothing);
    });

    testWidgets('бекор қилса — чақирилмайди', (tester) async {
      var calls = 0;
      await _pump(tester, _clip(), () async => calls++);
      await tester.tap(find.byKey(const ValueKey('tv_social_withdraw')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byKey(const ValueKey('tv_social_withdraw_card')), findsOneWidget);
    });

    testWidgets('хато — карточка қолади, тугма яна босилади', (tester) async {
      await _pump(tester, _clip(), () async => throw Exception('offline'));
      await tester.tap(find.byKey(const ValueKey('tv_social_withdraw')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tv_social_withdraw_yes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tv_social_withdraw_card')), findsOneWidget);
      final btn = tester.widget<TextButton>(find.byKey(const ValueKey('tv_social_withdraw')));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('розилик йўқ ёки реклама — карточка чиқмайди', (tester) async {
      await _pump(tester, _clip(consent: false), () async {});
      expect(find.byKey(const ValueKey('tv_social_withdraw_card')), findsNothing);
      await _pump(tester, _clip(category: 'ad'), () async {});
      expect(find.byKey(const ValueKey('tv_social_withdraw_card')), findsNothing);
    });
  });
}
