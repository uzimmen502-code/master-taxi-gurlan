import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import 'yuk_owner.dart';

/// Юк модуллари учун умумий Scaffold: тўқ тема + AppBar + эга маълумоти.
///
/// [YukOwner] SharedPreferences'дан юкланади ва [builder]га узатилади
/// (`name` — бўш бўлса `yuk_you`). Local ва intercity экранлари шу қобиқни
/// ишлатади; модул мантиғи ичида йўқ.
class YukModuleScaffold extends StatefulWidget {
  const YukModuleScaffold({
    super.key,
    required this.titleKey,
    required this.builder,
  });

  /// AppBar сарлавҳаси — l10n калити.
  final String titleKey;
  final Widget Function(BuildContext context, YukOwner owner, String name)
      builder;

  static const bg = Color(0xFF0B0E14);
  static const card = Color(0xFF131A22);
  static const accent = Color(0xFFFACC15);

  @override
  State<YukModuleScaffold> createState() => _YukModuleScaffoldState();
}

class _YukModuleScaffoldState extends State<YukModuleScaffold> {
  YukOwner _owner = YukOwner.empty;

  /// Эга юкланмагунча [builder] чақирилмайди: аввал бўш эга билан қурилган
  /// панел `initState`да ўз обуналарини бўш ID билан очиб қўярди ва State
  /// кейин қайта яратилмасди (аудит Y-1, 2026-10-31).
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    YukOwner.load().then((o) {
      if (mounted) {
        setState(() {
          _owner = o;
          _loaded = true;
        });
      }
    }, onError: (Object e) {
      debugPrint('[YukModuleScaffold] owner load: $e');
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _owner.name.isEmpty ? context.tr('yuk_you') : _owner.name;
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: YukModuleScaffold.bg,
        colorScheme: const ColorScheme.dark(
          primary: YukModuleScaffold.accent,
          secondary: Color(0xFF3B82F6),
          surface: YukModuleScaffold.card,
        ),
      ),
      child: Scaffold(
        backgroundColor: YukModuleScaffold.bg,
        appBar: AppBar(
          backgroundColor: YukModuleScaffold.bg,
          foregroundColor: Colors.white,
          title: Text(context.tr(widget.titleKey)),
        ),
        body: _loaded
            ? widget.builder(context, _owner, name)
            : const Center(
                child: CircularProgressIndicator(
                  color: YukModuleScaffold.accent,
                ),
              ),
      ),
    );
  }
}
