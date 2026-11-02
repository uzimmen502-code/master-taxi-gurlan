// Рўйхатдан ўтиш: олдиндан тўлдириш, `onRegistered` ва панел таби (эга, 2026-11-03: «Менинг бизнесим»
// овқатланиш объекти → меню занжири). Параметрлар берилмаса — аввалги хулқ ўзгармаган.

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_panel_screen.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_register_form.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo implements RestaurantsRepository {
  final events = <String>[];
  Map<String, dynamic>? payload;

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> payload, {String requestId = ''}) async {
    events.add('register');
    this.payload = payload;
    return {'restaurantId': 'r9', 'status': 'approved'};
  }

  @override
  Stream<Restaurant?> watchRestaurant(String id) => Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

const _prefill = RestaurantRegisterPrefill(
  name: 'Gurlan osh',
  description: 'Milliy taomlar',
  address: 'Gurlan, Navoiy 5',
  contactPhone: '998907654321',
  lat: 41.84,
  lng: 60.39,
  venueType: 'chaikhana',
  openTime: '08:00',
  closeTime: '22:00',
);

Future<void> _open(WidgetTester t, RestaurantRegisterScreen screen) async {
  SharedPreferences.setMockInitialValues({'user_phone': '998901111111'});
  t.view.physicalSize = const Size(390 * 3, 2400 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  await t.pumpAndSettle();
}

String _field(WidgetTester t, String labelKey) =>
    t.widget<TextField>(find.widgetWithText(TextField, labelKey)).controller!.text;

/// Юбориш. Табрик очиқ турганда тугма спиннери айланади (`_sending`) — `pumpAndSettle` эмас, бир неча кадр.
Future<void> _submit(WidgetTester t) async {
  final btn = find.widgetWithText(FilledButton, 'restaurants_m_submit');
  await t.ensureVisible(btn);
  await t.tap(btn);
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

final _celebrationOk = find.byKey(const ValueKey('celebration_ok'));

void main() {
  testWidgets('олдиндан тўлдириш формага тушади; телефон профилдагидан устун', (t) async {
    await _open(t, RestaurantRegisterScreen(repository: _Repo(), prefill: _prefill));
    expect(_field(t, 'restaurants_m_name'), 'Gurlan osh');
    expect(_field(t, 'restaurants_m_description'), 'Milliy taomlar');
    expect(_field(t, 'restaurants_m_address'), 'Gurlan, Navoiy 5');
    expect(_field(t, 'restaurants_m_contact_phone'), '998907654321');
    expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('venue-choice-chaikhana'))).selected, isTrue);
    expect(find.textContaining('restaurants_m_location_set'), findsOneWidget);
  });

  testWidgets('тўлдирилган форма юборилади; onRegistered табрикдан ОЛДИН ресторан ID билан; кейин панел «Меню» таби',
      (t) async {
    final repo = _Repo();
    await _open(
      t,
      RestaurantRegisterScreen(
        repository: repo,
        prefill: _prefill,
        onRegistered: (rid) async => repo.events.add('onRegistered:$rid'),
        panelInitialTab: RestaurantPanelScreen.menuTab,
      ),
    );
    await _submit(t);
    expect(_celebrationOk, findsOneWidget);
    expect(repo.events, ['register', 'onRegistered:r9'], reason: 'табрик чиққанда улаш аллақачон бажарилган');
    final p = repo.payload!;
    expect(p['name'], 'Gurlan osh');
    expect(p['description'], 'Milliy taomlar');
    expect(p['address'], 'Gurlan, Navoiy 5');
    expect(p['contactPhone'], '998907654321');
    expect([p['lat'], p['lng']], [41.84, 60.39]);
    expect(p['venueType'], 'chaikhana');
    expect(p['openingHours'], {'open': '08:00', 'close': '22:00'});

    await t.tap(_celebrationOk);
    await t.pumpAndSettle();
    final panel = t.widget<RestaurantPanelScreen>(find.byType(RestaurantPanelScreen));
    expect(panel.restaurantId, 'r9');
    expect(panel.initialTab, 1);
    expect(find.byType(RestaurantRegisterScreen), findsNothing);
  });

  testWidgets('onRegistered хато берса — огоҳлантириш, лекин ресторан очилган: табрик ва панелга ўтилади', (t) async {
    final repo = _Repo();
    await _open(
      t,
      RestaurantRegisterScreen(
        repository: repo,
        prefill: _prefill,
        onRegistered: (rid) async => throw StateError('link failed'),
        panelInitialTab: RestaurantPanelScreen.menuTab,
      ),
    );
    await _submit(t);
    expect(find.text('bizmap_menu_link_after_register_failed'), findsOneWidget);
    expect(find.textContaining('link failed'), findsNothing, reason: 'хом хато кўрсатилмайди');
    expect(_celebrationOk, findsOneWidget);
    await t.tap(_celebrationOk);
    await t.pumpAndSettle();
    expect(t.widget<RestaurantPanelScreen>(find.byType(RestaurantPanelScreen)).initialTab, 1);
  });

  testWidgets('олдиндан телефон бўш — профилдаги телефон (аввалги хулқ)', (t) async {
    await _open(
      t,
      RestaurantRegisterScreen(repository: _Repo(), prefill: const RestaurantRegisterPrefill(name: 'Gurlan osh')),
    );
    expect(_field(t, 'restaurants_m_name'), 'Gurlan osh');
    expect(_field(t, 'restaurants_m_contact_phone'), '998901111111');
  });

  testWidgets('параметрларсиз — аввалги хулқ: бўш форма, профил телефони', (t) async {
    await _open(t, RestaurantRegisterScreen(repository: _Repo(), homeCook: true));
    expect(_field(t, 'restaurants_m_name'), '');
    expect(_field(t, 'restaurants_m_address'), '');
    expect(_field(t, 'restaurants_m_contact_phone'), '998901111111');
    expect(find.text('restaurants_m_err_location'), findsOneWidget, reason: 'жой белгиланмаган');
  });

  testWidgets('onRegistered ва таб берилмаса — улашсиз, панел «Буюртмалар» табида (аввалги хулқ)', (t) async {
    final repo = _Repo();
    await _open(
      t,
      RestaurantRegisterScreen(
        repository: repo,
        homeCook: true,
        prefill: const RestaurantRegisterPrefill(name: 'Uy oshi', address: 'Gurlan', lat: 41.84, lng: 60.39),
      ),
    );
    await _submit(t);
    expect(repo.events, ['register']);
    expect(repo.payload!.containsKey('venueType'), isFalse, reason: 'уй ошпази — сервер home қўяди');
    await t.tap(_celebrationOk);
    await t.pumpAndSettle();
    expect(t.widget<RestaurantPanelScreen>(find.byType(RestaurantPanelScreen)).initialTab, 0);
  });
}
