import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/l10n/app_localizations.dart';
import 'package:ava_gurlan/main.dart';
import 'package:ava_gurlan/services/push_navigation.dart';
import 'package:ava_gurlan/shared/widgets/celebration_dialog.dart';
import 'package:ava_gurlan/shared/widgets/driver_application_feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Эга, 2026-10-31: ҳайдовчи аризаси тасдиқланганда табрик — телефон + тур учун БИР МАРТА.
/// Таржима: калитнинг ўзи (матн эмас, калит текширилади).
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('showDriverApprovedCelebrationOnce', () {
    /// Чақирувчи экран; қайтаради: натижа (ойна ҳали очиқ бўлса `null`).
    Future<bool? Function()> pumpCaller(WidgetTester t, {String phone = _phone, String? taxiType}) async {
      bool? shown;
      var done = false;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                shown = await showDriverApprovedCelebrationOnce(context, phone: phone, taxiType: taxiType);
                done = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ));
      return () => done ? shown : null;
    }

    testWidgets('биринчи марта: табрик (такси белгиси, сарлавҳа, изоҳ, «Давом этиш»); тугма ёпади → true',
        (t) async {
      final result = await pumpCaller(t, taxiType: 'intercity');
      await t.pump();
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('driver_request_approved_title'), findsOneWidget);
      expect(find.text('driver_request_approved_sub'), findsOneWidget);
      expect(find.text('celebration_continue'), findsOneWidget);
      expect(find.byIcon(Icons.local_taxi_rounded), findsOneWidget);
      expect(result(), isNull, reason: 'тугма босилгунча кутади');

      await t.tap(find.byKey(const ValueKey('celebration_ok')));
      await t.pumpAndSettle();
      expect(find.text('driver_request_approved_title'), findsNothing);
      expect(result(), isTrue);
    });

    testWidgets('иккинчи марта (шу телефон + тур): ойна йўқ → false (чақирувчи snack кўрсатади)', (t) async {
      SharedPreferences.setMockInitialValues({'celebrated_v1_driver_approved_998901112233_local': true});
      final result = await pumpCaller(t, taxiType: 'local');
      await t.pump();
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
      expect(result(), isFalse);
    });

    testWidgets('чегара: бошқа тур — мустақил (маршрут тасдиғи ҳам табрикланади)', (t) async {
      SharedPreferences.setMockInitialValues({'celebrated_v1_driver_approved_998901112233_local': true});
      final result = await pumpCaller(t, taxiType: 'marshrut');
      await t.pump();
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('driver_request_approved_title'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('celebration_ok')));
      await t.pumpAndSettle();
      expect(result(), isTrue);
    });

    testWidgets('чегара: тур номаълум — калит фақат телефон бўйича', (t) async {
      final result = await pumpCaller(t, taxiType: '  ');
      await t.pump();
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(const ValueKey('celebration_ok')));
      await t.pumpAndSettle();
      expect(result(), isTrue);
      expect(await CelebrationOnce.claim('driver_approved_998901112233'), isFalse, reason: 'белгиланган');
    });

    testWidgets('чегара: телефон номаълум — ойна йўқ → false', (t) async {
      final result = await pumpCaller(t, phone: '', taxiType: 'local');
      await t.pump();
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
      expect(result(), isFalse);
    });

    testWidgets('чегара: Navigator йўқ контекст — ойна йўқ → false, «бир марта» сарфланмайди', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(Localizations(
        locale: const Locale('en'),
        delegates: const [DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
        ),
      ));
      expect(await showDriverApprovedCelebrationOnce(ctx, phone: _phone, taxiType: 'local'), isFalse);
      expect(await CelebrationOnce.claim('driver_approved_998901112233_local'), isTrue);
    });
  });

  group('push: driver_request_approved (ҳайдовчи ҳуқуқи ҳали қурилмада йўқ)', () {
    Future<void> pumpApp(WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        navigatorKey: MyApp.navigatorKey,
        theme: AppTheme.light,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: const [
          _KeyL10nDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: Text('home')),
      ));
      await t.pump();
    }

    testWidgets('биринчи марта: табрик (snack ўрнида); «Давом этиш» ёпади', (t) async {
      SharedPreferences.setMockInitialValues({'user_phone': _phone, 'pending_driver_open': 'x'});
      await pumpApp(t);
      var finished = false;
      PushNavigation.handleData({'type': 'driver_request_approved', 'taxiType': 'intercity'})
          .then((_) => finished = true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('driver_request_approved_title'), findsOneWidget);
      expect(find.text('driver_request_approved_snack'), findsNothing);
      expect(finished, isFalse, reason: 'тугма босилгунча кутади');

      await t.tap(find.byKey(const ValueKey('celebration_ok')));
      await t.pumpAndSettle();
      expect(find.text('driver_request_approved_title'), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(finished, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_driver_open'), isNull);
      expect(prefs.getBool('celebrated_v1_driver_approved_998901112233_intercity'), isTrue);
    });

    testWidgets('иккинчи марта: ойна йўқ — аввалги snack', (t) async {
      SharedPreferences.setMockInitialValues({
        'user_phone': _phone,
        'celebrated_v1_driver_approved_998901112233_intercity': true,
      });
      await pumpApp(t);
      await PushNavigation.handleData({'type': 'driver_request_approved', 'taxiType': 'intercity'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
      expect(find.text('driver_request_approved_snack'), findsOneWidget);
      await t.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('чегара: телефон номаълум — ойна йўқ, snack', (t) async {
      SharedPreferences.setMockInitialValues({});
      await pumpApp(t);
      await PushNavigation.handleData({'type': 'driver_request_approved'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
      expect(find.text('driver_request_approved_snack'), findsOneWidget);
      await t.pumpAndSettle(const Duration(seconds: 4));
    });
  });
}
