import 'package:ava_gurlan/features/home/widgets/ava_bottom_nav.dart';
import 'package:ava_gurlan/features/home/widgets/ava_tab_shell.dart';
import 'package:ava_gurlan/features/tv_market/widgets/tv_feed_empty_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// AVAGram бўш/хато ҳолати: тармоқ хатоси «видео йўқ» деб кўрсатилмайди,
/// ҳудуд тугмалари ва «Орқага» ҳамиша бор (аввал бу ҳолатдан чиқиб
/// бўлмасди). Тестда `context.tr` калитнинг ўзини қайтаради.
void main() {
  Widget view({
    String? errorKey,
    VoidCallback? onRetry,
    VoidCallback? onPublish,
    VoidCallback? onBack,
  }) =>
      TvFeedEmptyView(
        errorKey: errorKey,
        onRetry: onRetry ?? () {},
        onPublish: onPublish ?? () {},
        onBack: onBack ?? () {},
        filters: const Text('FILTERS'),
      );

  Future<void> pumpAlone(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(backgroundColor: Colors.black, body: child),
      ));

  testWidgets('бўш лента: «видео йўқ» + «Видео жойлаш», хато тугмаси йўқ',
      (tester) async {
    var published = 0;
    await pumpAlone(tester, view(onPublish: () => published++));

    expect(find.text('tv_market_empty'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv_feed_retry')), findsNothing);
    expect(find.text('FILTERS'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv_feed_back')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tv_feed_publish')));
    expect(published, 1);
  });

  testWidgets('юклаш хатоси: «видео йўқ» ЭМАС, хато матни + «Қайта уриниш»',
      (tester) async {
    var retries = 0;
    await pumpAlone(
      tester,
      view(errorKey: 'err_network', onRetry: () => retries++),
    );

    expect(find.text('err_network'), findsOneWidget);
    expect(find.text('tv_market_empty'), findsNothing,
        reason: 'тармоқ хатоси «бу ҳудудда видео йўқ» деб кўринмасин');
    expect(find.byKey(const ValueKey('tv_feed_publish')), findsNothing);
    // Ҳудудни алмаштириш ва чиқиш хато ҳолатида ҳам мумкин.
    expect(find.text('FILTERS'), findsOneWidget);
    expect(find.text('back'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tv_feed_retry')));
    expect(retries, 1);
  });

  testWidgets('тор ва паст экранда ҳам тугмалар сиғади (overflow йўқ)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpAlone(tester, view(errorKey: 'err_load_failed'));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('tv_feed_back')),
      50,
    );
    expect(find.byKey(const ValueKey('tv_feed_back')).hitTestable(),
        findsOneWidget);
  });

  testWidgets('«Орқага» (push қилинган экран): экран ёпилади', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (ctx) => Scaffold(
                    body: view(onBack: () => Navigator.maybePop(ctx)),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('tv_market_empty'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tv_feed_back')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.text('tv_market_empty'), findsNothing);
  });

  testWidgets('«Орқага» (пастки менюдаги AVAGram таби): «Бош»га қайтади',
      (tester) async {
    final backs = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => _TabHost(backs)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('tv_market_empty'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tv_feed_back')));
    await tester.pumpAndSettle();
    expect(backs, [1]);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('open'), findsNothing,
        reason: 'таб режимида route ёпилмайди — «Бош» табга ўтади');
  });
}

/// HomeScreen'даги каби: AVAGram — [AvaTabShell] ичидаги таб.
class _TabHost extends StatefulWidget {
  const _TabHost(this.backs);
  final List<int> backs;

  @override
  State<_TabHost> createState() => _TabHostState();
}

class _TabHostState extends State<_TabHost> {
  AvaNavTab tab = AvaNavTab.avagram;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AvaTabShell(
        current: tab,
        home: const Center(child: Text('HOME')),
        tabBuilder: (ctx, _) => TvFeedEmptyView(
          onRetry: () {},
          onPublish: () {},
          onBack: () => Navigator.maybePop(ctx),
          filters: const SizedBox(),
        ),
        onBackToHome: () {
          widget.backs.add(1);
          setState(() => tab = AvaNavTab.home);
        },
      ),
    );
  }
}
