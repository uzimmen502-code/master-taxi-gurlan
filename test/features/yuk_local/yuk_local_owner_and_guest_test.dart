import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/home_yuk_local_section.dart';
import 'package:ava_gurlan/features/yuk_local/screens/yuk_local_nearby_panel.dart';
import 'package:ava_gurlan/features/yuk_shared/yuk_module_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Аудит 2026-10-31: Y-1 (эга юкланиш пойгаси) ва O-7 (меҳмонга рўйхат йўқ).
class _Probe extends StatefulWidget {
  const _Probe(this.ownerId, this.log);
  final String ownerId;
  final List<String> log;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('initState:${widget.ownerId}');
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets(
      'Y-1: YukModuleScaffold панелни эга ЮКЛАНГАНДАН кейин қуради — '
      'initState ҳақиқий ID кўради', (t) async {
    SharedPreferences.setMockInitialValues({
      'user_phone': '+998901234567',
      'user_name': 'Ali',
    });
    final log = <String>[];
    await t.pumpWidget(MaterialApp(
      home: YukModuleScaffold(
        titleKey: 'x',
        builder: (c, o, n) => _Probe(o.id, log),
      ),
    ));
    await t.pumpAndSettle();
    // Аввал: [initState:, ...] — обуналар бўш ID билан очиларди.
    expect(log, ['initState:998901234567']);
  });

  testWidgets('Y-1: телефонсиз — панел бўш ID билан БИР марта қурилади',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final log = <String>[];
    await t.pumpWidget(MaterialApp(
      home: YukModuleScaffold(
        titleKey: 'x',
        builder: (c, o, n) => _Probe(o.id, log),
      ),
    ));
    await t.pumpAndSettle();
    expect(log, ['initState:']);
  });

  testWidgets('O-7: меҳмон панели — рўйхат эмас, «Кабинетда рўйхатдан ўтинг»',
      (t) async {
    var tapped = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: YukLocalNearbyPanel(
          ownerId: '',
          ownerName: '',
          ownerPhone: '',
          onRegister: () => tapped++,
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('yuk_local_guest_message')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('yuk_local_add_btn')), findsNothing);
    await t.tap(find.text('yuk_local_guest_cta'));
    expect(tapped, 1);
  });

  testWidgets('O-7: бош саҳифа бўлими меҳмонга хабар кўрсатади', (t) async {
    var tapped = 0;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListView(children: [
          HomeYukLocalSection(
            isGuest: true,
            onRegister: () => tapped++,
            onOpenAll: () {},
            onOpenDriver: (_) {},
          ),
        ]),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('home_yuk_local_guest')), findsOneWidget);
    expect(find.text('yuk_local_guest_message'), findsOneWidget);
    await t.tap(find.text('yuk_local_guest_cta'));
    expect(tapped, 1);
  });
}
