// «Хабарлар» экрани (эга, 2026-11-02): битта рўйхат, филтрлар, суриб ўчириш + «Бекор қилиш»,
// қатор очилганда ўқилган, қидирув, қисман хато, push таб рақами → филтр.
// Матнлар `context.tr` — тестда делегат йўқ, калит кўринади.
import 'dart:async';

import 'package:ava_gurlan/features/chat/widgets/message_bubble.dart';
import 'package:ava_gurlan/features/deal_chat/data/deal_chat_repository.dart';
import 'package:ava_gurlan/features/deal_chat/screens/deal_chat_screen.dart';
import 'package:ava_gurlan/features/profile/inbox/inbox_entries.dart';
import 'package:ava_gurlan/features/profile/inbox/inbox_read_store.dart';
import 'package:ava_gurlan/features/profile/screens/news_hub_screen.dart';
import 'package:ava_gurlan/models/chat_message.dart';
import 'package:ava_gurlan/models/news_item.dart';
import 'package:ava_gurlan/repositories/chat_repository.dart';
import 'package:ava_gurlan/repositories/driver_repository.dart';
import 'package:ava_gurlan/repositories/news_repository.dart';
import 'package:ava_gurlan/repositories/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const uid = '998901234567';

class _News implements NewsRepository {
  final ctrl = StreamController<InboxNewsLists>.broadcast();
  final dismissedCtrl = StreamController<Set<String>>.broadcast();
  final dismissCalls = <List<String>>[];
  int opens = 0;
  bool failDismiss = false;
  DateTime? readAt;

  @override
  Stream<InboxNewsLists> watchInboxNews({
    required String userId,
    String role = 'user',
    int globalLimit = 50,
    int personalLimit = 100,
  }) {
    opens++;
    return ctrl.stream;
  }

  @override
  Stream<Set<String>> watchDismissedIds(String userId) => dismissedCtrl.stream;

  @override
  Future<void> dismissNews(String userId, Iterable<String> newsIds) async {
    if (failDismiss) throw StateError('offline');
    dismissCalls.add(newsIds.toList());
  }

