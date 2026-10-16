import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/driver_roles.dart';
import '../../../repositories/courier_capability_repository.dart';

/// Пастки менюнинг таблари.
enum AvaNavTab { home, avagram, create, messages, cabinet }

/// Бош · AVAGram · ＋ · Хабарлар · Кабинет.
///
/// «Буюртмалар» алоҳида таб эмас — у Кабинет ичига кўчди (тавсиф талаби).
/// «Ҳамён» ҳам бу ерда йўқ: у коддан ўчирилмаган, фақат интерфейсда
/// яширилган (AVA AI ва EV ичидаги «тўлдириш» ишлайверади).
class AvaBottomNav extends StatelessWidget {
  const AvaBottomNav({
    super.key,
    required this.current,
    required this.onTap,
    this.messagesBadge = 0,
  });

  final AvaNavTab current;
  final void Function(AvaNavTab tab) onTap;

  /// Ўқилмаган хабарлар сони; 0 бўлса белги кўринмайди.
  final int messagesBadge;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _NavItem(
              tab: AvaNavTab.home,
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: context.tr('home_nav_home'),
              current: current,
              onTap: onTap,
            ),
            _NavItem(
              tab: AvaNavTab.avagram,
              icon: Icons.play_circle_outline_rounded,
              activeIcon: Icons.play_circle_fill_rounded,
              label: context.tr('home_nav_avagram'),
              current: current,
              onTap: onTap,
            ),
            _CreateItem(onTap: () => onTap(AvaNavTab.create)),
            _NavItem(
              tab: AvaNavTab.messages,
              icon: Icons.chat_bubble_outline_rounded,
              activeIcon: Icons.chat_bubble_rounded,
              label: context.tr('home_nav_messages'),
              current: current,
              onTap: onTap,
              badge: messagesBadge,
            ),
            _NavItem(
              tab: AvaNavTab.cabinet,
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: context.tr('home_nav_cabinet'),
              current: current,
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.current,
    required this.onTap,
    this.badge = 0,
  });

  final AvaNavTab tab;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final AvaNavTab current;
  final void Function(AvaNavTab tab) onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final active = current == tab;
    final color = active ? c.brand : c.ink3;

    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          onTap: () => onTap(tab),
          child: ConstrainedBox(
            // Тизим шрифти катта бўлганда панел ўсади, лекин ёрлиқ
            // қирқилмайди ва «BOTTOM OVERFLOWED» чиқмайди.
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _IconWithBadge(
                    icon: active ? activeIcon : icon,
                    color: color,
                    badge: badge,
                    badgeColor: c.danger,
                    badgeInk: c.brandInk,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AvaText.navLabel.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconWithBadge extends StatelessWidget {
  const _IconWithBadge({
    required this.icon,
    required this.color,
    required this.badge,
    required this.badgeColor,
    required this.badgeInk,
  });

  final IconData icon;
  final Color color;
  final int badge;
  final Color badgeColor;
  final Color badgeInk;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 22, color: color);
    if (badge <= 0) return iconWidget;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        iconWidget,
        Positioned(
          right: -6,
          top: -3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            constraints: const BoxConstraints(minWidth: 15),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(AvaRadius.chip),
            ),
            child: Text(
              badge > 99 ? '99+' : '$badge',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: badgeInk,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// «＋» — марказдаги қўшиш тугмаси.
class _CreateItem extends StatelessWidget {
  const _CreateItem({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Expanded(
      child: Semantics(
        button: true,
        label: context.tr('home_nav_create'),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            // `heightFactor` ШАРТ: усиз `Center` бўш (loose) чегараларда
            // МАКСИМАЛ баландликни олади. `Scaffold.bottomNavigationBar`га
            // эса бутун экран баландлиги loose қилиб берилади — натижада
            // меню бутун саҳифани эгаллаб, бош саҳифани ёпиб қўйган эди
            // (2026-09-25, қурилмада: «Қўшиш» тугмаси 0..2340 px).
            child: Center(
              heightFactor: 1,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.brand,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.add_rounded, size: 24, color: c.brandInk),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «＋» — «Менинг бизнесим»: фойдаланувчи ўз ишини шу ердан бошлайди.
///
/// Тартиб (эга, 2026-10-16): видео · эълон · хизмат · онлайн дўкон · дўкон ·
/// ҳайдовчи · курьер · уй ошпази · кафе/ресторан · юк ташувчи · китоб · AI.
enum AvaCreateAction {
  video,
  ad,
  service,
  shopOnline,
  shop,
  driver,
  courier,
  homeCook,
  cafe,
  cargo,
  book,
  assistant,
}

/// «Онлайн Дўкон очиш» ичидаги танлов: маҳсулот қаерга қўшилади.
enum AvaShopTarget { retail, wholesale }

/// Танланган амални қайтаради; бекор қилинса `null`.
///
/// [driverRoles] — ҳайдовчи/курьер бўлса «…бўлиш» ўрнига «…панели» ва фаол
/// турда яшил белги чиқади. [hidden] — модули яширин бўлган бандлар
/// (масалан, кафе-ресторан `hidden` бўлса «Уй ошпази» ва «Кафе» кўринмайди).
Future<AvaCreateAction?> showAvaCreateSheet(
  BuildContext context, {
  DriverRoles driverRoles = DriverRoles.none,
  Set<AvaCreateAction> hidden = const {},
}) {
  return showModalBottomSheet<AvaCreateAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _CreateSheet(driverRoles: driverRoles, hidden: hidden),
  );
}

/// «Онлайн Дўкон очиш» → маҳсулот қаерга қўшилади: Аҳоли бозори ёки Улгуржи.
Future<AvaShopTarget?> showAvaShopTargetSheet(BuildContext context) {
  return showModalBottomSheet<AvaShopTarget>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final c = ctx.ava;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AvaSpace.screen, 0, AvaSpace.screen, AvaSpace.screen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ctx.tr('home_create_shop_where'),
                style: AvaText.sectionTitle.copyWith(color: c.ink),
              ),
              const SizedBox(height: 12),
              _CreateRow(
                icon: Icons.storefront_outlined,
                label: ctx.tr('tv_shop_to_market'),
                onTap: () => Navigator.of(ctx).pop(AvaShopTarget.retail),
              ),
              _CreateRow(
                icon: Icons.inventory_2_outlined,
                label: ctx.tr('home_module_wholesale'),
                onTap: () => Navigator.of(ctx).pop(AvaShopTarget.wholesale),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Бир-бирига ўхшаш икки банд ("Онлайн Дўкон очиш" ва "Дўкон очиш") фарқи
/// қисқа изоҳда кўринсин (эга, 2026-10-16).
const _subtitleKeys = <AvaCreateAction, String>{
  AvaCreateAction.shopOnline: 'home_create_shop_online_hint',
  AvaCreateAction.shop: 'tv_shop_open_hint',
};

class _CreateSheet extends StatelessWidget {
  const _CreateSheet({
    this.driverRoles = DriverRoles.none,
    this.hidden = const {},
  });

  final DriverRoles driverRoles;
  final Set<AvaCreateAction> hidden;

  /// Курьер панели бор (ёки тўхтатилган, лекин қўлдаги ишни тугатиши керак).
  bool get _courierHasPanel =>
      driverRoles.courierOnline ||
      CourierCapabilityRepository.panelStatuses
          .contains(driverRoles.courierStatus);

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final items = <(AvaCreateAction, IconData, String, bool)>[
      (AvaCreateAction.video, Icons.videocam_outlined, 'home_create_video', false),
      (AvaCreateAction.ad, Icons.campaign_outlined, 'home_create_ad', false),
      (
        AvaCreateAction.service,
        Icons.handyman_outlined,
        'home_create_service',
        false
      ),
      (
        AvaCreateAction.shopOnline,
        Icons.add_shopping_cart_outlined,
        'home_create_shop_online',
        false
      ),
      (AvaCreateAction.shop, Icons.storefront_outlined, 'tv_shop_open_cta', false),
      (
        AvaCreateAction.driver,
        Icons.local_taxi_outlined,
        driverRoles.isDriver ? 'home_create_driver_open' : 'home_create_driver',
        driverRoles.hasActive,
      ),
      (
        AvaCreateAction.courier,
        Icons.delivery_dining,
        _courierHasPanel ? 'home_create_courier_open' : 'home_create_courier',
        driverRoles.courierOnline,
      ),
      (
        AvaCreateAction.homeCook,
        Icons.soup_kitchen_outlined,
        'home_create_home_cook',
        false
      ),
      (AvaCreateAction.cafe, Icons.restaurant_outlined, 'restaurants_m_open_cafe', false),
      (
        AvaCreateAction.cargo,
        Icons.local_shipping_outlined,
        'home_create_cargo',
        false
      ),
      (AvaCreateAction.book, Icons.menu_book_outlined, 'book_menu_title', false),
      (
        AvaCreateAction.assistant,
        Icons.auto_awesome_outlined,
        'home_module_chatgpt',
        false
      ),
    ].where((e) => !hidden.contains(e.$1)).toList();

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // 12 банд кичик экранга сиғмайди — рўйхат айланади, сарлавҳа туради.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AvaSpace.screen,
            0,
            AvaSpace.screen,
            AvaSpace.screen,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('home_create_title'),
                style: AvaText.sectionTitle.copyWith(color: c.ink),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final (action, icon, key, active) in items)
                      _CreateRow(
                        icon: icon,
                        label: context.tr(key),
                        subtitle: _subtitleKeys[action] == null
                            ? null
                            : context.tr(_subtitleKeys[action]!),
                        active: active,
                        onTap: () => Navigator.of(context).pop(action),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Варақадаги битта қатор: белги · матн · (фаол бўлса яшил нуқта) · ›.
class _CreateRow extends StatelessWidget {
  const _CreateRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AvaRadius.card),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AvaTap.minSize),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.brandSoft,
                  borderRadius: BorderRadius.circular(AvaRadius.card - 2),
                ),
                child: Icon(icon, size: 20, color: c.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AvaText.body.copyWith(color: c.ink),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AvaText.body.copyWith(
                          color: c.ink3,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (active) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right_rounded, size: 20, color: c.ink3),
            ],
          ),
        ),
      ),
    );
  }
}
