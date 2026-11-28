// «Туғилган кунингизни киритинг» пуши (4 кун кунига бир марта → 7 кун танаффус → ҳар якшанба) (эга 2026-11-28, сервер functions/birthday_prompt.js):
// push/«Хабарлар» йўналиши, админ созлама модели ва текшируви, админ таби (юклаш, хато, сақлаш, версия).
import 'package:ava_gurlan/features/admin_web/screens/holiday_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_birthday_prompt_service.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_holiday_service.dart';
import 'package:ava_gurlan/features/admin_web/widgets/birthday_prompt_admin_panel.dart';
import 'package:ava_gurlan/features/profile/domain/birthday_prompt_push.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_holiday.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_taxonomy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _k(String k) => find.byKey(ValueKey(k));

class _FakePromptApi implements AdminBirthdayPromptApi {
  _FakePromptApi(this.state);

  BirthdayPromptAdminState state;
  final saved = <(BirthdayPromptSettings, int, String)>[];
  bool failLoad = false;

  @override
  Future<BirthdayPromptAdminState> load() async {
    if (failLoad) throw Exception('offline');
    return state;
  }

  @override
  Future<void> save(BirthdayPromptSettings s, {required int expectedVersion, String reason = ''}) async {
    saved.add((s, expectedVersion, reason));
    state = BirthdayPromptAdminState(
      settings: BirthdayPromptSettings(
          stage: s.stage, internalPhones: s.internalPhones, pilotDistrictIds: s.pilotDistrictIds,
          dailyCount: s.dailyCount,
          weeklySunday: s.weeklySunday,
          version: expectedVersion + 1),
      runs: state.runs,
    );
  }
}

class _NoHolidayApi implements AdminHolidayApi {
  @override
  Future<List<HolidayOccasion>> loadOccasions() async => const [];
  @override
  Future<List<HolidayBasket>> loadBaskets() async => const [];
  @override
  Future<Map<String, FamilyBonusProgram?>> loadFamilyPrograms() async => const {};
  @override
  Future<void> saveOccasion(HolidayOccasion o, {String reason = ''}) async {}
  @override
  Future<void> saveBasket(HolidayBasket b, {String reason = ''}) async {}
  @override
  Future<void> saveFamilyProgram(String programId, FamilyBonusProgram p, {String reason = ''}) async {}
}

