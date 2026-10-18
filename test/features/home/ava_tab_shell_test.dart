import 'package:ava_gurlan/features/home/widgets/ava_bottom_nav.dart';
import 'package:ava_gurlan/features/home/widgets/ava_tab_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ҳолатли «Бош»: ҳисоблагич босилганда ўсади, tickers ҳолати ёзиб борилади.
class _Counter extends StatefulWidget {
  const _Counter(this.log);
  final List<String> log;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;

  @override
  Widget build(BuildContext context) {
    widget.log.add('home ticker=${TickerMode.valuesOf(context).enabled}');
    return GestureDetector(
      onTap: () => setState(() => n++),
      child: Center(child: Text('home:$n')),
    );
  }
}

/// Бошқа таб: яратилиши ва ўчирилиши ёзиб борилади.
class _Tab extends StatefulWidget {
  const _Tab(this.name, this.log);
  final String name;
  final List<String> log;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init ${widget.name}');
  }

  @override
  void dispose() {
    widget.log.add('dispose ${widget.name}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(child: Text('tab:${widget.name}'));
}

class _Host extends StatefulWidget {
  const _Host(this.log, this.backs);
  final List<String> log;
  final List<int> backs;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  AvaNavTab tab = AvaNavTab.home;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AvaTabShell(
        current: tab,
        home: _Counter(widget.log),
        tabBuilder: (_, t) => _Tab(t.name, widget.log),
        onBackToHome: () {
          widget.backs.add(1);
          setState(() => tab = AvaNavTab.home);
        },
      ),
      bottomNavigationBar: AvaBottomNav(
        current: tab,
        onTap: (t) {
          if (t == AvaNavTab.create) return;
          setState(() => tab = t);
        },
      ),
    );
  }
}

void main() {
  Future<void> pump(WidgetTester tester, List<String> log, List<int> backs) async {
    // `home` — pastdagi route; usti — ilova «ildizi» emas, shuning uchun
    // PopScope ishini tekshirish mumkin.
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => _Host(log, backs)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('«Бош» бошқа табга ўтганда ҳам тирик: ҳолат сақланади, тикерлар тўхтайди',
      (tester) async {
    final log = <String>[];
    await pump(tester, log, []);

    await tester.tap(find.text('home:0'));
    await tester.pump();
    expect(find.text('home:1'), findsOneWidget);

    await tester.tap(find.text('home_nav_messages'));
    await tester.pump();
    // «Бош» кўринмайди (Offstage), лекин ўчирилмаган.
    expect(find.text('home:1'), findsNothing);
    expect(find.text('home:1', skipOffstage: false), findsOneWidget);
    expect(log.lastWhere((e) => e.startsWith('home ticker')), 'home ticker=false');

    await tester.tap(find.text('home_nav_home'));
    await tester.pump();
    expect(find.text('home:1'), findsOneWidget, reason: 'ҳолат йўқолмаган');
    expect(log.lastWhere((e) => e.startsWith('home ticker')), 'home ticker=true');
  });

  testWidgets('бошқа таб танланганда яратилади, чиқилганда ЎЧИРИЛАДИ', (tester) async {
    final log = <String>[];
    await pump(tester, log, []);

    await tester.tap(find.text('home_nav_avagram'));
    await tester.pump();
    expect(find.text('tab:avagram'), findsOneWidget);
    expect(log.where((e) => e == 'init avagram'), hasLength(1));

    // Табдан табга: эскиси ўчади, янгиси яратилади.
    await tester.tap(find.text('home_nav_cabinet'));
    await tester.pump();
    // Flutter янги элементни ҚУРГАНДАН кейин эскисини ўчиради — тартиб муҳим эмас.
    expect(log, containsAll(['init avagram', 'dispose avagram', 'init cabinet']));
    expect(find.text('tab:avagram'), findsNothing);

    await tester.tap(find.text('home_nav_home'));
    await tester.pump();
    expect(log, contains('dispose cabinet'));
    expect(find.text('tab:cabinet'), findsNothing);
  });

  testWidgets('орқага: «Бош»дан бошқа табда аввал «Бош»га қайтади, route ёпилмайди',
      (tester) async {
    final log = <String>[];
    final backs = <int>[];
    await pump(tester, log, backs);

    await tester.tap(find.text('home_nav_messages'));
    await tester.pump();
    expect(find.text('tab:messages'), findsOneWidget);

    await tester.binding.handlePopRoute(); // система «орқага»
    await tester.pumpAndSettle();
    expect(backs, [1]);
    expect(find.text('home:0'), findsOneWidget);
    expect(find.text('open'), findsNothing, reason: 'route ёпилмаган — ҳали «Бош» таб');

    // «Бош»да «орқага» — route ёпилади (иловадан чиқишга тенг).
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(backs, [1], reason: '«Бош»да onBackToHome чақирилмайди');
  });

  testWidgets('клавиатура очиқ — меню яширилади', (tester) async {
    late bool hidden;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
        child: Builder(builder: (context) {
          hidden = avaNavHiddenByKeyboard(context);
          return const SizedBox();
        }),
      ),
    ));
    expect(hidden, isTrue);

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        hidden = avaNavHiddenByKeyboard(context);
        return const SizedBox();
      }),
    ));
    expect(hidden, isFalse);
  });
}
