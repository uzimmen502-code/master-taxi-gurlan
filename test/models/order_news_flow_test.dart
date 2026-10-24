import 'package:ava_gurlan/features/admin_web/screens/admin_order_news_list_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_news_read_service.dart';
import 'package:ava_gurlan/models/news_item.dart';
import 'package:ava_gurlan/models/order_news_group.dart';
import 'package:ava_gurlan/repositories/news_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Буюртма хабар» оқими аудити (2026-10-11): админ сайдбар бўлими,
/// мижоз «Буюртма» таби, бош badge.
void main() {
  NewsItem n(
    String id, {
    int minute = 0,
    String orderId = '',
    String orderStatus = '',
    String orderType = '',
    String source = 'order_status',
    String category = 'order',
    bool pushDirect = false,
  }) =>
      NewsItem(
        id: id,
        title: 'T $id',
        body: 'B $id',
        createdAt: DateTime(2026, 10, 11, 12, minute),
        category: category,
        targetUserId: '998901112233',
        source: source,
        orderId: orderId,
        orderStatus: orderStatus,
        orderType: orderType,
        pushDirect: pushDirect,
      );

  group('Мижоз ўқилмаганлар ҳисоби — шахсий хабарлар', () {
    test('буюртма бўлими шахсий хабарларни ҳам санайди (аввал доим 0)', () {
      expect(NewsRepository.feedHasPersonalNews(NewsFeedKind.order), isTrue);
      expect(NewsRepository.feedHasPersonalNews(NewsFeedKind.dialog), isTrue);
    });
    test('умумий янгиликлар — фақат умумий сўров', () {
      expect(
          NewsRepository.feedHasPersonalNews(NewsFeedKind.broadcast), isFalse);
    });
  });

  group('OrderNewsGroup.fromItems', () {
    test('orderId сиз буюртма хабари ташланмайди — ўз картаси', () {
      final groups = OrderNewsGroup.fromItems([
        n('a', orderId: 'o1', orderStatus: 'new', orderType: 'platform'),
        n('r', minute: 5, source: 'collection_receipt'),
      ]);
      expect(groups, hasLength(2));
      final standalone = groups.firstWhere((g) => g.orderId.isEmpty);
      expect(standalone.messages.single.id, 'r');
      expect(standalone.moduleLabelKey, 'order');
    });

    test('иккита orderId сиз хабар — иккита алоҳида карта', () {
      final groups = OrderNewsGroup.fromItems([
        n('r1', source: 'collection_receipt'),
        n('r2', minute: 1, source: 'courier_arrived'),
      ]);
      expect(groups, hasLength(2));
    });

    test('чек охирги бўлса ҳам тур — тури ёзилган хабардан (аввал «Нон»)', () {
      final groups = OrderNewsGroup.fromItems([
        n('a', orderId: 'o1', orderStatus: 'new', orderType: 'platform'),
        n('b', minute: 1, orderId: 'o1', orderStatus: 'delivered',
            orderType: 'platform'),
        n('c', minute: 2, orderId: 'o1', source: 'payment_receipt'),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.orderType, 'platform');
      expect(groups.single.messages.map((m) => m.id), ['a', 'b', 'c']);
    });

    test('буюртма бўлмаган хабар гуруҳга тушмайди', () {
      final groups = OrderNewsGroup.fromItems([
        n('w', category: 'wallet', source: 'wallet_withdraw'),
      ]);
      expect(groups, isEmpty);
    });
  });

  group('Админ «Буюртма хабар» — ёрлиқ ва филтр', () {
    test('cancelled — «Бекор» (аввал хом `cancelled`)', () {
      expect(orderNewsStatusLabel(n('x', orderStatus: 'cancelled')), 'Бекор');
    });
    test('статуссиз хабар — манбаси бўйича (аввал «—»)', () {
      expect(orderNewsStatusLabel(n('x', source: 'courier_arrived')),
          'Курьер етиб келди');
      expect(orderNewsStatusLabel(n('x', source: 'payment_receipt')),
          'Тўлов чеки');
      expect(orderNewsStatusLabel(n('x', source: 'unknown_src')), '—');
    });
    test('тур: platform/restaurant «Нон» эмас', () {
      expect(orderNewsTypeLabel(n('x', orderType: 'platform')),
          '🛒 Улгуржи бозор');
      expect(orderNewsTypeLabel(n('x', orderType: 'restaurant')),
          '🍽 Кафе-ресторан');
      expect(orderNewsTypeLabel(n('x', source: 'restaurant_order')),
          '🍽 Кафе-ресторан');
      expect(orderNewsTypeLabel(n('x', orderType: 'bread')), '🍞 Нон буюртма');
      expect(orderNewsTypeLabel(n('x', source: 'collection_receipt')),
          '📦 Буюртма');
    });
    test('«Бошқа» филтри — фақат статуссизлар; статус филтри аниқ', () {
      final items = [
        n('s', orderStatus: 'ready'),
        n('o', source: 'courier_arrived'),
      ];
      expect(filterOrderNews(items, 'all').map((e) => e.id), ['s', 'o']);
      expect(filterOrderNews(items, kOrderNewsOtherFilter).map((e) => e.id),
          ['o']);
      expect(filterOrderNews(items, 'ready').map((e) => e.id), ['s']);
      expect(filterOrderNews(items, 'cancelled'), isEmpty);
    });
  });

  group('NewsItem.pushDirect', () {
    test('push функция ўзи юборган — «push кутилмоқда» эмас', () {
      final item = NewsItem(
        id: 'p',
        title: 'T',
        body: 'B',
        createdAt: DateTime.now(),
        source: 'wallet_withdraw',
        targetUserId: '998901112233',
        pushDirect: true,
      );
      expect(item.pushPending, isFalse);
      // «Push qayta yuborish» тугмаси сақланади.
      expect(item.expectsPushFromAdmin, isTrue);
    });
    test('pushDirect йўқ — аввалгидек кутилмоқда', () {
      final item = NewsItem(
        id: 'p',
        title: 'T',
        body: 'B',
        createdAt: DateTime.now(),
        source: 'wallet_withdraw',
        targetUserId: '998901112233',
      );
      expect(item.pushPending, isTrue);
    });
  });

  group('AdminNewsReadService.markOrderSeen — сервер вақти белгиси', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('белги фақат олдинга силжийди ва сақланади', () async {
      final s = AdminNewsReadService();
      await s.init();
      expect(s.lastOrderSeen, isNull);
      final t1 = DateTime.utc(2026, 10, 11, 12, 0, 0, 0, 123);
      await s.markOrderSeen(t1);
      expect(s.lastOrderSeen, t1);
      await s.markOrderSeen(t1.subtract(const Duration(minutes: 5)));
      expect(s.lastOrderSeen, t1, reason: 'эскиси белгини орқага қайтармайди');

      final reloaded = AdminNewsReadService();
      await reloaded.init();
      expect(reloaded.lastOrderSeen!.microsecondsSinceEpoch,
          t1.microsecondsSinceEpoch,
          reason: 'микросекунд йўқолмайди — энг янги хабар қайта саналмайди');
    });

    test('эски ms калити ўқилади (орқага мослик)', () async {
      final ms = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({'admin_news_order_seen_ms': ms});
      final s = AdminNewsReadService();
      await s.init();
      expect(s.lastOrderSeen!.millisecondsSinceEpoch, ms);
    });
  });
}
