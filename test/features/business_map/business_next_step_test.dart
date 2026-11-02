import 'dart:async';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_type_profile.dart';
import 'package:ava_gurlan/features/business_map/screens/business_next_step_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// «Кейинги қадам» / эга хаби (S1, эга 2026-11-03). Локализациясиз — матн ўрнида калитнинг ўзи кўринади.

Business _b(
  String id,
  BusinessCategory c, {
  String subtype = '',
  bool online = false,
  String restaurantId = '',
  String status = 'active',
  String name = 'Объект',
}) =>
    Business(
      id: id,
      ownerId: '998901111111',
      name: name,
      category: c,
      subtype: subtype,
      phone: '998901234567',
      lat: online ? 0 : 41.3,
      lng: online ? 0 : 69.2,
      address: online ? '' : 'Гурлан, Мустақиллик 5',
      online: online,
      restaurantId: restaurantId,
      status: status,
    );

/// Ҳук чақирувлари журнали.
class _Calls {
  final log = <String>[];
  int countLoads = 0;
}

Future<_Calls> _pump(
  WidgetTester tester,
  Business b, {
  int count = 0,
  bool countFails = false,
  bool justCreated = false,
  Stream<Business?>? watch,
  Set<String> linked = const {},
  _Calls? calls,
}) async {
  tester.view.physicalSize = const Size(420 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final c = calls ?? _Calls();
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(), // қайта чақирилганда — тоза навигатор
    theme: AppTheme.light,
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => BusinessNextStepScreen(
                business: b,
                justCreated: justCreated,
                watch: watch,
                linkedRestaurantIds: linked,
                loadOfferCount: (x) async {
                  c.countLoads++;
                  if (countFails) throw StateError('offline');
                  return count;
                },
                openOffers: (ctx, x, openForm) async => c.log.add('offers:${x.id}:form=$openForm'),
                menuFlow: (ctx, x, l) async => c.log.add('menu:${x.id}:${(l.toList()..sort()).join(',')}'),
                openEdit: (ctx, x) async {
                  c.log.add('edit:${x.id}');
                  return true;
                },
                openCustomerView: (ctx, x) async => c.log.add('view:${x.id}'),
                openShare: (ctx, x) async => c.log.add('share:${x.id}'),
                openChats: (ctx) async => c.log.add('chats'),
                openBridge: (ctx, br) async => c.log.add('bridge:${br.name}'),
              ),
            )),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
  return c;
}

double _progress(WidgetTester tester) =>
    tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value!;

Finder _cta(String step) => find.byKey(ValueKey('biz_next_cta_$step'));
Finder _in(String step, String text) =>
    find.descendant(of: find.byKey(ValueKey('biz_next_step_$step')), matching: find.text(text));
