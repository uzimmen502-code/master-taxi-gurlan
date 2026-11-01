// «Буюртма ёзиш» тугмаси (эга қарори 2026-11-01): «Қўнғироқ қилиш» билан БИР қаторда, сутли ранг;
// ўз маҳсулотида йўқ; чат очилаётганда қайта босилмайди; тор экранда ҳам сиғади; 3 тилда матн бор.
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_detail_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

Widget _host(Widget child, {JsonL10nDelegate? d, double textScale = 1.0}) => l10nApp(
      delegate: d,
      textScale: textScale,
      home: Scaffold(
        bottomNavigationBar: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

void main() {
  final d = JsonL10nDelegate();
  const writeKey = ValueKey('wholesale-write-order');
  const callKey = ValueKey('wholesale-call');

  testWidgets('бегона маҳсулот: иккала тугма бир қаторда, ҳақиқий матн, босилса чақирилади', (tester) async {
    var calls = 0, writes = 0;
    await tester.pumpWidget(_host(
      WholesaleDetailActions(onCall: () => calls++, onWriteOrder: () => writes++),
      d: d,
    ));
    expect(find.byKey(callKey), findsOneWidget);
    expect(find.byKey(writeKey), findsOneWidget);
    expect(find.text(d.tr('deal_chat_write_order')), findsOneWidget);
    expect(find.text(d.tr('wholesale_call')), findsOneWidget);
    // Бир қатор: марказлари бир баландликда, «Буюртма ёзиш» ўнгда.
    final call = tester.getCenter(find.byKey(callKey));
    final write = tester.getCenter(find.byKey(writeKey));
    expect(call.dy, write.dy);
    expect(write.dx, greaterThan(call.dx));
    // Ранглар: «Буюртма ёзиш» — тўлиқ сутли (асосий), қўнғироқ — сутли чизиқли.
    final w = tester.widget<FilledButton>(find.byKey(writeKey));
    expect(w.style!.backgroundColor!.resolve({}), kWholesaleMilk);
    expect(w.style!.foregroundColor!.resolve({}), kWholesaleMilkInk);
    expect(find.byKey(callKey).evaluate().single.widget, isA<OutlinedButton>());

    await tester.tap(find.byKey(writeKey));
    await tester.tap(find.byKey(callKey));
    expect([writes, calls], [1, 1]);
  });

  testWidgets('ўз маҳсулоти: «Буюртма ёзиш» йўқ, қўнғироқ тўлиқ сутли (аввалги кўриниш)', (tester) async {
    await tester.pumpWidget(_host(
      WholesaleDetailActions(onCall: () {}, onWriteOrder: () {}, showWriteOrder: false),
      d: d,
    ));
    expect(find.byKey(writeKey), findsNothing);
    expect(find.text(d.tr('deal_chat_write_order')), findsNothing);
    final c = tester.widget<FilledButton>(find.byKey(callKey));
    expect(c.style!.backgroundColor!.resolve({}), kWholesaleMilk);
  });

  testWidgets('чат очилмоқда (busy): тугма ўчиқ, босиш ҳеч нарса қилмайди', (tester) async {
    var writes = 0;
    await tester.pumpWidget(_host(
      WholesaleDetailActions(onCall: () {}, onWriteOrder: () => writes++, writeBusy: true),
      d: d,
    ));
    expect(tester.widget<FilledButton>(find.byKey(writeKey)).onPressed, isNull);
    await tester.tap(find.byKey(writeKey));
    expect(writes, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('тор экран (320 dp) ва катта шрифт (1.3): тошиш хатоси йўқ', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      await tester.pumpWidget(_host(
        WholesaleDetailActions(onCall: () {}, onWriteOrder: () {}),
        d: JsonL10nDelegate(lang),
        textScale: 1.3,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: lang);
    }
  });

  test('кўриниш қоидаси: ўз эълони (9/12 хонали ҳам) — йўқ; бегона/меҳмон — бор; сотувчисиз — йўқ', () {
    expect(wholesaleShowWriteOrder(myUid: '998901234567', sellerId: '998901234567'), isFalse);
    expect(wholesaleShowWriteOrder(myUid: '998901234567', sellerId: '901234567'), isFalse);
    expect(wholesaleShowWriteOrder(myUid: '998901234567', sellerId: '+998 90 123 45 67'), isFalse);
    expect(wholesaleShowWriteOrder(myUid: '998901234568', sellerId: '998901234567'), isTrue);
    expect(wholesaleShowWriteOrder(myUid: '', sellerId: '998901234567'), isTrue);
    expect(wholesaleShowWriteOrder(myUid: '998901234567', sellerId: ''), isFalse);
  });

  test('3 тилда калитлар бор ва бўш эмас', () {
    const keys = [
      'deal_chat_write_order',
      'deal_chat_with_seller',
      'deal_chat_with_buyer',
      'deal_chat_hint',
      'deal_chat_send',
      'deal_chat_empty',
      'deal_chat_load_failed',
      'deal_chat_open_failed',
      'deal_chat_send_failed',
      'deal_chat_text_invalid',
      'deal_chat_product_unavailable',
      'deal_chat_own_product',
      'deal_chat_login_required',
      'deal_chat_login_cta',
      'deal_chat_role_seller',
      'deal_chat_role_buyer',
      'deal_chat_you',
      'deal_chats_title',
      'deal_chats_subtitle',
      'deal_chats_unread',
      'deal_chats_empty',
    ];
    for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      final m = loadLang(lang);
      for (final k in keys) {
        expect(m[k]?.trim().isNotEmpty, isTrue, reason: '$lang:$k');
      }
      expect(m['deal_chats_unread'], contains('{n}'), reason: lang);
    }
  });
}
