import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/repositories/user_repository.dart';
import 'package:ava_gurlan/shared/car/car_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Автомобиль ойнаси Кабинетдан чиқарилди (эга, 2026-10-16): энди ҳайдовчи
/// панели ва онбординг оқимлари шу ердан чақиради. Фирестор ўрнига қўлда
/// ёзилган сохта репозиторий; қолган ҳар қандай чақирув тест хатоси.
class _FakeUserRepo implements UserRepository {
  _FakeUserRepo({this.car});

  Map<String, String>? car;
  bool failSave = false;
  bool failClear = false;
  final saved = <Map<String, Object>>[];
  final cleared = <String>[];

  @override
  Future<Map<String, String>?> getCarInfo(String uid) async => car;

  @override
  Future<void> saveCarInfo({
    required String uid,
    required String carModel,
    required String carColor,
    required String carPlate,
    required int carSeats,
    String carBrand = '',
    int carYear = 0,
    String carEngine = '',
    String carFuelType = '',
    List<String> carUsageTags = const [],
  }) async {
    if (failSave) throw StateError('save');
    saved.add({
      'uid': uid,
      'model': carModel,
      'color': carColor,
      'plate': carPlate,
      'seats': carSeats,
    });
  }

  @override
  Future<void> clearCarInfo(String uid) async {
    if (failClear) throw StateError('clear');
    cleared.add(uid);
    car = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _host(WidgetTester t, Future<void> Function(BuildContext) onTap) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(onPressed: () => onTap(context), child: const Text('go')),
      ),
    ),
  ));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
}

void main() {
  group('showCarEditDialog', () {
    testWidgets('мавжуд маълумот майдонларга тўлади, сақлаш — тўғри қийматлар билан', (t) async {
      final repo = _FakeUserRepo(car: {
        'carModel': 'Cobalt',
        'carColor': 'Oq',
        'carPlate': '01A123BC',
        'carSeats': '4',
      });
      bool? result;
      await _host(t, (c) async {
        result = await showCarEditDialog(c, uid: '998901234567', repository: repo);
      });
      expect(find.text('Cobalt'), findsOneWidget);
      expect(find.text('01A123BC'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, 'Oq'), 'Qora');
      await t.tap(find.text('save'));
      await t.pumpAndSettle();
      expect(result, isTrue);
      expect(repo.saved, hasLength(1));
      expect(repo.saved.single['color'], 'Qora');
      expect(repo.saved.single['uid'], '998901234567');
    });

    testWidgets('бўш майдон билан сақланмайди (ойна очиқ қолади)', (t) async {
      final repo = _FakeUserRepo();
      bool? result;
      await _host(t, (c) async {
        result = await showCarEditDialog(c, uid: '998901234567', repository: repo);
      });
      await t.tap(find.text('save'));
      await t.pumpAndSettle();
      expect(repo.saved, isEmpty);
      expect(find.text('car_info_edit'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('сақлаш хатоси — false қайтади ва «error_generic» чиқади', (t) async {
      final repo = _FakeUserRepo(car: {
        'carModel': 'Cobalt',
        'carColor': 'Oq',
        'carPlate': '01A123BC',
        'carSeats': '4',
      })..failSave = true;
      bool? result;
      await _host(t, (c) async {
        result = await showCarEditDialog(c, uid: '998901234567', repository: repo);
      });
      await t.tap(find.text('save'));
      await t.pumpAndSettle();
      expect(result, isFalse);
      expect(find.text('error_generic'), findsOneWidget);
    });

    testWidgets('онбординг (driverFlow): ташқарига босиш ойнани ёпмайди', (t) async {
      final repo = _FakeUserRepo();
      await _host(t, (c) async {
        await showCarEditDialog(c, uid: '998901234567', driverFlow: true, repository: repo);
      });
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(find.text('car_info_edit'), findsOneWidget);
    });
  });

  group('confirmAndDeleteCar', () {
    testWidgets('тасдиқдан кейин ўчиради', (t) async {
      final repo = _FakeUserRepo(car: {'carModel': 'Cobalt'});
      bool? result;
      await _host(t, (c) async {
        result = await confirmAndDeleteCar(c, uid: '998901234567', repository: repo);
      });
      expect(find.text('car_delete_confirm_title'), findsOneWidget);
      await t.tap(find.text('delete'));
      await t.pumpAndSettle();
      expect(result, isTrue);
      expect(repo.cleared, ['998901234567']);
      expect(find.text('car_deleted_success'), findsOneWidget);
    });

    testWidgets('бекор қилинса ҲЕЧ НАРСА ўчмайди', (t) async {
      final repo = _FakeUserRepo(car: {'carModel': 'Cobalt'});
      bool? result;
      await _host(t, (c) async {
        result = await confirmAndDeleteCar(c, uid: '998901234567', repository: repo);
      });
      await t.tap(find.text('cancel'));
      await t.pumpAndSettle();
      expect(result, isFalse);
      expect(repo.cleared, isEmpty);
      expect(repo.car, isNotNull);
    });

    testWidgets('ўчириш хатоси — false ва «error_generic» (муваффақият хабари йўқ)', (t) async {
      final repo = _FakeUserRepo(car: {'carModel': 'Cobalt'})..failClear = true;
      bool? result;
      await _host(t, (c) async {
        result = await confirmAndDeleteCar(c, uid: '998901234567', repository: repo);
      });
      await t.tap(find.text('delete'));
      await t.pumpAndSettle();
      expect(result, isFalse);
      expect(find.text('error_generic'), findsOneWidget);
      expect(find.text('car_deleted_success'), findsNothing);
    });
  });
}
