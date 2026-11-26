// Оила боғланиши (эга 2026-11-28, G/H/I/J): модел, форма, экран (қабул/рад, турмуш ўртоғи, қариндош, ажратиш),
// рўйхатдан кейинги таклиф (3 тугма), админ дастурлари, l10n, overflow.
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/admin_web/screens/holiday_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_holiday_service.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_incentives_service.dart';
import 'package:ava_gurlan/features/relatives/data/family_links_repository.dart';
import 'package:ava_gurlan/features/relatives/screens/family_links_screen.dart';
import 'package:ava_gurlan/features/relatives/widgets/family_prompt.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_holiday.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_taxonomy.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _k(String k) => find.byKey(ValueKey(k));

Widget _app(Widget home, {double textScale = 1}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

final _raw = {
  'incoming': [
    {'inviteId': '998901_998902', 'kind': 'spouse', 'relation': 'spouse', 'fromName': 'Ali'},
    {'inviteId': '998903_998902', 'kind': 'relative', 'relation': 'son', 'fromName': 'Vali'},
    {'inviteId': '', 'kind': 'spouse'},
  ],
  'outgoing': [
    {'inviteId': '998902_998904', 'kind': 'relative', 'relation': 'mother', 'name': 'Ona', 'status': 'pending'},
    {'inviteId': '998902_998905', 'kind': 'relative', 'relation': 'brother', 'name': 'Aka', 'status': 'declined'},
  ],
  'links': [
    {'pairKey': '998902_998906', 'kind': 'relative', 'relation': 'father', 'name': 'Ota'},
  ],
  'programs': {
    'spouse': {'active': true, 'amount': 10000, 'validityDays': 30},
    'relative': {'active': true, 'amount': 5000, 'validityDays': 30, 'parents': 2, 'siblings': 15},
  },
};

class _Api implements FamilyLinksApi {
  _Api(this.state);
  FamilyState state;
  final calls = <String>[];
  Object? fail;

  @override
  Future<FamilyState> load() async => state;

  @override
  Future<void> inviteSpouse({required String name, required String birthDate, required String phone, String personId = ''}) async {
    if (fail != null) throw fail!;
    calls.add('spouse:$name:$birthDate:$phone');
  }

  @override
  Future<void> inviteRelative({required String name, required String phone, required String relation, String birthDate = '', String personId = ''}) async =>
      calls.add('relative:$name:$phone:$relation:$birthDate');

  @override
  Future<String> respond(FamilyInvite invite, {required bool accept}) async {
    calls.add('respond:${invite.inviteId}:$accept');
    return accept ? 'accepted' : 'declined';
  }

  @override
  Future<void> unlink(FamilyLink link) async => calls.add('unlink:${link.pairKey}');
}

class _Admin implements AdminHolidayApi {
  final saved = <(String, FamilyBonusProgram)>[];
  @override
  Future<List<HolidayOccasion>> loadOccasions() async => const [];
  @override
  Future<List<HolidayBasket>> loadBaskets() async => const [];
  @override
  Future<Map<String, FamilyBonusProgram?>> loadFamilyPrograms() async => {
        'spouse_link': null,
        'relative_link': FamilyBonusProgram.fromMap({'stage': 'internal', 'amount': 5000, 'maxParents': 2, 'maxSiblings': 15, 'budgetTotal': 100000, 'title': {'uz_Cyrl': 'Қ', 'uz_Latn': 'Q', 'ru': 'Р'}}),
      };
  @override
  Future<void> saveOccasion(HolidayOccasion o, {String reason = ''}) async {}
  @override
  Future<void> saveBasket(HolidayBasket b, {String reason = ''}) async {}
  @override
  Future<void> saveFamilyProgram(String programId, FamilyBonusProgram p, {String reason = ''}) async => saved.add((programId, p));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('модел ва қоидалар', () {
    test('getMyFamilyLinks жавоби: бузуғи ташланади; турмуш ўртоғи/қариндошлар; дастурлар ва чегаралар', () {
      final s = FamilyState.fromMap(_raw);
      expect(s.incoming.map((i) => i.inviteId), ['998901_998902', '998903_998902']);
      expect(s.spouse, isNull);
      expect(s.relatives.single.relation, 'father');
      expect(s.relativeInvites.map((i) => i.status), ['pending', 'declined']);
      expect([s.spouseProgram.amount, s.relativeProgram.maxParents, s.relativeProgram.maxSiblings], [10000, 2, 15]);
      expect(FamilyState.fromMap({'programs': {'spouse': {'active': false, 'amount': 1}}}).anyProgramActive, isFalse);
      expect(FamilyState.fromMap(null).links, isEmpty);
    });

    test('форма: исм, телефон (+998/9 хона), турмуш ўртоғида сана шарт', () {
      expect(familyInviteProblems(name: 'Ali', phone: '+998 90 123 45 67', birthDate: '1990-01-01', spouse: true), isEmpty);
      expect(familyInviteProblems(name: 'Ali', phone: '901234567'), isEmpty);
      expect(familyInviteProblems(name: '', phone: '123', spouse: true), ['fam_err_name', 'fam_err_phone', 'fam_err_birth']);
      expect(kFamilyRelativeRelations, ['father', 'mother', 'brother', 'sister', 'son', 'daughter']);
    });

    test('сервер хатоси → калит; йўл: таклиф → экран, бонус → супермаркет; таклиф кунига бир текширилади, бир марта кўрсатилади', () {
      expect(familyErrorKey(FirebaseFunctionsException(code: 'failed-precondition', message: 'x', details: {'code': 'CAP_REACHED'})), 'fam_err_CAP_REACHED');
      expect(familyErrorKey(FirebaseFunctionsException(code: 'internal', message: 'x', details: {'code': 'WHAT'})), 'fam_err_generic');
      expect(familyErrorKey(Exception('x')), 'fam_err_generic');
      expect(familyRouteOf('family_invite'), 'links');
      expect(familyRouteOf('family_link'), 'links');
      expect(familyRouteOf('family_bonus'), 'supermarket');
      expect(familyRouteOf('holiday_reminder'), isNull);
      expect(familyPromptDue(shown: false, checkedDay: '', today: '2026-11-28'), isTrue);
      expect(familyPromptDue(shown: false, checkedDay: '2026-11-28', today: '2026-11-28'), isFalse);
      expect(familyPromptDue(shown: true, checkedDay: '', today: '2026-11-28'), isFalse);
      expect(incentiveProgramLocked('spouse_link', const {}), isTrue);
      expect(incentiveProgramLocked('x', const {'kind': 'relative_link'}), isTrue);
    });
  });

  group('экран', () {
    Future<_Api> pump(WidgetTester t, Map<String, Object?> raw, {String focus = ''}) async {
      await t.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = _Api(FamilyState.fromMap(raw));
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_app(FamilyLinksScreen(api: api, focus: focus)));
      await t.pumpAndSettle();
      return api;
    }

    testWidgets('кирувчи таклиф: қабул / рад; бонус изоҳлари; прогресс', (t) async {
      final api = await pump(t, _raw);
      expect(_k('fam_incoming_998901_998902'), findsOneWidget);
      expect(_k('fam_spouse_bonus'), findsOneWidget);
      expect(_k('fam_relative_bonus'), findsOneWidget);
      expect(find.text('fam_relatives_progress'), findsOneWidget);
      await t.tap(_k('fam_accept_998901_998902'));
      await t.pumpAndSettle();
      await t.tap(_k('fam_decline_998903_998902'));
      await t.pumpAndSettle();
      expect(api.calls, ['respond:998901_998902:true', 'respond:998903_998902:false']);
    });

    testWidgets('турмуш ўртоғи: форма текшируви, сана ISO шаклида; сервер хатоси — snackbar', (t) async {
      final api = await pump(t, {..._raw, 'incoming': const []});
      await t.tap(_k('fam_spouse_invite'));
      await t.pump();
      expect(_k('fam_problem_fam_err_name'), findsOneWidget);
      expect(_k('fam_problem_fam_err_birth'), findsOneWidget);
      await t.enterText(_k('fam_spouse_name'), 'Malika');
      await t.enterText(_k('fam_spouse_birth'), '12.12.1992');
      await t.enterText(_k('fam_spouse_phone'), '+998 91 200 00 02');
      await t.tap(_k('fam_spouse_invite'));
      await t.pumpAndSettle();
      expect(api.calls, ['spouse:Malika:1992-12-12:+998 91 200 00 02']);
      api.fail = FirebaseFunctionsException(code: 'resource-exhausted', message: 'x', details: {'code': 'RATE_LIMITED'});
      await t.tap(_k('fam_spouse_invite'));
      await t.pumpAndSettle();
      expect(find.text('fam_err_RATE_LIMITED'), findsOneWidget);
    });

    testWidgets('боғланган турмуш ўртоғи: ажратиш — тасдиқ билан; кутаётган таклиф ҳолати', (t) async {
      final api = await pump(t, {
        'links': [
          {'pairKey': '998901_998902', 'kind': 'spouse', 'relation': 'spouse', 'name': 'Malika'},
        ],
      });
      expect(_k('fam_spouse_linked'), findsOneWidget);
      expect(_k('fam_spouse_invite'), findsNothing);
      await t.tap(_k('fam_spouse_unlink'));
      await t.pumpAndSettle();
      await t.tap(_k('fam_unlink_ok'));
      await t.pumpAndSettle();
      expect(api.calls, ['unlink:998901_998902']);
      await pump(t, {
        'outgoing': [
          {'inviteId': '998902_998901', 'kind': 'spouse', 'relation': 'spouse', 'name': 'Malika', 'status': 'pending'},
        ],
      });
      expect(_k('fam_spouse_pending'), findsOneWidget);
    });

    testWidgets('қариндош қўшиш (focus=relatives): муносабат танлови → inviteRelative', (t) async {
      final api = await pump(t, const {}, focus: 'relatives');
      expect(_k('fam_rel_send'), findsOneWidget);
      await t.tap(_k('fam_rel_relation'));
      await t.pumpAndSettle();
      await t.tap(find.text('fam_rel_mother').last);
      await t.pumpAndSettle();
      await t.enterText(_k('fam_rel_name'), 'Ona');
      await t.enterText(_k('fam_rel_phone'), '901234567');
      await t.enterText(_k('fam_rel_birth'), '1.3.1965');
      await t.tap(_k('fam_rel_send'));
      await t.pumpAndSettle();
      expect(api.calls, ['relative:Ona:901234567:mother:1965-03-01']);
    });
  });

  group('рўйхатдан кейинги таклиф', () {
    testWidgets('3 тугма; «Оила қурмаганман» → ота-она/ака-ука изоҳи → қариндошлар; «Кейинроқ»', (t) async {
      String? result;
      await t.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<String>(context: context, builder: (_) => FamilyPromptDialog(state: FamilyState.fromMap(_raw))),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(_k('fam_prompt_spouse'), findsOneWidget);
      expect(_k('fam_prompt_single'), findsOneWidget);
      expect(_k('fam_prompt_later'), findsOneWidget);
      await t.tap(_k('fam_prompt_single'));
      await t.pumpAndSettle();
      expect(find.text('fam_prompt_single_body'), findsOneWidget);
      await t.tap(_k('fam_prompt_relatives'));
      await t.pumpAndSettle();
      expect(result, 'relatives');
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(_k('fam_prompt_later'));
      await t.pumpAndSettle();
      expect(result, 'later');
    });

    testWidgets('дастур фаол эмас — кўрсатилмайди; фаол — бир марта (оилавий ҳолат ёзилмайди)', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_app(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      await maybeShowFamilyPrompt(ctx, api: _Api(FamilyState.fromMap(const {})), now: DateTime(2026, 11, 28));
      await t.pumpAndSettle();
      expect(_k('fam_prompt'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFamilyPromptShownKey), isNull);
      unawaitedPrompt() => maybeShowFamilyPrompt(ctx, api: _Api(FamilyState.fromMap(_raw)), now: DateTime(2026, 11, 29));
      unawaitedPrompt();
      await t.pumpAndSettle();
      expect(_k('fam_prompt'), findsOneWidget);
      await t.tap(_k('fam_prompt_later'));
      await t.pumpAndSettle();
      expect(prefs.getBool(kFamilyPromptShownKey), isTrue);
      expect(prefs.getKeys().where((k) => k.contains('marital') || k.contains('single')), isEmpty);
      unawaitedPrompt();
      await t.pumpAndSettle();
      expect(_k('fam_prompt'), findsNothing, reason: 'бир марта');
    });
  });

  testWidgets('админ: «Оила бонуслари» — 2 дастур; қариндошлар чегаралари; текширув; сақлаш', (t) async {
    final api = _Admin();
    await t.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_app(Scaffold(body: HolidayAdminScreen(api: api, loadTaxonomy: () async => SmTaxonomy.empty, loadOffers: (_) async => const []))));
    await t.pumpAndSettle();
    await t.tap(find.text('Оила бонуслари'));
    await t.pumpAndSettle();
    expect(_k('hb_admin_family_spouse_link'), findsOneWidget);
    expect(_k('hb_admin_family_relative_link'), findsOneWidget);
    await t.tap(_k('hb_admin_family_relative_link'));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(_k('hb_admin_family_siblings')).controller!.text, '15');
    await t.enterText(_k('hb_admin_family_siblings'), '51');
    await t.tap(_k('hb_admin_family_save'));
    await t.pumpAndSettle();
    expect(api.saved, isEmpty);
    await t.enterText(_k('hb_admin_family_siblings'), '15');
    await t.tap(_k('hb_admin_family_save'));
    await t.pumpAndSettle();
    expect(api.saved.single.$1, 'relative_link');
    expect(api.saved.single.$2.toMap('relative_link')['maxSiblings'], 15);
    expect(api.saved.single.$2.toMap('spouse_link').containsKey('maxSiblings'), isFalse);
    await t.tap(_k('hb_admin_family_spouse_link'));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(_k('hb_admin_family_amount')).controller!.text, '10000', reason: 'сукут 10 000');
    expect(_k('hb_admin_family_siblings'), findsNothing);
    expect(familyBonusProblems('relative_link', const FamilyBonusProgram(maxParents: 11)), contains('Ота-она чегараси 0–10.'));
  });

  test('fam_* калитлари 3 тилда; uz_Latn янги алифбода', () {
    final maps = {for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) l: jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>};
    final keys = {for (final k in maps['uz_Cyrl']!.keys) if (k.startsWith('fam_')) k};
    expect(keys.length, greaterThanOrEqualTo(60));
    for (final l in ['uz_Latn', 'ru']) {
      expect({for (final k in maps[l]!.keys) if (k.startsWith('fam_')) k}, keys, reason: l);
    }
    for (final k in keys) {
      for (final l in maps.keys) {
        expect((maps[l]![k] as String).trim(), isNotEmpty, reason: '$l $k');
      }
      expect(RegExp(r"o'|g'|o‘|g‘|sh|ch", caseSensitive: false).hasMatch(maps['uz_Latn']![k] as String), isFalse, reason: k);
      expect(RegExp(r'[a-z]').hasMatch((maps['uz_Cyrl']![k] as String).replaceAll(RegExp(r'\{\w+\}'), '')), isFalse, reason: 'uz_Cyrl $k');
    }
    expect(maps['uz_Cyrl']!['fam_prompt_single_body'], startsWith('Ота-онангиз, ака-укангиз, опа-сингилларингизнинг'));
  });

  group('катта шрифт 1.5 / 320 px — overflow йўқ', () {
    for (final e in {'screen': _raw, 'linked': {'links': [{'pairKey': '1_2', 'kind': 'spouse', 'relation': 'spouse', 'name': 'Juda uzun ism familiya otasining ismi'}]}}.entries) {
      testWidgets(e.key, (t) async {
        await t.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(_app(FamilyLinksScreen(api: _Api(FamilyState.fromMap(e.value))), textScale: 1.5));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.drag(find.byType(ListView).first, const Offset(0, -3000));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
    testWidgets('таклиф ойнаси', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(Scaffold(body: FamilyPromptDialog(state: FamilyState.fromMap(_raw))), textScale: 1.5));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