final _done = find.byKey(const ValueKey('biz_next_done'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('гуруҳ бўйича таклиф қадами (тур профили — ягона манба)', () {
    testWidgets('хизмат тури (авто): сарлавҳа/изоҳ/тугма — services; 0 та → форма дарҳол очилади', (tester) async {
      final b = _b('a1', BusinessCategory.auto);
      expect(BusinessTypeProfile.forBusiness(b).group, BusinessOfferGroup.services);
      final c = await _pump(tester, b);
      expect(_in('offers', 'biz_next_services_title'), findsOneWidget);
      expect(_in('offers', 'biz_next_services_sub'), findsOneWidget);
      expect(_in('offers', 'biz_next_services_cta'), findsOneWidget);
      expect(c.countLoads, 1, reason: 'очилганда битта ўқиш');

      await tester.tap(_cta('offers'));
      await tester.pumpAndSettle();
      expect(c.log, ['offers:a1:form=true']);
      expect(c.countLoads, 2, reason: 'каталогдан қайтгач сон қайта ўқилади');
    });

    testWidgets('маҳсулот тури (қишлоқ хўжалиги) — products калитлари', (tester) async {
      await _pump(tester, _b('g1', BusinessCategory.agriculture));
      expect(_in('offers', 'biz_next_products_title'), findsOneWidget);
      expect(_in('offers', 'biz_next_products_cta'), findsOneWidget);
    });

    testWidgets('аралаш тур («Бошқа») — mixed калитлари, тугма «Қўшиш»', (tester) async {
      await _pump(tester, _b('o1', BusinessCategory.other));
      expect(_in('offers', 'biz_next_mixed_title'), findsOneWidget);
      expect(_in('offers', 'bizprod_add'), findsOneWidget);
    });

    testWidgets('таклиф бор (3 та): қадам бажарилган, сон кўрсатилади, тугма «Бошқариш» (форма очилмайди)', (tester) async {
      final c = await _pump(tester, _b('a1', BusinessCategory.auto), count: 3);
      expect(_in('offers', 'biz_next_offer_count'), findsOneWidget);
      expect(_in('offers', 'biz_next_manage'), findsOneWidget);
      expect(_done, findsNWidgets(2), reason: 'харитада ✓ + таклифлар ✓');
      expect(_progress(tester), 0.5);
      await tester.tap(_cta('offers'));
      await tester.pumpAndSettle();
      expect(c.log, ['offers:a1:form=false']);
    });

    testWidgets('сонни ўқиб бўлмади — «0 та» эмас, оддий изоҳ; форма автомат очилмайди', (tester) async {
      final c = await _pump(tester, _b('a1', BusinessCategory.auto), countFails: true);
      expect(_in('offers', 'biz_next_services_sub'), findsOneWidget);
      expect(_in('offers', 'biz_next_offer_count'), findsNothing);
      await tester.tap(_cta('offers'));
      await tester.pumpAndSettle();
      expect(c.log, ['offers:a1:form=false']);
    });

    testWidgets('овқатланиш (харитада) — «Меню» занжири, таклиф сони ўқилмайди, бошқа уланган ресторанлар узатилади',
        (tester) async {
      final c = await _pump(tester, _b('f1', BusinessCategory.food), linked: {'r_old'});
      expect(c.countLoads, 0, reason: 'менюни ресторан бўлими юритади');
      expect(_in('offers', 'bizmap_menu_sheet_title'), findsOneWidget);
      expect(_in('offers', 'biz_next_menu_sub'), findsOneWidget);
      expect(_in('offers', 'bizmap_open_menu'), findsOneWidget);
      await tester.tap(_cta('offers'));
      await tester.pumpAndSettle();
      expect(c.log, ['menu:f1:r_old']);
    });

    testWidgets('овқатланиш, меню уланган — қадам бажарилган', (tester) async {
      await _pump(tester, _b('f2', BusinessCategory.food, restaurantId: 'r2'));
      expect(_in('offers', 'bizmap_menu_linked'), findsOneWidget);
      expect(_in('offers', 'biz_next_manage'), findsOneWidget);
      expect(_progress(tester), 0.5);
    });

    testWidgets('онлайн овқатланиш объекти — менюга уланмайди, умумий каталог (mixed)', (tester) async {
      final c = await _pump(tester, _b('fo', BusinessCategory.food, online: true));
      expect(_in('offers', 'biz_next_mixed_title'), findsOneWidget);
      await tester.tap(_cta('offers'));
      await tester.pumpAndSettle();
      expect(c.log, ['offers:fo:form=true']);
      expect(find.text('biz_next_pill_online'), findsOneWidget);
      expect(find.text('biz_next_hero_online'), findsOneWidget);
      expect(_in('placed', 'biz_next_step_online'), findsOneWidget);
    });
  });

  group('прогресс ва қадамлар', () {
    testWidgets('янги объект: 1/4 (фақат харитада ✓); асосий тугма — таклиф қўшиш; «Кейинроқ» ёпади', (tester) async {
      final c = await _pump(tester, _b('a1', BusinessCategory.auto), justCreated: true);
      expect(find.text('biz_next_title'), findsOneWidget, reason: 'AppBar сарлавҳаси');
      expect(find.text('biz_next_pill_map'), findsOneWidget);
      expect(find.text('biz_next_hero_map'), findsOneWidget);
      expect(_in('placed', 'Гурлан, Мустақиллик 5'), findsOneWidget);
      expect(_done, findsOneWidget);
      expect(_progress(tester), 0.25);
      final primary = find.byKey(const ValueKey('biz_next_primary'));
      expect(find.descendant(of: primary, matching: find.text('biz_next_services_cta')), findsOneWidget);
      await tester.tap(primary);
      await tester.pumpAndSettle();
      expect(c.log, ['offers:a1:form=true']);

      await tester.tap(find.byKey(const ValueKey('biz_next_later')));
      await tester.pumpAndSettle();
      expect(find.text('OPEN'), findsOneWidget, reason: '«Кейинроқ» — рўйхатга қайтади');
    });

    testWidgets('мижоз кўзи ва ҳавола: босилгач ✓, қурилмада сақланади; асосий тугма кейинги қадамга ўтади',
        (tester) async {
      final c = await _pump(tester, _b('a1', BusinessCategory.auto), count: 2);
      final primary = find.byKey(const ValueKey('biz_next_primary'));
      expect(find.descendant(of: primary, matching: find.text('biz_customer_view')), findsOneWidget);

      await tester.tap(_cta('preview'));
      await tester.pumpAndSettle();
      expect(_progress(tester), 0.75);
      expect(find.descendant(of: primary, matching: find.text('biz_link_qr')), findsOneWidget);

      await tester.tap(primary);
      await tester.pumpAndSettle();
      expect(c.log, ['view:a1', 'share:a1']);
      expect(_progress(tester), 1.0);
      expect(find.descendant(of: primary, matching: find.text('biz_open_page')), findsOneWidget,
          reason: 'ҳаммаси тайёр — саҳифага ўтиш');

      // Қайта очилганда ҳам белгилар турибди (шу объект учун).
      await _pump(tester, _b('a1', BusinessCategory.auto), count: 2);
      expect(_progress(tester), 1.0);
      await _pump(tester, _b('a2', BusinessCategory.auto), count: 2);
      expect(_progress(tester), 0.5, reason: 'бошқа объект — ўз белгилари');
    });

    testWidgets('хаб (justCreated эмас): сарлавҳа — объект номи, «Кейинроқ» йўқ; таҳрир ва чатлар ҳуклари', (tester) async {
      final c = await _pump(tester, _b('a1', BusinessCategory.auto, name: 'Мойка №1'));
      expect(find.widgetWithText(AppBar, 'Мойка №1'), findsOneWidget);
      expect(find.byKey(const ValueKey('biz_next_later')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('biz_next_edit_action')));
      await tester.pumpAndSettle();
      await tester.tap(_cta('edit'));
      await tester.pumpAndSettle();
      await tester.tap(_cta('chats'));
      await tester.pumpAndSettle();
      expect(c.log, ['edit:a1', 'edit:a1', 'chats']);
    });

    testWidgets('объект янгиланса (таҳрир) — оқимдан келган ном кўринади; null эътиборсиз', (tester) async {
      final ctl = StreamController<Business?>();
      addTearDown(ctl.close);
      await _pump(tester, _b('a1', BusinessCategory.auto, name: 'Эски ном'), watch: ctl.stream);
      ctl.add(_b('a1', BusinessCategory.auto, name: 'Янги ном'));
      await tester.pumpAndSettle();
      expect(find.text('Янги ном'), findsWidgets);
      ctl.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Янги ном'), findsWidgets);
    });
  });

  group('тур кўприклари, лицензия ва блок', () {
    testWidgets('кўчмас мулк — «Эълон қўшиш» кўприги', (tester) async {
      final c = await _pump(tester, _b('r1', BusinessCategory.realEstate));
      final card = find.byKey(const ValueKey('biz_next_bridge_realtyListing'));
      expect(find.descendant(of: card, matching: find.text('realty_add_cta')), findsOneWidget);
      expect(find.text('biz_next_more_title'), findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(c.log, ['bridge:realtyListing']);
    });

    testWidgets('юк машинаси — «Юк ташувчи бўлиш»; EV станцияси — зарядлаш; сартарош — кўприк йўқ', (tester) async {
      var c = await _pump(tester, _b('l1', BusinessCategory.logistics, subtype: 'Юк машинаси'));
      await tester.tap(find.byKey(const ValueKey('biz_next_bridge_cargoLocal')));
      await tester.pumpAndSettle();
      expect(c.log, ['bridge:cargoLocal']);

      c = await _pump(tester, _b('e1', BusinessCategory.auto, subtype: 'Электромобиль қувватлаш станцияси'));
      expect(find.text('ev_add_station_title'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('biz_next_bridge_evStation')));
      await tester.pumpAndSettle();
      expect(c.log, ['bridge:evStation']);

      await _pump(tester, _b('p1', BusinessCategory.personal));
      for (final br in BusinessModuleBridge.values) {
        expect(find.byKey(ValueKey('biz_next_bridge_${br.name}')), findsNothing);
      }
      expect(find.text('biz_next_more_title'), findsNothing);
    });

    testWidgets('лицензияли тур (тиббиёт) — эслатма (тўсиқ эмас: тугмалар ишлайди); авто — эслатма йўқ', (tester) async {
      final c = await _pump(tester, _b('h1', BusinessCategory.health));
      final note = find.byKey(const ValueKey('biz_next_licence_note'));
      expect(find.descendant(of: note, matching: find.text('business_cat_note_health')), findsOneWidget);
      await tester.tap(_cta('offers'));
      await tester.pumpAndSettle();
      expect(c.log, ['offers:h1:form=true']);

      await _pump(tester, _b('a1', BusinessCategory.auto));
      expect(find.byKey(const ValueKey('biz_next_licence_note')), findsNothing);
    });

    testWidgets('блокланган объект — сабаб, қўшиш/улашиш/мижоз кўзи ва асосий тугма йўқ', (tester) async {
      await _pump(tester, _b('x1', BusinessCategory.realEstate, status: 'blocked'));
      expect(find.byKey(const ValueKey('biz_next_blocked_banner')), findsOneWidget);
      expect(find.text('bizprod_blocked_banner'), findsOneWidget);
      expect(find.text('bizprod_status_blocked'), findsOneWidget);
      expect(_in('offers', 'biz_next_services_title'), findsOneWidget);
      expect(_cta('offers'), findsNothing, reason: 'бўш каталогга қўшиб бўлмайди (rules ҳам рад этади)');
      expect(find.byKey(const ValueKey('biz_next_step_preview')), findsNothing);
      expect(find.byKey(const ValueKey('biz_next_step_share')), findsNothing);
      expect(find.byKey(const ValueKey('biz_next_primary')), findsNothing);
      expect(find.byKey(const ValueKey('biz_next_bridge_realtyListing')), findsNothing);
    });

    testWidgets('тор экранда оверфлоу йўқ', (tester) async {
      await _pump(tester, _b('h1', BusinessCategory.health, name: 'Жуда узун номли кўп тармоқли тиббиёт маркази'),
          justCreated: true);
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
