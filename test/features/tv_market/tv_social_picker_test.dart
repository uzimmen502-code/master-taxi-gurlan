import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_publish_rules.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_social.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_social_picker.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_social_withdraw_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Менинг каналим» (сотувчининг ўз Telegram канали, 2026-10-25) — жойлаш экранидаги танлов ва розилик.
/// Локализация делегати уланмаган — `context.tr` калитнинг ўзини қайтаради.

class _Host extends StatefulWidget {
  const _Host({required this.channel});
  final String channel;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final selected = <String>{};
  bool consent = false;
  @override
  Widget build(BuildContext context) => TvSocialPicker(
        selected: selected,
        sellerChannel: widget.channel,
        consent: consent,
        onToggle: (id, on) => setState(() {
          if (on) {
            selected.add(id);
            consent = false;
          } else {
            selected.remove(id);
          }
        }),
        onConsent: (v) => setState(() => consent = v),
      );
}

Future<_HostState> _pump(WidgetTester tester, String channel) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: _Host(channel: channel)))));
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  group('TvPublishRules — «Менинг каналим»', () {
    test('faqat kanal ulangan va tovar/xizmat bo\'lsa taklif qilinadi', () {
      expect(TvPublishRules.sellerChannelOffered(category: 'product', channelConnected: true), true);
      expect(TvPublishRules.sellerChannelOffered(category: 'service', channelConnected: true), true);
      expect(TvPublishRules.sellerChannelOffered(category: 'news', channelConnected: true), false);
      expect(TvPublishRules.sellerChannelOffered(category: 'ad', channelConnected: true), false);
      expect(TvPublishRules.sellerChannelOffered(category: 'product', channelConnected: false), false);
    });
    test('taklif qilinmasa (yangilikka o\'tdi) — tarmoqlardan tushadi; boshqalar qoladi', () {
      final picked = {TvSocial.telegram, TvSocial.sellerTelegram};
      expect(TvPublishRules.effectiveSocialNetworks(picked, sellerChannelOffered: true), picked);
      expect(TvPublishRules.effectiveSocialNetworks(picked, sellerChannelOffered: false), {TvSocial.telegram});
    });
    test('rozilik versiyasi: kanal bilan — 2 (server qoidasi), kanalsiz — 1 (eski bilan bir xil)', () {
      expect(TvPublishRules.socialConsentVersion({TvSocial.sellerTelegram}), 2);
      expect(TvPublishRules.socialConsentVersion({TvSocial.telegram, TvSocial.sellerTelegram}), 2);
      expect(TvPublishRules.socialConsentVersion({TvSocial.instagram}), TvSocial.consentVersion);
    });
  });

  group('TvClip / withdraw — yangi qiymat yo\'qolmaydi', () {
    TvClip clip(List<String> nets, {Map<String, dynamic> post = const {}}) => TvClip.fromMap('c1', {
          'videoUrl': '', 'posterUrl': '', 'title': 'Non', 'price': 0, 'ownerPhone': '998900000000',
          'category': 'product', 'socialConsent': true, 'socialNetworks': nets, 'socialPost': post,
        });
    test('o\'qishda seller_telegram saqlanadi, tiktok tashlanadi; qaytarib olish kartasi uni ko\'rsatadi', () {
      final c = clip(['seller_telegram', 'tiktok', 'telegram']);
      expect(c.socialNetworks, ['seller_telegram', 'telegram']);
      expect(tvSocialTargets(c), ['seller_telegram', 'telegram']);
      expect(TvSocial.parse(['seller_telegram', 'x']), ['seller_telegram']);
    });
    test('joylanganlar ro\'yxatida kanal ham bor', () {
      final c = clip(['seller_telegram'], post: {
        'networks': {'seller_telegram': {'status': 'posted'}},
      });
      expect(tvSocialPostedNetworks(c), ['seller_telegram']);
    });
  });

  group('TvSocialPicker', () {
    testWidgets('kanal ulanmagan — «Менинг каналим» chipi yo\'q (eski ko\'rinish)', (tester) async {
      await _pump(tester, '');
      expect(find.byKey(const ValueKey('tv_social_seller_telegram')), findsNothing);
      expect(find.byType(FilterChip), findsNWidgets(4));
      expect(find.byKey(const ValueKey('tv_social_consent')), findsNothing);
    });

    testWidgets('kanal tanlansa — rozilik matni kanalni NOMI bilan aytadi; belgilash ishlaydi', (tester) async {
      final host = await _pump(tester, '@non_shop');
      expect(find.byType(FilterChip), findsNWidgets(5));
      await tester.tap(find.byKey(const ValueKey('tv_social_seller_telegram')));
      await tester.pump();
      expect(host.selected, {TvSocial.sellerTelegram});
      final tile = find.byKey(const ValueKey('tv_social_consent'));
      expect(tile, findsOneWidget);
      // Kalit qaytadi (delegatsiz) — kanal nomi o'rinbosarga qo'yilmaydi; shuning uchun matn kaliti tekshiriladi.
      expect(find.textContaining('tv_social_consent_check_own'), findsOneWidget);
      expect(find.textContaining('tv_social_consent_check\n'), findsNothing, reason: 'AVA tarmoqlari tanlanmagan');
      await tester.tap(tile);
      await tester.pump();
      expect(host.consent, true);
    });

    testWidgets('AVA tarmog\'i + kanal — bitta belgi, ikkala jumla; yangi tarmoq qo\'shilsa belgi qayta so\'raladi', (tester) async {
      final host = await _pump(tester, '@non_shop');
      await tester.tap(find.text('tv_social_telegram'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tv_social_consent')));
      await tester.pump();
      expect(host.consent, true);
      await tester.tap(find.byKey(const ValueKey('tv_social_seller_telegram')));
      await tester.pump();
      expect(host.consent, false);
      expect(find.text('tv_social_consent_check\ntv_social_consent_check_own'), findsOneWidget);
    });
  });
}
