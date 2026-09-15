import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../yuk_intercity/screens/yuk_intercity_screen.dart';
import '../../yuk_local/screens/yuk_local_nearby_panel.dart';
import '../../yuk_shared/yuk_owner.dart';

/// Юк биржаси қобиғи — `local` (туман ичида, GPS) ва `intercity`
/// (шаҳарлараро эълонлар) scope'ларини алмаштиради. Мантиқ йўқ: эга
/// маълумотини юклаб, танланган панелга узатади.
class YukBirjaScreen extends StatefulWidget {
  const YukBirjaScreen({
    super.key,
    this.initialScope,
    this.highlightListingId,
    this.autoFrom,
    this.autoTo,
  });

  /// `local` | `intercity`
  final String? initialScope;
  final String? highlightListingId;
  final String? autoFrom;
  final String? autoTo;

  @override
  State<YukBirjaScreen> createState() => _YukBirjaScreenState();
}

class _YukBirjaScreenState extends State<YukBirjaScreen> {
  static const _bg = Color(0xFF0B0E14);
  static const _card = Color(0xFF131A22);
  static const _border = Color(0xFF252B36);
  static const _muted = Color(0xFF94A3B8);
  static const _accent = Color(0xFFFACC15);

  final _localPanelKey = GlobalKey<YukLocalNearbyPanelState>();
  String _scope = 'local';
  YukOwner _owner = YukOwner.empty;

  /// Intercity бир марта очилгач тирик қолади (store/stream қайта юкланмайди);
  /// local панел ҳар киришда қайта қурилади (GPS қайта сўралади).
  bool _intercityVisited = false;

  @override
  void initState() {
    super.initState();
    final scope = (widget.initialScope ?? '').trim();
    if (scope == 'intercity' || scope == 'local') _scope = scope;
    _intercityVisited = _scope == 'intercity';
    YukOwner.load().then((o) {
      if (mounted) setState(() => _owner = o);
    });
  }

  void _onScopeTap(String scope) {
    setState(() {
      _scope = scope;
      if (scope == 'intercity') _intercityVisited = true;
    });
    if (scope == 'local') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _localPanelKey.currentState?.ensureGps();
      });
    }
  }

  Widget _chip(String scope, String labelKey) {
    final on = _scope == scope;
    return Expanded(
      child: ChoiceChip(
        label: Center(child: Text(context.tr(labelKey))),
        selected: on,
        selectedColor: _accent.withValues(alpha: 0.25),
        labelStyle: TextStyle(
          color: on ? _accent : _muted,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        side: BorderSide(color: on ? _accent : _border),
        backgroundColor: _card,
        onSelected: (_) => _onScopeTap(scope),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _owner.name.isEmpty ? context.tr('yuk_you') : _owner.name;
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          secondary: Color(0xFF3B82F6),
          surface: _card,
        ),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          title: Text(context.tr('home_module_yuk_birja')),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              _chip('local', 'yuk_scope_local'),
              const SizedBox(width: 12),
              _chip('intercity', 'yuk_scope_intercity'),
            ]),
          ),
          Expanded(
            child: IndexedStack(
              index: _scope == 'local' ? 0 : 1,
              children: [
                if (_scope == 'local')
                  YukLocalNearbyPanel(
                    key: _localPanelKey,
                    ownerId: _owner.id,
                    ownerName: name,
                    ownerPhone: _owner.phone,
                  )
                else
                  const SizedBox.shrink(),
                if (_intercityVisited)
                  YukIntercityScreen(
                    ownerId: _owner.id,
                    ownerName: name,
                    ownerPhone: _owner.phone,
                    highlightListingId: widget.highlightListingId,
                    autoFrom: widget.autoFrom,
                    autoTo: widget.autoTo,
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
