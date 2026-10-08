// ПРОФИЛДА КАФЕ-РЕСТОРАН (D-REST-6, D-REST-7: барча рўйхатдан ўта олади).
//
//   ресторани йўқ   → «Кафе-ресторан очиш» → рўйхатдан ўтиш экрани
//   applied         → «Менинг кафем» (меню/дўкон тўлдириш мумкин) + «ариза кўрилмоқда»
//   approved        → «Менинг кафем» → панел
//   suspended/…     → панел + огоҳлантириш
// Ҳозирча фақат ЭГА (`ownerUid == мен`); ходимлар — Б2.7.
// Модул кўринмас (`hidden`) бўлса — ҳеч нарса кўрсатилмайди.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/app_theme.dart';
import '../../courier/widgets/courier_profile_entry.dart' show ProfilePanelButtonBuilder;
import '../data/restaurants_repository.dart';
import '../domain/restaurant_models.dart';
import 'restaurant_panel_screen.dart';
import 'restaurant_register_screen.dart';

class RestaurantProfileEntry extends StatefulWidget {
  const RestaurantProfileEntry({
    super.key,
    required this.userId,
    required this.panelButton,
    this.repository,
  });

  /// Канон телефон ID (`998XXXXXXXXX`) — `restaurants.ownerUid`.
  final String userId;
  final ProfilePanelButtonBuilder panelButton;
  final RestaurantsRepository? repository;

  @override
  State<RestaurantProfileEntry> createState() => _RestaurantProfileEntryState();
}

class _RestaurantProfileEntryState extends State<RestaurantProfileEntry> {
  late final RestaurantsRepository _repo = widget.repository ?? RestaurantsRepository();
  StreamSubscription<List<Restaurant>>? _sub;
  List<Restaurant> _mine = const [];
  bool _loaded = false;

  bool get _visible => ServiceConfigHolder.isVisible('restaurants');

  @override
  void initState() {
    super.initState();
    if (_visible) _listen();
  }

  void _listen() {
    _sub?.cancel();
    _sub = _repo.watchMine(widget.userId).listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _mine = list;
          _loaded = true;
        });
      },
      onError: (Object e) {
        debugPrint('restaurant_profile_entry: $e');
        if (mounted) setState(() => _loaded = true);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _openRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RestaurantRegisterScreen(repository: _repo)),
    );
  }

  void _openPanel(Restaurant r) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RestaurantPanelScreen(restaurantId: r.id, repository: _repo)),
    );
  }

  void _choose() {
    if (_mine.length == 1) {
      _openPanel(_mine.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(ctx.tr('restaurants_m_choose_cafe'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            for (final r in _mine)
              ListTile(
                leading: const Icon(Icons.restaurant_rounded),
                title: Text(r.name),
                subtitle: Text(ctx.tr('restaurants_m_status_${r.status}')),
                onTap: () {
                  Navigator.pop(ctx);
                  _openPanel(r);
                },
              ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(ctx.tr('restaurants_m_open_cafe')),
              onTap: () {
                Navigator.pop(ctx);
                _openRegister();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _note(IconData icon, String text, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_visible || !_loaded) return const SizedBox.shrink();
    if (_mine.isEmpty) {
      return widget.panelButton(
        label: context.tr('restaurants_m_open_cafe'),
        icon: Icons.restaurant_rounded,
        color: AppColors.primaryMid,
        onTap: _openRegister,
      );
    }
    final first = _mine.first;
    final label = _mine.length == 1
        ? '${context.tr('restaurants_m_my_cafe')} · ${first.name}'
        : context.tr('restaurants_m_my_cafe');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.panelButton(
          label: label,
          icon: Icons.restaurant_rounded,
          color: AppColors.primary,
          onTap: _choose,
        ),
        if (first.status == 'applied')
          _note(Icons.hourglass_top_rounded, context.tr('restaurants_m_pending_note'), AppColors.primaryMid),
        if (first.status == 'suspended')
          _note(Icons.block_rounded, context.tr('restaurants_m_suspended_note'), Colors.red.shade700),
        if (first.status == 'rejected')
          _note(Icons.info_outline, context.tr('restaurants_m_rejected_note'), Colors.red.shade700),
      ],
    );
  }
}
