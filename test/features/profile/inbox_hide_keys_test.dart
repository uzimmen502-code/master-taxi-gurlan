import 'package:ava_gurlan/features/profile/inbox_hide_keys.dart';
import 'package:ava_gurlan/features/profile/widgets/news_delete_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Хабарлар»: ҳайдовчи аризаси ва «Админ билан чат»да ўчириш (эга, 2026-10-26: «кирит»).
void main() {
  group('ҳайдовчи аризаси калити', () {
    test('ҳолат ва вақтга боғлиқ — ҳолат ўзгарса бошқа калит (карта яна чиқади)', () {
      final t = Timestamp.fromMillisecondsSinceEpoch(1000);
      final pending = InboxHideKeys.driverRequest({'status': 'pending', 'createdAt': t});
      final approved = InboxHideKeys.driverRequest({'status': 'approved', 'updatedAt': Timestamp.fromMillisecondsSinceEpoch(2000)});
      expect(pending, 'driver_req_pending_1000');
      expect(approved, isNot(pending));
    });

    test('вақт йўқ — барқарор калит (ҳар чизишда ўзгармайди)', () {
      expect(InboxHideKeys.driverRequest({'status': 'pending'}), InboxHideKeys.driverRequest({'status': 'pending'}));
      expect(InboxHideKeys.driverRequest({}), 'driver_req_pending_0');
    });
  });

  group('админ чати тарихини тозалаш', () {
    test('энг охирги тозалаш вақти олинади, бошқа белгилар эътиборсиз', () {
      final a = InboxHideKeys.supportChatCleared(DateTime.fromMillisecondsSinceEpoch(5000));
      final b = InboxHideKeys.supportChatCleared(DateTime.fromMillisecondsSinceEpoch(9000));
      expect(InboxHideKeys.supportChatClearedAt({'news1', a, b, 'driver_req_pending_0'}), DateTime.fromMillisecondsSinceEpoch(9000));
      expect(InboxHideKeys.supportChatClearedAt({'news1'}), isNull);
    });

    test('тозалашдан олдинги хабар яширилади, кейингиси ва вақти номаълуми кўринади', () {
      final cleared = DateTime(2026, 10, 26, 13);
      expect(InboxHideKeys.visibleAfterClear(DateTime(2026, 10, 26, 12), cleared), isFalse);
      expect(InboxHideKeys.visibleAfterClear(DateTime(2026, 10, 26, 14), cleared), isTrue);
      expect(InboxHideKeys.visibleAfterClear(null, cleared), isTrue, reason: 'ҳозиргина юборилган (сервер вақти кутилмоқда)');
      expect(InboxHideKeys.visibleAfterClear(DateTime(2020), null), isTrue);
    });
  });

  testWidgets('NewsDeleteButton: ўз тасдиқ матнлари (чат — «тарих тозаланади, қатор қолади»)', (t) async {
    var called = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NewsDeleteButton(
          titleKey: 'chat_clear_title',
          bodyKey: 'chat_clear_body',
          doneKey: 'chat_cleared_snack',
          onDelete: () async => called = true,
        ),
      ),
    ));
    await t.tap(find.byKey(const ValueKey('news-delete')));
    await t.pumpAndSettle();
    expect(find.text('chat_clear_title'), findsOneWidget);
    expect(find.text('chat_clear_body'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('news-delete-confirm')));
    await t.pumpAndSettle();
    expect(called, isTrue);
    expect(find.text('chat_cleared_snack'), findsOneWidget);
  });
}
