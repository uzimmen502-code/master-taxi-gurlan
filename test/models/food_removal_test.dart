import 'package:ava_gurlan/features/home/home_modules_catalog.dart';
import 'package:ava_gurlan/models/news_item.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:ava_gurlan/models/order_news_group.dart';
import 'package:ava_gurlan/repositories/inventory_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Овқат» модули олиб ташланди (эга, 2026-10-11): эски `type:'food'`
/// буюртмалари ва уларнинг хабарлари ҳеч бир рўйхатда кўринмайди.
void main() {
  OrderModel order(String type) =>
      OrderModel(id: 'o', type: type, total: 1000, status: 'new', items: const []);

  NewsItem news(
    String id, {
    String orderId = 'o1',
    String orderType = '',
    String body = '',
    String category = 'order',
    String source = 'order_status',
    int minute = 0,
  }) =>
      NewsItem(
        id: id,
        title: 'T',
        body: body,
        createdAt: DateTime(2026, 10, 11, 12, minute),
        category: category,
        targetUserId: '998901112233',
        source: source,
        orderId: orderId,
        orderType: orderType,
      );

  group('OrderModel', () {
    test('food — олиб ташланган, бошқалар эмас', () {
      expect(order('food').isRemovedFoodOrder, isTrue);
      for (final t in ['bread', 'platform', 'restaurant', '']) {
        expect(order(t).isRemovedFoodOrder, isFalse, reason: t);
      }
    });

    test('тур номи — ягона манба; улгуржи энди «Нон» эмас', () {
      expect(order('platform').typeLabelUz, 'Улгуржи бозор');
      expect(order('restaurant').typeLabelUz, 'Кафе-ресторан');
      expect(order('bread').typeLabelUz, 'Нон');
    });
  });

  group('NewsItem.isRemovedFoodOrderNews', () {
    test('буюртма хабари + food — яширилади', () {
      expect(news('a', orderType: 'food').isRemovedFoodOrderNews, isTrue);
    });
    test('бошқа турдаги буюртма хабари — кўринади', () {
      expect(news('a', orderType: 'restaurant').isRemovedFoodOrderNews, isFalse);
      expect(news('a', orderType: '').isRemovedFoodOrderNews, isFalse);
    });
    test('буюртма бўлмаган хабар — тегилмайди', () {
      final n = news('w', orderType: 'food', category: 'wallet', source: 'wallet_x');
      expect(n.isRemovedFoodOrderNews, isFalse);
    });
  });

  group('OrderNewsGroup.fromItems', () {
    test('food буюртма гуруҳи йўқ, қолганлари бор', () {
      final groups = OrderNewsGroup.fromItems([
        news('a', orderId: 'f1', orderType: 'food'),
        news('b', orderId: 'b1', orderType: 'bread', minute: 1),
        news('c', orderId: 'r1', orderType: 'restaurant', minute: 2),
      ]);
      expect(groups.map((g) => g.orderId), ['r1', 'b1']);
    });

    test('тури ёзилмаган эски хабар — матндан «овқат» деб аниқланса ҳам яширилади', () {
      final groups = OrderNewsGroup.fromItems([
        news('a', orderId: 'f1', body: 'Тайёр овқат'),
      ]);
      expect(groups, isEmpty);
    });

    test('ресторан хабари матнида «овқат» бўлса ҳам кўринади (тур ёзилган)', () {
      final groups = OrderNewsGroup.fromItems([
        news('a', orderId: 'r1', orderType: 'restaurant', body: 'Овқатингиз тайёр'),
      ]);
      expect(groups.single.orderType, 'restaurant');
    });
  });

  group('Модул ва омбор', () {
    test('бош экран модулларида food йўқ', () {
      expect(HomeModulesCatalog.modules.map((m) => m.id), isNot(contains('food')));
      expect(() => HomeModulesCatalog.byId('food'), throwsArgumentError);
      expect(HomeModulesCatalog.byId('restaurants').id, 'restaurants');
    });

    test('омбор турлари — фақат нон ва қўшимча', () {
      expect(InventoryKind.values, [InventoryKind.bread, InventoryKind.extra]);
    });
  });
}