  @override
  Future<({DateTime? news, DateTime? messages, DateTime? orders})> fetchLastReadAt(String userId) async =>
      (news: readAt, messages: readAt, orders: readAt);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Chat implements ChatRepository {
  final ctrl = StreamController<SupportChatMeta>.broadcast();
  @override
  Stream<SupportChatMeta> watchSupportMeta(String chatId) => ctrl.stream;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Driver implements DriverRepository {
  @override
  Stream<Map<String, dynamic>?> watchMyDriverRequest(String phone) => Stream.value(null);
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Deals implements DealChatRepository {
  final ctrl = StreamController<List<DealChat>>.broadcast();
  @override
  Stream<List<DealChat>> watchMyChats(String myUid, {int limit = 50}) => ctrl.stream;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Users implements UserRepository {
  final marked = <String>[];
  @override
  Future<void> markNewsRead(String uid) async => marked.add('news');
  @override
  Future<void> markMessagesRead(String uid) async => marked.add('messages');
  @override
  Future<void> markOrderNewsRead(String uid) async => marked.add('orders');
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

NewsItem _news(String id, DateTime at, {String title = 'Янгилик'}) =>
    NewsItem(id: id, title: title, body: 'матн', createdAt: at);

NewsItem _order(String id, DateTime at) => NewsItem(
    id: id,
    title: 'Қабул қилинди',
    body: 'x',
    createdAt: at,
    source: 'order_status',
    category: 'order',
    orderId: 'o1',
    orderStatus: 'accepted',
    orderType: 'bread',
    targetUserId: uid);

class _Harness {
  final news = _News();
  final chat = _Chat();
  final deals = _Deals();
  final users = _Users();
  final read = InboxReadStore.memory();

  Future<void> pump(WidgetTester t, {int? tab}) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MultiProvider(
      providers: [
        Provider<NewsRepository>.value(value: news),
        Provider<ChatRepository>.value(value: chat),
        Provider<DriverRepository>.value(value: _Driver()),
        Provider<DealChatRepository>.value(value: deals),
        Provider<UserRepository>.value(value: users),
      ],
      child: MaterialApp(home: NewsHubScreen(initialTabIndex: tab, readStore: read)),
    ));
    await t.pump();
    await t.pump();
  }

  Future<void> emit(WidgetTester t, {List<NewsItem> broadcast = const [], List<NewsItem> orders = const []}) async {
    news.ctrl.add(InboxNewsLists(broadcast: broadcast, orders: orders));
    await t.pump();
  }
}

FontWeight? _titleWeight(WidgetTester t, String key, String title) => t
    .widget<Text>(find.descendant(of: find.byKey(ValueKey('inbox-row-$key')), matching: find.text(title)))
    .style
    ?.fontWeight;

void main() {
  final now = DateTime.now();

  setUp(() => SharedPreferences.setMockInitialValues({'user_phone': uid}));

  testWidgets('битта рўйхат: «AVA ёрдам» тепада, буюртма чати алоҳида қатор, сервер белгилари тозаланади',
      (t) async {
    final h = _Harness()..news.readAt = now.subtract(const Duration(hours: 2));
    await h.pump(t);
    await h.emit(t, broadcast: [_news('n1', now.subtract(const Duration(hours: 1)))]);
    h.deals.ctrl.add([
      DealChat(
          id: 'c1',
          members: const [uid, '998907777777'],
          buyerId: uid,
          sellerId: '998907777777',
          productId: 'p',
          productTitle: 'Ун 50 кг',
          lastMessage: 'эртага',
          lastFrom: '998907777777',
          lastAt: now,
          unread: const {uid: 2}),
    ]);
    await t.pump();

    final rows = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('inbox-row-'));
    expect(rows, findsNWidgets(3));
    expect(t.getTopLeft(find.byKey(const ValueKey('inbox-row-support'))).dy,
        lessThan(t.getTopLeft(find.byKey(const ValueKey('inbox-row-deal:c1'))).dy));
    expect(find.text('Ун 50 кг'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-count-deal:c1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-filter-count-chats')), findsOneWidget);
    expect(h.users.marked, containsAll(['news', 'messages', 'orders']));
  });

  testWidgets('ўқилмаган жирний; қатор очилгач оддий (экран қайта очилса ҳам жирний қолмайди)', (t) async {
    final h = _Harness()..news.readAt = now.subtract(const Duration(hours: 2));
    await h.pump(t);
    await h.emit(t, broadcast: [_news('n1', now.subtract(const Duration(hours: 1)), title: 'Янги бўлим')]);
    expect(_titleWeight(t, 'news:n1', 'Янги бўлим'), FontWeight.w700);
    expect(find.byKey(const ValueKey('inbox-dot-news:n1')), findsOneWidget);

    await t.tap(find.text('Янги бўлим'));
    await t.pumpAndSettle();
    expect(find.text('матн'), findsWidgets, reason: 'тафсилот экрани очилди');
    await t.pageBack();
    await t.pumpAndSettle();
    expect(_titleWeight(t, 'news:n1', 'Янги бўлим'), FontWeight.w500);
    expect(h.read.openedAt('news:n1'), isNotNull);
  });

  testWidgets('филтр: «Буюртмалар» фақат буюртмани кўрсатади; push таб 2 → шу филтр', (t) async {
    final h = _Harness();
    await h.pump(t, tab: 2);
    await h.emit(t, broadcast: [_news('n1', now)], orders: [_order('a', now)]);
    expect(find.byKey(const ValueKey('inbox-row-order:o1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-row-news:n1')), findsNothing);
    expect(find.byKey(const ValueKey('inbox-row-support')), findsNothing);
    await t.tap(find.byKey(const ValueKey('inbox-filter-all')));
    await t.pump();
    expect(find.byKey(const ValueKey('inbox-row-news:n1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-row-support')), findsOneWidget);
  });

  testWidgets('суриб ўчириш: дарров йўқолади, «Бекор қилиш» қайтаради, серверга ёзилмайди', (t) async {
    final h = _Harness();
    await h.pump(t);
    await h.emit(t, broadcast: [_news('n1', now)]);
    await t.drag(find.byKey(const ValueKey('inbox-row-news:n1')), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-row-news:n1')), findsNothing);
    await t.tap(find.text('inbox_undo'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-row-news:n1')), findsOneWidget);
    expect(h.news.dismissCalls, isEmpty);
  });

  testWidgets('суриб ўчириш: «Бекор қилиш» босилмаса — серверга (dismissed_news) ёзилади', (t) async {
    final h = _Harness();
    await h.pump(t);
    await h.emit(t, broadcast: [_news('n1', now)]);
    await t.drag(find.byKey(const ValueKey('inbox-row-news:n1')), const Offset(-500, 0));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(h.news.dismissCalls, [
      ['n1']
    ]);
    expect(find.byKey(const ValueKey('inbox-row-news:n1')), findsNothing);
  });

  testWidgets('ёзилмаса (офлайн) — қатор қайтади (жимгина йўқолмайди)', (t) async {
    final h = _Harness()..news.failDismiss = true;
    await h.pump(t);
    await h.emit(t, broadcast: [_news('n1', now)]);
    await t.drag(find.byKey(const ValueKey('inbox-row-news:n1')), const Offset(-500, 0));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-row-news:n1')), findsOneWidget);
  });

  testWidgets('«AVA ёрдам» суриб — қатор ЎЗИ қолади, фақат тарих тозаланади', (t) async {
    final h = _Harness();
    await h.pump(t);
    await h.emit(t);
    h.chat.ctrl.add(SupportChatMeta(lastMessage: 'Ҳал бўлди', updatedAt: now.subtract(const Duration(minutes: 1)), lastFromAdmin: true));
    await t.pump();
    expect(find.text('Ҳал бўлди'), findsOneWidget);
    await t.drag(find.byKey(const ValueKey('inbox-row-support')), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-row-support')), findsOneWidget);
    expect(find.text('inbox_support_hint'), findsOneWidget);
    expect(find.text('inbox_history_cleared'), findsOneWidget);
  });

  testWidgets('қидирув: сарлавҳа ва матн бўйича; топилмаса — бўш ҳолат', (t) async {
    final h = _Harness();
    await h.pump(t);
    await h.emit(t, broadcast: [_news('n1', now, title: 'Улгуржи бозор'), _news('n2', now, title: 'Такси')]);
    await t.tap(find.byKey(const ValueKey('inbox-search')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('inbox-search-field')), 'улгур');
    await t.pump();
    expect(find.byKey(const ValueKey('inbox-row-news:n1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-row-news:n2')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('inbox-search-field')), 'йўқ-нарса');
    await t.pump();
    expect(find.text('inbox_search_empty'), findsOneWidget);
  });

  testWidgets('хабарлар юкланмади — огоҳлантириш ва «Қайта уриниш»; бошқа қаторлар кўринади', (t) async {
    final h = _Harness();
    await h.pump(t);
    h.news.ctrl.addError(StateError('permission'));
    await t.pump();
    expect(find.byKey(const ValueKey('inbox-error-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-row-support')), findsOneWidget);
    final before = h.news.opens;
    await t.tap(find.text('inbox_retry'));
    await t.pump(const Duration(seconds: 1));
    expect(h.news.opens, before + 1);
  });

  testWidgets('«Ҳаммасини ўқилган қилиш» — жирнийлар оддий бўлади', (t) async {
    final h = _Harness()..news.readAt = now.subtract(const Duration(hours: 2));
    await h.pump(t);
    await h.emit(t, broadcast: [_news('n1', now.subtract(const Duration(hours: 1)), title: 'А')]);
    expect(_titleWeight(t, 'news:n1', 'А'), FontWeight.w700);
    await t.tap(find.byKey(const ValueKey('inbox-mark-all')));
    await t.pump();
    expect(_titleWeight(t, 'news:n1', 'А'), FontWeight.w500);
  });

  group('чат', () {
    testWidgets('пуфакча: вақт, меники учун ✓/✓✓, кенглик чекланган', (t) async {
      await t.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final msg = ChatMessage(id: 'm', text: 'салом ' * 40, createdAt: DateTime.utc(2026, 11, 5, 9, 35));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            MessageBubble(message: msg, isMine: true, read: true),
            MessageBubble(message: msg, isMine: true, read: false),
            MessageBubble(message: msg, isMine: false),
          ]),
        ),
      ));
      expect(find.text('14:35'), findsNWidgets(3));
      expect(find.byKey(const ValueKey('bubble-read')), findsOneWidget);
      expect(find.byKey(const ValueKey('bubble-sent')), findsOneWidget);
      expect(t.getSize(find.descendant(of: find.byType(MessageBubble).first, matching: find.byType(Container)).first).width,
          lessThanOrEqualTo(400 * 0.78 + 0.5));
    });

    test('кун ажратгичлари: ҳар янги кун олдидан битта', () {
      final rows = withDaySeparators<DateTime?>([
        DateTime.utc(2026, 11, 4, 10),
        DateTime.utc(2026, 11, 4, 12),
        null,
        DateTime.utc(2026, 11, 5, 10),
      ], (x) => x);
      expect(rows.whereType<ChatDay>().length, 2);
      expect(rows.first, isA<ChatDay>());
      expect(rows[4], isA<ChatDay>());
    });

    test('ўқилди белгиси: қарши томоннинг unread сони — меники охирги шунча хабар ўқилмаган', () {
      const me = uid;
      const other = '998907777777';
      final msgs = [
        const DealMessage(id: '1', from: me, text: 'a'),
        const DealMessage(id: '2', from: other, text: 'b'),
        const DealMessage(id: '3', from: me, text: 'c'),
        const DealMessage(id: '4', from: me, text: 'd'),
      ];
      DealChat chat(int otherUnread) => DealChat(
          id: 'c', members: const [me, other], buyerId: me, sellerId: other, productId: 'p',
          unread: {other: otherUnread});
      expect(dealReadMessageIds(msgs, myUid: me, chat: chat(0)), {'1', '3', '4'});
      expect(dealReadMessageIds(msgs, myUid: me, chat: chat(2)), {'1'});
      expect(dealReadMessageIds(msgs, myUid: me, chat: chat(9)), <String>{});
      expect(dealReadMessageIds(msgs, myUid: me, chat: null), isNull);
    });
  });

  test('InboxFilter тартиби ўзгармасин (push таб рақамлари)', () {
    expect(InboxFilter.values.map((f) => f.name), ['all', 'chats', 'orders', 'news']);
  });
}
