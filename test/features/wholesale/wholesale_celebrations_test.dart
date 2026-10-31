import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_seller.dart';
import 'package:ava_gurlan/features/wholesale/wholesale_celebrations.dart';
import 'package:ava_gurlan/l10n/app_localizations.dart';
import 'package:ava_gurlan/services/push_navigation.dart';
import 'package:ava_gurlan/shared/widgets/celebration_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Эга, 2026-10-31: улгуржи сотувчи тасдиқланганда («ҳа») ва биринчи буюртмада
/// («табрик бўлсин») — табрик, қурилмада БИР МАРТА.
class _KeyL10n extends AppLocalizations {
  _KeyL10n(super.locale);

  @override
  String translate(String key) => key;
}

class _KeyL10nDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _KeyL10nDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture(_KeyL10n(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}

const _phone = '+998 90 111 22 33';
final _now = DateTime(2026, 10, 31, 12);

WholesaleSeller _seller({String status = WholesaleSeller.statusApproved, DateTime? approvedAt}) =>
    WholesaleSeller(phone: _phone, companyName: 'Test', approvalStatus: status, approvedAt: approvedAt);

/// Тугма босилганда [run] чақирилади; қайтаради: натижа (ойна ҳали очиқ бўлса `null`).
Future<bool? Function()> _pump(WidgetTester t, Future<bool> Function(BuildContext) run) async {
  bool? shown;
  var done = false;
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      _KeyL10nDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            shown = await run(context);
            done = true;
          },
          child: const Text('go'),
        ),
      ),
    ),
  ));
  return () => done ? shown : null;
}

Future<void> _tapGo(WidgetTester t) async {
  await t.tap(find.text('go'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('isFreshWholesaleApproval', () {
    test('тасдиқ бугун — янги', () {
      expect(isFreshWholesaleApproval(_seller(approvedAt: _now.subtract(const Duration(hours: 1))), _now), isTrue);
    });
    test('чегара: роппа-роса 7 кун — янги; 7 кун + 1 дақиқа — эски', () {
      expect(isFreshWholesaleApproval(_seller(approvedAt: _now.subtract(wholesaleSellerApprovalFreshFor)), _now),
          isTrue);
      expect(
          isFreshWholesaleApproval(
              _seller(approvedAt: _now.subtract(wholesaleSellerApprovalFreshFor + const Duration(minutes: 1))), _now),
          isFalse);
    });
    test('кутилмоқда / рад этилган / approvedAt йўқ — табрик йўқ', () {
      expect(isFreshWholesaleApproval(_seller(status: WholesaleSeller.statusPending, approvedAt: _now), _now), isFalse);
      expect(isFreshWholesaleApproval(_seller(status: WholesaleSeller.statusRejected, approvedAt: _now), _now), isFalse);
      expect(isFreshWholesaleApproval(_seller(), _now), isFalse);
    });
    test('approvedAt келажакда (соат фарқи) — янги', () {
      expect(isFreshWholesaleApproval(_seller(approvedAt: _now.add(const Duration(minutes: 5))), _now), isTrue);
    });
  });

  group('celebrateWholesaleSellerApprovedOnce', () {
    testWidgets('янги тасдиқ: табрик бир марта; иккинчи марта — йўқ', (t) async {
      final s = _seller(approvedAt: _now);
      var result = await _pump(t, (c) => celebrateWholesaleSellerApprovedOnce(c, seller: s, now: _now));
      await _tapGo(t);
      expect(find.text('wholesale_seller_approved_title'), findsOneWidget);
      expect(find.text('wholesale_seller_approved_sub'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('celebration_ok')));
      await t.pumpAndSettle();
      expect(result(), isTrue);

      result = await _pump(t, (c) => celebrateWholesaleSellerApprovedOnce(c, seller: s, now: _now));
      await _tapGo(t);
      expect(find.text('wholesale_seller_approved_title'), findsNothing);
      expect(result(), isFalse);
    });

    testWidgets('эски тасдиқ (8 кун) — табрик йўқ ва белги ҳам қўйилмайди', (t) async {
      final s = _seller(approvedAt: _now.subtract(const Duration(days: 8)));
      final result = await _pump(t, (c) => celebrateWholesaleSellerApprovedOnce(c, seller: s, now: _now));
      await _tapGo(t);
      expect(find.text('wholesale_seller_approved_title'), findsNothing);
      expect(result(), isFalse);
      expect(await CelebrationOnce.wasClaimed(wholesaleSellerApprovedKey(_phone)), isFalse);
    });
  });

  group('celebrateWholesaleFirstOrderOnce', () {
    testWidgets('0 та буюртма — табрик йўқ, белги йўқ; кейин 1 та — табрик', (t) async {
      var result = await _pump(t, (c) => celebrateWholesaleFirstOrderOnce(c, sellerId: _phone, orderCount: 0));
      await _tapGo(t);
      expect(result(), isFalse);
      expect(await CelebrationOnce.wasClaimed(wholesaleFirstOrderKey(_phone)), isFalse);

      result = await _pump(t, (c) => celebrateWholesaleFirstOrderOnce(c, sellerId: _phone, orderCount: 1));
      await _tapGo(t);
      expect(find.text('wholesale_first_order_title'), findsOneWidget);
      expect(find.text('wholesale_first_order_view'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('celebration_ok')));
      await t.pumpAndSettle();
      expect(result(), isTrue);
    });

    testWidgets('1 та — бир марта; яна 1 та — табрик йўқ', (t) async {
      var result = await _pump(t, (c) => celebrateWholesaleFirstOrderOnce(c, sellerId: _phone, orderCount: 1));
      await _tapGo(t);
      await t.tap(find.byKey(const ValueKey('celebration_ok')));
      await t.pumpAndSettle();
      expect(result(), isTrue);

      result = await _pump(t, (c) => celebrateWholesaleFirstOrderOnce(c, sellerId: _phone, orderCount: 1));
      await _tapGo(t);
      expect(find.text('wholesale_first_order_title'), findsNothing);
      expect(result(), isFalse);
    });

    testWidgets('2+ та (биринчиси ўтиб кетган) — табрик йўқ ва белги қўйилади: кейин 1 кўрилса ҳам чиқмайди',
        (t) async {
      var result = await _pump(t, (c) => celebrateWholesaleFirstOrderOnce(c, sellerId: _phone, orderCount: 2));
      await _tapGo(t);
      expect(find.text('wholesale_first_order_title'), findsNothing);
      expect(result(), isFalse);
      expect(await CelebrationOnce.wasClaimed(wholesaleFirstOrderKey(_phone)), isTrue);

      result = await _pump(t, (c) => celebrateWholesaleFirstOrderOnce(c, sellerId: _phone, orderCount: 1));
      await _tapGo(t);
      expect(find.text('wholesale_first_order_title'), findsNothing);
      expect(result(), isFalse);
    });

    test('калит телефон шаклига боғлиқ эмас (каноник)', () {
      expect(wholesaleFirstOrderKey('+998 90 111 22 33'), wholesaleFirstOrderKey('998901112233'));
      expect(wholesaleSellerApprovedKey('901112233'), wholesaleSellerApprovedKey('+998901112233'));
    });
  });

  test('push: сотувчига «янги буюртма» ҳодисаси — сервер калити билан бир хил', () {
    expect(PushNavigation.wholesaleNewOrderEvent, 'ws_card_new_order');
  });
}
