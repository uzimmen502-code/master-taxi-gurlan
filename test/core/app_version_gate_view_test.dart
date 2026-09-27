import 'package:ava_gurlan/core/app_version_gate.dart';
import 'package:ava_gurlan/core/widgets/app_version_gate_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Дарвоза ИЛОВА ДАРАХТИДА тўғри уланганми.
///
/// `app_version_gate_test.dart` фақат мантиқни текширади. Бу ерда эса
/// асосий савол: мажбурий янгилашда илова ҳақиқатан кўринмай қоладими.
/// Агар [AppVersionGateView] болани барибир чизса, дарвоза «ишлаяпти»
/// деб кўринади, аслида эса ҳеч нарсани тўхтатмайди.
Future<void> _pump(WidgetTester tester) async {
  // Локализация делегати АТАЙЛАБ уланмаган: `AppLocalizations.tr`
  // таржима топилмаса калитнинг ўзини қайтаради, бу эса тестда
  // текширишга қулай ва илова тилидан мустақил.
  await tester.pumpWidget(
    const MaterialApp(
      home: AppVersionGateView(
        child: Text('ИЛОВА'),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(AppVersionGate.resetForTest);
  tearDown(AppVersionGate.resetForTest);

  testWidgets('мажбурий янгилаш — илова КЎРИНМАЙДИ', (tester) async {
    AppVersionGate.setForTest(currentBuild: 67, minSupportedBuild: 70);
    await _pump(tester);

    expect(find.text('ИЛОВА'), findsNothing);
    expect(find.byType(ForceUpdateScreen), findsOneWidget);
  });

  testWidgets('версия ярайди — илова одатдагидек', (tester) async {
    AppVersionGate.setForTest(currentBuild: 70, minSupportedBuild: 70);
    await _pump(tester);

    expect(find.text('ИЛОВА'), findsOneWidget);
    expect(find.byType(ForceUpdateScreen), findsNothing);
  });

  testWidgets('конфиг йўқ — илова одатдагидек', (tester) async {
    // Энг кенг тарқалган ҳолат: `config/app_version` ҳали яратилмаган.
    AppVersionGate.setForTest(currentBuild: 70);
    await _pump(tester);

    expect(find.text('ИЛОВА'), findsOneWidget);
  });

  testWidgets('сервер матни бўлса — ўша кўрсатилади', (tester) async {
    AppVersionGate.setForTest(
      currentBuild: 67,
      minSupportedBuild: 70,
      serverMessage: 'Тўлов тизими янгиланди',
    );
    await _pump(tester);

    expect(find.text('Тўлов тизими янгиланди'), findsOneWidget);
  });

  testWidgets('сервер матни бўш — локал таржима', (tester) async {
    AppVersionGate.setForTest(currentBuild: 67, minSupportedBuild: 70);
    await _pump(tester);

    // Тест муҳитида таржима юкланмайди, `tr()` калитнинг ўзини
    // қайтаради — бизга кифоя: матн манбаи алмашгани кўриняпти.
    expect(find.text('update_required_body'), findsOneWidget);
    expect(find.text('update_required_button'), findsOneWidget);
  });

  testWidgets('конфиг келганда экран ЎЗИ алмашади', (tester) async {
    // Тармоқ жавоби splash'дан кейин келади. Ўшанда илова қайта ишга
    // туширилмайди — `revision` orqali o'zi almashishi kerak.
    AppVersionGate.setForTest(currentBuild: 67);
    await _pump(tester);
    expect(find.text('ИЛОВА'), findsOneWidget);

    AppVersionGate.setForTest(currentBuild: 67, minSupportedBuild: 70);
    AppVersionGate.revision.value++;
    await tester.pump();

    expect(find.text('ИЛОВА'), findsNothing);
    expect(find.byType(ForceUpdateScreen), findsOneWidget);
  });
}
