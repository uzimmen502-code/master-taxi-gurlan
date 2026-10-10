// Ресторан панели (§12.8): Буюртмалар / Меню / Дўкон / Ҳисобот.
// Иловада = вебда (Flutter web) — битта код.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../home/widgets/ava_section.dart';
import '../data/restaurants_repository.dart';
import '../domain/restaurant_models.dart';
import 'merchant_menu_tab.dart';
import 'merchant_orders_tab.dart';
import 'merchant_report_tab.dart';
import 'merchant_shop_tab.dart';
import 'restaurant_register_screen.dart';

class RestaurantPanelScreen extends StatefulWidget {
  const RestaurantPanelScreen({super.key, required this.restaurantId, this.repository, this.initialTab = 0});

  final String restaurantId;
  final RestaurantsRepository? repository;
  final int initialTab;

  @override
  State<RestaurantPanelScreen> createState() => _RestaurantPanelScreenState();
}

class _RestaurantPanelScreenState extends State<RestaurantPanelScreen> {
  late final RestaurantsRepository _repo = widget.repository ?? RestaurantsRepository();
  late int _tab = widget.initialTab;

  /// Жорий ресторан — эга бир нечта кафе юритса панел ичида алмаштиради
  /// (менежерлик, эга қарори 2026-10-10); `IndexedStack` таблари қайта
  /// қурилади (`ValueKey`).
  late String _restaurantId = widget.restaurantId;

  /// Эганинг барча ресторанлари — алмаштириш варағи учун (ownerUid маълум
  /// бўлгач уланади; ходим аъзолиги — Б2.7).
  Stream<List<Restaurant>>? _mine;
  String _mineOwner = '';

  /// Жорий ресторан оқими — state'да кешланади: ҳар `setState` (таб
  /// алмашуви) да янги Firestore listener очилмасин. Алмаштиришда тозаланади.
  Stream<Restaurant?>? _restaurantStream;

  Stream<Restaurant?> get _restaurant => _restaurantStream ??= _repo.watchRestaurant(_restaurantId);

  Stream<List<Restaurant>> _mineFor(String ownerUid) {
    if (_mine == null || _mineOwner != ownerUid) {
      _mineOwner = ownerUid;
      _mine = _repo.watchMine(ownerUid);
    }
    return _mine!;
  }

  Future<void> _switchRestaurant(List<Restaurant> mine) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(ctx.tr('restaurants_m_switch_cafe'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            for (final r in mine)
              ListTile(
                leading: Icon(r.id == _restaurantId ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                title: Text(r.name),
                subtitle: Text(ctx.tr('restaurants_m_status_${r.status}')),
                onTap: () => Navigator.pop(ctx, r.id),
              ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(ctx.tr('restaurants_m_add_another')),
              onTap: () => Navigator.pop(ctx, '+'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == '+') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => RestaurantRegisterScreen(repository: _repo)));
      return;
    }
    if (picked != _restaurantId) {
      setState(() {
        _restaurantId = picked;
        // Панел қайта қурилади — эски обуналар StreamBuilder dispose'ида
        // бекор бўлади, оқимлар янги ID учун янгидан очилади.
        _mine = null;
        _restaurantStream = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return StreamBuilder<Restaurant?>(
      key: ValueKey('panel_$_restaurantId'),
      stream: _restaurant,
      builder: (context, snap) {
        final r = snap.data;
        return Scaffold(
          backgroundColor: c.bg,
          appBar: AppBar(
            backgroundColor: c.surface,
            surfaceTintColor: c.surface,
            elevation: 0,
            title: r == null
                ? Text(context.tr('restaurants_m_my_cafe'),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink))
                : StreamBuilder<List<Restaurant>>(
                    stream: _mineFor(r.ownerUid),
                    builder: (context, ms) {
                      final mine = ms.data ?? const <Restaurant>[];
                      final many = mine.length > 1;
                      final title = Text(r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink));
                      if (!many) return title;
                      return InkWell(
                        onTap: () => _switchRestaurant(mine),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(child: title),
                          Icon(Icons.expand_more_rounded, color: c.ink2),
                        ]),
                      );
                    },
                  ),
            actions: [
              if (r != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(child: _StatusBadge(status: r.status)),
                ),
            ],
          ),
          body: r == null
              ? (snap.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: AvaNoticeRow(text: context.tr('restaurants_err_RESTAURANT_NOT_FOUND'), icon: Icons.error_outline, color: c.warn),
                    ))
              : Column(
                  children: [
                    if (r.status == 'applied')
                      _Banner(text: context.tr('restaurants_m_pending_note'), icon: Icons.hourglass_top_rounded, color: c.warn),
                    if (r.status == 'suspended')
                      _Banner(text: context.tr('restaurants_m_suspended_note'), icon: Icons.block_rounded, color: c.danger),
                    if (r.status == 'rejected')
                      _Banner(text: context.tr('restaurants_m_rejected_note'), icon: Icons.info_outline, color: c.danger),
                    if (r.isPausedAt(DateTime.now()))
                      _Banner(
                        text: context.tr('restaurants_m_paused_until').replaceAll('{time}', _hhmm(r.pausedUntil!)),
                        icon: Icons.pause_circle_outline_rounded,
                        color: c.warn,
                        actionLabel: context.tr('restaurants_m_resume'),
                        onAction: () => _repo.setPaused(r.id, null),
                      ),
                    Expanded(
                      child: IndexedStack(
                        key: ValueKey('tabs_$_restaurantId'),
                        index: _tab,
                        children: [
                          MerchantOrdersTab(restaurant: r, repository: _repo),
                          MerchantMenuTab(restaurant: r, repository: _repo),
                          MerchantShopTab(restaurant: r, repository: _repo),
                          MerchantReportTab(restaurant: r, repository: _repo),
                        ],
                      ),
                    ),
                  ],
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), label: context.tr('restaurants_m_tab_orders')),
              NavigationDestination(icon: const Icon(Icons.restaurant_menu_rounded), label: context.tr('restaurants_m_tab_menu')),
              NavigationDestination(icon: const Icon(Icons.storefront_outlined), label: context.tr('restaurants_m_tab_shop')),
              NavigationDestination(icon: const Icon(Icons.bar_chart_rounded), label: context.tr('restaurants_m_tab_report')),
            ],
          ),
        );
      },
    );
  }

  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final color = switch (status) {
      'approved' => c.ok,
      'applied' => c.warn,
      _ => c.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(context.tr('restaurants_m_status_$status'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.icon, required this.color, this.actionLabel, this.onAction});

  final String text;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: AvaNoticeRow(text: text, icon: icon, color: color, actionLabel: actionLabel, onAction: onAction),
      );
}
