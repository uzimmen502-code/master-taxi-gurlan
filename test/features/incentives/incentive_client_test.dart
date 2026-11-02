import 'package:ava_gurlan/core/utils/order_receipt_format.dart';
import 'package:ava_gurlan/features/incentives/incentive_service.dart';
import 'package:ava_gurlan/features/incentives/screens/auto_hub_screen.dart';
import 'package:ava_gurlan/features/platform_store/controllers/platform_store_controller.dart';
import 'package:ava_gurlan/features/platform_store/services/platform_cart_store.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:ava_gurlan/models/platform_product.dart';
import 'package:ava_gurlan/models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Рағбат (AVA бонуси, эга 2026-11-02) — клиент қисми: сават ҳисоби, модел, чек,
/// табрик/таклиф режаси, «Менинг машинам» фильтри. Ҳақиқий ҳисоб серверда — бу ерда фақат кўриниш.
PlatformProduct _p(String id, int price, {String cat = '', bool active = true}) => PlatformProduct(
      id: id,
      name: id,
      price: price,
      active: active,
      incentiveCategory: cat,
      createdAt: DateTime.utc(2026, 11, 1),
    );

IncentiveOffer _o(String id, {bool car = false, bool claimed = false, bool eligible = false, bool needsCar = false}) =>
    IncentiveOffer(
      programId: id,
      key: id,
      title: const {},
      amount: car ? 200000 : 100000,
      requireCar: car,
      claimed: claimed,
      eligible: eligible,
      needsCar: needsCar,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('сават: бонус → нетто → ҳамён → нақд', () {
    Future<PlatformStoreController> cart({required int preview, int balance = 300000}) async {
      final c = PlatformStoreController(
        cartStore: PlatformCartStore(),
        incentivePreviewer: (_) async => preview,
      )..debugProducts = [_p('tire1', 100000, cat: 'tire')];
      c.incentiveBalance = balance;
      c.addToCart(c.productOf('tire1')!);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return c;
    }

    test('бонус маҳсулот суммасидан айирилади, етказиш ҳақи қолади', () async {
      final c = await cart(preview: 60000);
      expect(c.cartTotal, 100000);
      expect(c.deliveryFee, 5000);
      expect(c.incentiveApplyAmount, 60000);
      expect(c.netTotal, 45000);
      c.walletBalance = 100000;
      c.setUseWallet(true);
      expect(c.walletApplyAmount, 45000);
      expect(c.cashDuePreview, 0);
      c.dispose();
    });

    test('сервер ортиқ қайтарса ҳам — маҳсулот суммасидан ошмайди (чегара)', () async {
      final c = await cart(preview: 250000);
      expect(c.incentiveApplyAmount, 100000);
      expect(c.netTotal, 5000);
      c.dispose();
    });

    test('мижоз бонусни ўчирса — тўлиқ сумма', () async {
      final c = await cart(preview: 60000);
      c.setUseIncentive(false);
      expect(c.incentiveApplyAmount, 0);
      expect(c.netTotal, 105000);
      c.dispose();
    });

    test('бонус баланси 0 — сўров йўқ, бонус йўқ', () async {
      var calls = 0;
      final c = PlatformStoreController(
        cartStore: PlatformCartStore(),
        incentivePreviewer: (_) async {
          calls++;
          return 50000;
        },
      )..debugProducts = [_p('x', 10000)];
      c.addToCart(c.productOf('x')!);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(calls, 0);
      expect(c.incentiveApplyAmount, 0);
      expect(c.netTotal, c.grandTotal);
      c.dispose();
    });

    test('ҳисоб хатоси — бонус кўрсатилмайди (сервер барибир ўзи ҳисоблайди)', () async {
      final c = PlatformStoreController(
        cartStore: PlatformCartStore(),
        incentivePreviewer: (_) async => throw StateError('offline'),
      )..debugProducts = [_p('x', 10000)];
      c.incentiveBalance = 50000;
      c.addToCart(c.productOf('x')!);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(c.incentivePreview, 0);
      expect(c.netTotal, c.grandTotal);
      c.dispose();
    });
  });

  group('модел', () {
    test('incentiveCategory нормаллашади ва ёзувга тушади', () {
      expect(PlatformProduct.normalizeIncentiveCategory('  Tire '), 'tire');
      expect(PlatformProduct.normalizeIncentiveCategory(null), '');
      final p = _p('a', 1000, cat: 'oil');
      expect(p.toFirestoreCreate()['incentiveCategory'], 'oil');
      expect(p.toFirestoreUpdate()['incentiveCategory'], 'oil');
      expect(p.copyWith(incentiveCategory: 'battery').incentiveCategory, 'battery');
    });

    test('ҳамёнда пул + бонус бирга кўринади, тўлов текшируви фақат пулни кўради', () {
      final u = const UserModel(id: '998901234567', bonusBalance: 15000, incentiveBalance: 100000);
      expect(u.bonusBalance, 15000);
      expect(u.incentiveBalance, 100000);
      expect(u.walletDisplayTotal, 115000);
      final old = const UserModel(id: '998901234567', bonusBalance: 7000);
      expect(old.incentiveBalance, 0);
      expect(old.walletDisplayTotal, 7000);
    });

    test('чекда бонус қатори жамидан олдин', () {
      const order = OrderModel(
        id: 'o1',
        type: 'platform',
        total: 45000,
        incentiveApplied: 60000,
        status: 'pending',
        items: [OrderItem(name: 'Шина', qty: 1, itemTotal: 100000)],
      );
      final lines = OrderReceiptFormat.lines(order);
      final bonus = lines.indexWhere((l) => l.startsWith('incentive_bonus_label'));
      final total = lines.indexWhere((l) => l.startsWith('total:'));
      expect(bonus, greaterThanOrEqualTo(0));
      expect(lines[bonus], contains('60'));
      expect(total, greaterThan(bonus));
      const plain = OrderModel(id: 'o2', type: 'platform', total: 1000, status: 'pending', items: []);
      expect(OrderReceiptFormat.lines(plain).any((l) => l.startsWith('incentive_bonus_label')), isFalse);
    });
  });

  group('табрик / таклиф режаси', () {
    test('аёллар дастури (машина шарт эмас) — ўзи олинади; машина дастури — сўралади', () {
      final s = planIncentiveSteps([
        _o('women', eligible: true),
        _o('car', car: true, needsCar: true),
      ]);
      expect(s.autoClaim.map((o) => o.programId), ['women']);
      expect(s.carOffers.map((o) => o.programId), ['car']);
    });

    test('олинган ёки мос келмаган — ҳеч нарса', () {
      final s = planIncentiveSteps([
        _o('women', claimed: true, eligible: true),
        _o('car', car: true, claimed: true),
        _o('x', car: true),
      ]);
      expect(s.autoClaim, isEmpty);
      expect(s.carOffers, isEmpty);
    });

    test('сервер жавоби ўқилади', () {
      final o = IncentiveOffer.fromMap({
        'programId': 'p1',
        'key': 'car200',
        'title': {'uz_Cyrl': 'Машина'},
        'amount': 200000,
        'buckets': [
          {'category': 'tire', 'amount': 120000},
          {'category': 'oil', 'amount': 80000},
        ],
        'requireCar': true,
        'claimed': false,
        'eligible': false,
        'needsCar': true,
      });
      expect(o.amount, 200000);
      expect(o.buckets.length, 2);
      expect(o.buckets.first.category, 'tire');
      expect(o.needsCar, isTrue);
      expect(o.title['uz_Cyrl'], 'Машина');
    });
  });

  group('«Менинг машинам»', () {
    test('фақат фаол, нархли, туркумли маҳсулотлар; туркум бўйича', () {
      final all = [
        _p('t', 100, cat: 'tire'),
        _p('o', 100, cat: 'oil'),
        _p('off', 100, cat: 'tire', active: false),
        _p('free', 0, cat: 'tire'),
        _p('plain', 100),
      ];
      expect(autoHubProducts(all, '').map((p) => p.id), ['t', 'o']);
      expect(autoHubProducts(all, 'tire').map((p) => p.id), ['t']);
      expect(autoHubProducts(all, 'battery'), isEmpty);
    });

    test('бонус қолдиғи туркумлар бўйича; муддати ўтган ва сарфланган ҳисобланмайди', () {
      final now = DateTime.utc(2026, 11, 3);
      final s = autoHubBonusSummary([
        {
          'status': 'active',
          'expiresAt': Timestamp.fromDate(DateTime.utc(2026, 12, 1)),
          'buckets': {'tire': 120000, 'oil': 0},
        },
        {
          'status': 'active',
          'expiresAt': Timestamp.fromDate(DateTime.utc(2026, 11, 20)),
          'buckets': {'any': 100000},
        },
        {
          'status': 'active',
          'expiresAt': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
          'buckets': {'tire': 50000},
        },
        {
          'status': 'spent',
          'expiresAt': Timestamp.fromDate(DateTime.utc(2026, 12, 1)),
          'buckets': {'battery': 10},
        },
      ], now);
      expect(s.byCategory, {'tire': 120000, 'any': 100000});
      expect(s.nearestExpiry!.isAtSameMomentAs(DateTime.utc(2026, 11, 20)), isTrue);
    });
  });
}