void main() {
  group('push / «Хабарлар» йўналиши', () {
    test('birthday_prompt тури ёки user_info экрани — туғилган сана экрани', () {
      expect(opensBirthDateEntry(type: 'birthday_prompt'), isTrue);
      expect(opensBirthDateEntry(type: ' birthday_prompt '), isTrue);
      expect(opensBirthDateEntry(screen: 'user_info'), isTrue);
      expect(opensBirthDateEntry(type: 'birthday_prompt', screen: 'user_info'), isTrue);
    });
    test('бошқа хабарлар — йўқ (байрам, ўз туғилган куни, бўш)', () {
      expect(opensBirthDateEntry(), isFalse);
      expect(opensBirthDateEntry(type: 'holiday_self_birthday', screen: 'supermarket'), isFalse);
      expect(opensBirthDateEntry(type: 'holiday_reminder'), isFalse);
      expect(opensBirthDateEntry(type: 'general', screen: 'news'), isFalse);
      expect(opensBirthDateEntry(type: 'birthday_bonus'), isFalse);
    });
    test('сервер қийматлари билан бир хил (functions/birthday_prompt.js SOURCE/SCREEN)', () {
      expect(kBirthdayPromptType, 'birthday_prompt');
      expect(kBirthdayPromptScreen, 'user_info');
    });
  });

  group('админ созлама модели', () {
    test('fromMap: йўқ/бузуқ — OFF, сукут 4 кун + якшанба ёқиқ; toMap — фақат сервер калитлари', () {
      final empty = BirthdayPromptAdminState.fromMap(const {});
      expect(empty.settings.stage, 'off');
      expect(empty.settings.dailyCount, kBirthdayPromptDefaultDailyCount);
      expect(kBirthdayPromptDefaultDailyCount, 4);
      expect(empty.settings.weeklySunday, isTrue);
      expect(empty.runs, isEmpty);
      final st = BirthdayPromptAdminState.fromMap({
        'settings': {'stage': 'internal', 'internalPhones': ['998901234567'], 'pilotDistrictIds': [], 'dailyCount': 6, 'weeklySunday': false, 'maxSends': 9, 'version': 3},
        'runs': [
          {'id': '2026-11-30_internal', 'day': '2026-11-30', 'week': '2026-W49', 'stage': 'internal', 'done': true, 'stats': {'sent': 2, 'scanned': 5, 'x': 'bad'}},
          'junk',
        ],
      });
      expect(st.settings.version, 3);
      expect(st.settings.dailyCount, 6);
      expect(st.settings.weeklySunday, isFalse);
      expect(st.settings.toMap().keys.toSet(), {'stage', 'internalPhones', 'pilotDistrictIds', 'dailyCount', 'weeklySunday'});
      expect(st.runs.single.stats, {'sent': 2, 'scanned': 5});
      expect(st.runs.single.day, '2026-11-30');
      expect(BirthdayPromptSettings.fromMap(const {'stage': 'weird'}).stage, 'off');
    });

    test('текширув: позитив, чегаралар (1/14), негатив', () {
      const ok = BirthdayPromptSettings(stage: 'internal', internalPhones: ['998901234567'], dailyCount: 4);
      expect(birthdayPromptProblems(ok), isEmpty);
      expect(birthdayPromptProblems(const BirthdayPromptSettings(stage: 'public', dailyCount: 1)), isEmpty);
      expect(birthdayPromptProblems(const BirthdayPromptSettings(stage: 'public', dailyCount: 14, weeklySunday: false)), isEmpty);
      expect(birthdayPromptProblems(const BirthdayPromptSettings(stage: 'public', dailyCount: 0)), isNotEmpty);
      expect(birthdayPromptProblems(const BirthdayPromptSettings(stage: 'public', dailyCount: 15)), isNotEmpty);
      expect(birthdayPromptProblems(const BirthdayPromptSettings(stage: 'on')), isNotEmpty);
      expect(birthdayPromptProblems(const BirthdayPromptSettings(internalPhones: ['901234567'])), isNotEmpty);
      expect(birthdayPromptProblems(const BirthdayPromptSettings(internalPhones: ['998901234567', '998901234567'])), isNotEmpty);
      expect(birthdayPromptProblems(const BirthdayPromptSettings(pilotDistrictIds: ['Gurlan'])), isNotEmpty);
      expect(birthdayPromptProblems(const BirthdayPromptSettings(stage: 'pilot')), isNotEmpty);
      expect(birthdayPromptProblems(const BirthdayPromptSettings(stage: 'pilot', pilotDistrictIds: ['gurlan'])), isEmpty);
    });
  });

  group('админ таби', () {
    testWidgets('юклайди, нотўғри рақам — сақламайди; тўғри — версия билан сақлайди ва қайта юклайди', (t) async {
      final api = _FakePromptApi(const BirthdayPromptAdminState(
        settings: BirthdayPromptSettings(version: 2),
        runs: [BirthdayPromptRun(id: '2026-11-30_internal', day: '2026-11-30', week: '2026-W49', stage: 'internal', done: true, stats: {'sent': 3})],
      ));
      await t.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: BirthdayPromptAdminPanel(api: api))));
      await t.pumpAndSettle();
      expect(find.text('Сақлаш (версия 2)'), findsOneWidget);
      expect(_k('bp_admin_run_2026-11-30_internal'), findsOneWidget);
      expect(find.textContaining('2026-11-30 ·'), findsOneWidget);
      expect(t.widget<TextField>(_k('bp_admin_daily')).controller!.text, '4');
      expect(t.widget<SwitchListTile>(_k('bp_admin_weekly')).value, isTrue);

      await t.tap(_k('bp_admin_stage'));
      await t.pumpAndSettle();
      await t.tap(find.text('Ички синов (фақат рақамлар)').last);
      await t.pumpAndSettle();
      await t.enterText(_k('bp_admin_internal'), '901234567');
      await t.tap(_k('bp_admin_save'));
      await t.pumpAndSettle();
      expect(api.saved, isEmpty);
      expect(find.textContaining('998XXXXXXXXX'), findsOneWidget);

      await t.enterText(_k('bp_admin_internal'), '998901234567, 998901234568');
      await t.enterText(_k('bp_admin_daily'), '15');
      await t.tap(_k('bp_admin_save'));
      await t.pumpAndSettle();
      expect(api.saved, isEmpty);
      expect(find.textContaining('Кунлик эслатмалар сони'), findsOneWidget);

      await t.enterText(_k('bp_admin_daily'), '6');
      await t.tap(_k('bp_admin_weekly'));
      await t.pumpAndSettle();
      await t.tap(_k('bp_admin_save'));
      await t.pumpAndSettle();
      expect(api.saved, hasLength(1));
      final (s, ver, _) = api.saved.single;
      expect(ver, 2);
      expect(s.stage, 'internal');
      expect(s.internalPhones, ['998901234567', '998901234568']);
      expect(s.dailyCount, 6);
      expect(s.weeklySunday, isFalse);
      expect(find.text('Сақлаш (версия 3)'), findsOneWidget);
      expect(find.text('Сақланди.'), findsOneWidget);
    });

    testWidgets('юклаш хатоси — хабар ва «Қайта уриниш»', (t) async {
      final api = _FakePromptApi(const BirthdayPromptAdminState(settings: BirthdayPromptSettings()))..failLoad = true;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: BirthdayPromptAdminPanel(api: api))));
      await t.pumpAndSettle();
      expect(find.textContaining('Юклаб бўлмади'), findsOneWidget);
      api.failLoad = false;
      await t.tap(find.text('Қайта уриниш'));
      await t.pumpAndSettle();
      expect(find.text('Сақлаш (версия 0)'), findsOneWidget);
    });

    testWidgets('«Байрам саватчаси» админида 4-таб «Туғилган кун эслатмаси»', (t) async {
      final api = _FakePromptApi(const BirthdayPromptAdminState(settings: BirthdayPromptSettings(stage: 'public', version: 7)));
      await t.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HolidayAdminScreen(
            api: _NoHolidayApi(),
            loadTaxonomy: () async => SmTaxonomy.empty,
            loadOffers: (_) async => const [],
            birthdayPromptApi: api,
          ),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('Туғилган кун эслатмаси'));
      await t.pumpAndSettle();
      expect(find.text('Сақлаш (версия 7)'), findsOneWidget);
    });
  });
}
