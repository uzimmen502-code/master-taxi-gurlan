// «Хабарлар» битта рўйхат (эга, 2026-11-02): вақт формати, ўқилганлик, қаторлар, филтр/қидирув.
import 'package:ava_gurlan/features/deal_chat/data/deal_chat_repository.dart';
import 'package:ava_gurlan/features/profile/inbox/inbox_entries.dart';
import 'package:ava_gurlan/features/profile/inbox/inbox_read_store.dart';
import 'package:ava_gurlan/features/profile/inbox/inbox_time.dart';
import 'package:ava_gurlan/features/profile/inbox_hide_keys.dart';
import 'package:ava_gurlan/models/news_item.dart';
import 'package:ava_gurlan/repositories/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const uid = '998901234567';
String tr(String k) => k;

NewsItem news(String id, DateTime at, {String category = 'info', String title = 'T', String body = 'B'}) =>
    NewsItem(id: id, title: title, body: body, createdAt: at, category: category);

NewsItem dialog(String id, DateTime at, {String source = 'ad_moderation', String title = 'Эълон'}) => NewsItem(
    id: id, title: title, body: 'b', createdAt: at, source: source, category: 'info', targetUserId: uid, submissionId: 's1');

NewsItem order(String id, String orderId, DateTime at, {String status = 'accepted', String title = ''}) => NewsItem(
    id: id,
    title: title,
    body: 'x',
    createdAt: at,
    source: 'order_status',
    category: 'order',
    orderId: orderId,
    orderStatus: status,
    orderType: 'bread',
    targetUserId: uid);

DealChat deal(String id, DateTime at, {int unread = 0, String lastFrom = '998907777777'}) => DealChat(
      id: id,
      members: const [uid, '998907777777'],
      buyerId: uid,
      sellerId: '998907777777',
      productId: 'p',
      productTitle: 'Ун 50 кг',
      lastMessage: 'салом',
      lastFrom: lastFrom,
      lastAt: at,
      unread: {uid: unread},
    );

void main() {
  // 2026-11-05 12:00 Тошкент = 07:00Z (чоршанба).
  final now = DateTime.utc(2026, 11, 5, 7);

  group('inbox_time', () {
    const wd = ['Д', 'С', 'Ч', 'П', 'Ж', 'Ш', 'Я'];
    String row(DateTime t) => inboxRowTime(t, now: now, yesterday: 'Кеча', weekdays: wd);

    test('бугун → соат (Тошкент), кеча → «Кеча», ҳафта ичи → ҳафта куни, эски → сана', () {
      expect(row(DateTime.utc(2026, 11, 5, 9, 35)), '14:35');
      expect(row(DateTime.utc(2026, 11, 4, 9)), 'Кеча');
      expect(row(DateTime.utc(2026, 11, 2, 9)), 'Д', reason: '2026-11-02 — душанба');
      expect(row(DateTime.utc(2026, 10, 20, 9)), '20.10.26');
    });

    test('ярим тун чегараси Тошкент бўйича: 19:30Z = эртаси 00:30', () {
      expect(row(DateTime.utc(2026, 11, 4, 19, 30)), '00:30');
      expect(row(DateTime.utc(2026, 11, 4, 18, 59)), 'Кеча');
    });

    test('келажак (соат фарқи) — бугун деб', () {
      expect(row(DateTime.utc(2026, 11, 5, 8)), '13:00');
    });

    test('кун ажратгичи', () {
      String day(DateTime t) => inboxDayLabel(t, now: now, today: 'Бугун', yesterday: 'Кеча');
      expect(day(DateTime.utc(2026, 11, 5, 1)), 'Бугун');
      expect(day(DateTime.utc(2026, 11, 4, 1)), 'Кеча');
      expect(day(DateTime.utc(2026, 10, 31, 1)), '31.10.2026');
      expect(inboxSameDay(DateTime.utc(2026, 11, 4, 19, 30), DateTime.utc(2026, 11, 5, 18)), isTrue);
    });
  });

  group('InboxReadStore', () {
    test('baseline йўқ — ҳеч нарса янги эмас; бор — ундан кейингиси янги, очилгани эмас', () async {
      final s = InboxReadStore.memory();
      expect(s.isUnread(feed: 'news', key: 'k', latest: now), isFalse);
      await s.ensureBaseline('news', now.subtract(const Duration(hours: 1)), fallback: now);
      expect(s.isUnread(feed: 'news', key: 'k', latest: now), isTrue);
      expect(s.isUnread(feed: 'news', key: 'k', latest: now.subtract(const Duration(hours: 2))), isFalse);
      await s.markOpened('k', at: now);
      expect(s.isUnread(feed: 'news', key: 'k', latest: now), isFalse);
      // Очилгандан КЕЙИН янги хабар — яна жирний.
      expect(s.isUnread(feed: 'news', key: 'k', latest: now.add(const Duration(minutes: 1))), isTrue);
    });

    test('ensureBaseline мавжудини ўзгартирмайди (экранни ёпиб-очиш ўқилган қилмайди)', () async {
      final s = InboxReadStore.memory();
      final b = now.subtract(const Duration(days: 1));
      await s.ensureBaseline('orders', b, fallback: now);
      await s.ensureBaseline('orders', now, fallback: now);
      expect(s.baseline('orders')!.isAtSameMomentAs(b), isTrue);
    });

    test('markAllRead — барча бўлим, очилганлар тозаланади', () async {
      final s = InboxReadStore.memory();
      await s.ensureBaseline('news', now.subtract(const Duration(days: 1)), fallback: now);
      await s.markAllRead(InboxFeed.all, at: now);
      expect(s.isUnread(feed: 'news', key: 'x', latest: now.subtract(const Duration(seconds: 1))), isFalse);
      expect(s.hasBaseline('messages'), isTrue);
    });

    test('қурилмада сақланади ва қайта юкланади; 90 кундан эскиси тозаланади', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await InboxReadStore.load(now: now);
      await s.ensureBaseline('news', now, fallback: now);
      await s.markOpened('new', at: now);
      await s.markOpened('old', at: now.subtract(const Duration(days: 100)));
      final again = await InboxReadStore.load(now: now);
      expect(again.baseline('news')!.isAtSameMomentAs(now), isTrue);
      expect(again.openedAt('new'), isNotNull);
      expect(again.openedAt('old'), isNull);
    });

    test('бузилган JSON — бўш ҳолат, хато йўқ', () async {
      SharedPreferences.setMockInitialValues({InboxReadStore.openedKey: '{bad', InboxReadStore.baselineKey: '[]'});
      final s = await InboxReadStore.load(now: now);
      expect(s.hasBaseline('news'), isFalse);
    });
  });

  group('buildInboxEntries', () {
    late InboxReadStore read;
    setUp(() async {
      read = InboxReadStore.memory();
      for (final f in InboxFeed.all) {
        await read.ensureBaseline(f, now.subtract(const Duration(hours: 3)), fallback: now);
      }
    });

    List<InboxEntry> build(InboxData d) => buildInboxEntries(d, uid: uid, read: read, tr: tr);

    test('«AVA ёрдам» доим биринчи (хабарсиз ҳам), қолгани вақт бўйича', () {
      final e = build(InboxData(
        broadcast: [news('n1', now.subtract(const Duration(hours: 5)))],
        deals: [deal('d1', now.subtract(const Duration(minutes: 5)))],
        orders: [order('o1a', 'o1', now.subtract(const Duration(hours: 1)))],
      ));
      expect(e.map((x) => x.kind).toList(),
          [InboxKind.support, InboxKind.deal, InboxKind.order, InboxKind.news]);
      expect(e.first.pinned, isTrue);
      expect(e.first.preview, 'inbox_support_hint');
      expect(e.first.time, isNull);
    });

    test('support: охирги хабар ва ўқилмаган (админдан); меники — «Сиз:» билан', () {
      var e = build(InboxData(
          support: SupportChatMeta(lastMessage: 'Ҳал бўлди', updatedAt: now, lastFromAdmin: true)));
      expect(e.first.preview, 'Ҳал бўлди');
      expect(e.first.unreadCount, 1);
      e = build(InboxData(support: SupportChatMeta(lastMessage: 'Салом', updatedAt: now)));
      expect(e.first.preview, 'deal_chat_you Салом');
      expect(e.first.unreadCount, 0);
    });

    test('support: тарих тозалангандан кейин — эслатма матни, белги йўқ', () {
      final cleared = InboxHideKeys.supportChatCleared(now.add(const Duration(minutes: 1)));
      final e = build(InboxData(
        support: SupportChatMeta(lastMessage: 'эски', updatedAt: now, lastFromAdmin: true),
        hidden: {cleared},
      ));
      expect(e.first.preview, 'inbox_support_hint');
      expect(e.first.unreadCount, 0);
    });

    test('буюртма чатлари — ҳар бири алоҳида қатор, сон ва қарши томон', () {
      final e = build(InboxData(deals: [
        deal('a', now, unread: 3),
        deal('b', now.subtract(const Duration(hours: 1)), lastFrom: uid),
      ]));
      final deals = e.where((x) => x.kind == InboxKind.deal).toList();
      expect(deals.length, 2);
      expect(deals[0].unreadCount, 3);
      expect(deals[0].preview, 'deal_chat_role_seller: салом');
      expect(deals[1].preview, 'deal_chat_you салом');
      expect(deals[1].canDismiss, isFalse, reason: 'серверда ўчириш йўқ');
    });

    test('буюртма чати: сотувчи кўрганда қарши томон — «Харидор» (эски DealChatTile текшируви)', () {
      const buyer = '998905555555';
      final c = DealChat(
          id: 's',
          members: const [uid, buyer],
          buyerId: buyer,
          sellerId: uid,
          productId: 'p',
          productTitle: 'Ун',
          lastMessage: 'бор',
          lastFrom: buyer,
          lastAt: now,
          unread: const {uid: 3});
      final e = build(InboxData(deals: [c])).firstWhere((x) => x.kind == InboxKind.deal);
      expect(e.preview, 'deal_chat_role_buyer: бор');
      expect(e.unreadCount, 3);
    });

    group('объект номи (sellerName, S3 2026-11-03)', () {
      const seller = '998907777777';
      DealChat c({String source = 'shop_item', String title = 'Ун 50 кг', String sellerName = '', String sellerId = seller,
              String buyerId = uid, String lastFrom = seller}) =>
          DealChat(
            id: 'x',
            members: const [uid, seller],
            buyerId: buyerId,
            sellerId: sellerId,
            productId: 'p',
            source: source,
            productTitle: title,
            sellerName: sellerName,
            lastMessage: 'бор',
            lastFrom: lastFrom,
            lastAt: now,
          );
      InboxEntry row(DealChat d) => build(InboxData(deals: [d])).firstWhere((x) => x.kind == InboxKind.deal);

      test('харидорга: маҳсулот чатида сотувчи хабари — объект номи билан, сарлавҳа — маҳсулот', () {
        final e = row(c(sellerName: 'Бахор дўкони'));
        expect(e.title, 'Ун 50 кг');
        expect(e.preview, 'Бахор дўкони: бор');
        expect(e.category, '');
      });

      test('sellerName йўқ (эски чат) — «Сотувчи»; меники — «Сиз»; сотувчига — «Харидор» (объект номи эмас)', () {
        expect(row(c()).preview, 'deal_chat_role_seller: бор');
        expect(row(c(sellerName: 'Бахор', lastFrom: uid)).preview, 'deal_chat_you бор');
        const other = '998905555555';
        final mineShop = row(c(sellerName: 'Бахор', sellerId: uid, buyerId: other, lastFrom: other));
        expect(mineShop.preview, 'deal_chat_role_buyer: бор');
      });

      test('объект чати: сарлавҳа = объект номи, такрорланмайди («Сотувчи:»), белги — дўкон', () {
        final e = row(c(source: 'business', title: 'Гулбаҳор салони', sellerName: 'Гулбаҳор салони'));
        expect(e.title, 'Гулбаҳор салони');
        expect(e.preview, 'deal_chat_role_seller: бор');
        expect(e.category, 'business');
      });
    });

    test('ўқилмаган: baseline дан кейингиси жирний, очилгандан кейин оддий', () async {
      final fresh = now.subtract(const Duration(hours: 1));
      final old = now.subtract(const Duration(hours: 5));
      var e = build(InboxData(broadcast: [news('n1', fresh), news('n2', old)]));
      expect(e.firstWhere((x) => x.key == 'news:n1').isBold, isTrue);
      expect(e.firstWhere((x) => x.key == 'news:n2').isBold, isFalse);
      await read.markOpened('news:n1', at: now);
      e = build(InboxData(broadcast: [news('n1', fresh)]));
      expect(e.firstWhere((x) => x.key == 'news:n1').isBold, isFalse);
    });

    test('ўчирилганлар кўринмайди; диалог бир темага гуруҳланади', () {
      final e = build(InboxData(
        dialog: [dialog('m1', now.subtract(const Duration(hours: 2))), dialog('m2', now)],
        broadcast: [news('n1', now)],
        hidden: {'n1'},
      ));
      final d = e.where((x) => x.kind == InboxKind.dialog).toList();
      expect(d.length, 1);
      expect(d.single.dismissIds, ['m1', 'm2']);
      expect(d.single.title, 'mdl_thread_ad_moderation');
      expect(e.any((x) => x.kind == InboxKind.news), isFalse);
    });

    test('буюртма: сарлавҳа тури, матн — сервер ёзуви ёки статус калити; хом статус чиқмайди', () {
      var e = build(InboxData(orders: [order('a', 'o1', now, status: 'in_delivery')]));
      final o = e.firstWhere((x) => x.kind == InboxKind.order);
      expect(o.title, 'bread_order');
      expect(o.preview, 'order_status_in_delivery');
      e = build(InboxData(orders: [order('a', 'o1', now, title: 'Етказилди')]));
      expect(e.firstWhere((x) => x.kind == InboxKind.order).preview, 'Етказилди');
      expect(orderStatusKey('weird'), isNull);
    });

    test('ҳайдовчи аризаси: ҳолат ўзгарса яна жирний', () async {
      final drv = {'status': 'pending', 'createdAt': null};
      var e = build(InboxData(driver: drv));
      expect(e.any((x) => x.kind == InboxKind.driver), isTrue);
      await read.markOpened('driver', at: now.add(const Duration(days: 1)));
      e = build(InboxData(driver: drv));
      expect(e.firstWhere((x) => x.kind == InboxKind.driver).isBold, isFalse);
    });

    test('филтр, қидирув ва чип сонлари', () {
      final e = build(InboxData(
        support: SupportChatMeta(lastMessage: 'x', updatedAt: now, lastFromAdmin: true),
        deals: [deal('a', now, unread: 2)],
        orders: [order('a', 'o1', now.subtract(const Duration(hours: 1)))],
        broadcast: [news('n1', now.subtract(const Duration(hours: 1)), title: 'Улгуржи бозор')],
      ));
      expect(filterInbox(e, InboxFilter.chats, '').map((x) => x.kind).toSet(),
          {InboxKind.support, InboxKind.deal});
      expect(filterInbox(e, InboxFilter.orders, '').single.kind, InboxKind.order);
      expect(filterInbox(e, InboxFilter.all, 'улгуржи').single.key, 'news:n1');
      expect(filterInbox(e, InboxFilter.all, 'УН 50').single.kind, InboxKind.deal);
      expect(inboxFilterCount(e, InboxFilter.chats), 3, reason: 'support 1 + deal 2');
      expect(inboxFilterCount(e, InboxFilter.orders), 1);
      expect(inboxFilterCount(e, InboxFilter.news), 1);
      expect(inboxFilterCount(e, InboxFilter.all), 0);
    });
  });
}
