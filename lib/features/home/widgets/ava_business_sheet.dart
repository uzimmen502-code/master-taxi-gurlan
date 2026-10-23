import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/driver_roles.dart';
import '../../../repositories/courier_capability_repository.dart';

/// «＋» — «Менинг бизнесим»: фойдаланувчи ўз ишини шу ердан бошлайди.
///
/// Тартиб (эга, 2026-10-16): видео · эълон · хизмат · онлайн дўкон ·
/// ҳайдовчи · курьер · уй ошпази · кафе/ресторан · юк ташувчи · китоб · AI.
enum AvaCreateAction {
  video,
  ad,
  service,
  shopOnline,
  businessMap,
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
/// турда «Фаол» белгиси чиқади. [hidden] — модули яширин бўлган бандлар
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
    backgroundColor: context.ava.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _Scaled(
      child: _BusinessSheet(driverRoles: driverRoles, hidden: hidden),
    ),
  );
}

/// Тизим шрифти катта қилинган қурилмада (1.3–1.5×) варақа «тўлиб» кетмасин:
/// изоҳлар кесилмасин, бир экранга кўпроқ гуруҳ сиғсин. Ассистент варағидаги
/// каби чегара (`assistant_entry.dart`); матн ҳамон бироз катталашади.
class _Scaled extends StatelessWidget {
  const _Scaled({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.15)),
      child: child,
    );
  }
}

/// «Онлайн Дўкон очиш» → маҳсулот қаерга қўшилади: Аҳоли бозори ёки Улгуржи.
Future<AvaShopTarget?> showAvaShopTargetSheet(BuildContext context) {
  return showModalBottomSheet<AvaShopTarget>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.ava.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final c = ctx.ava;
      return _Scaled(
          child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AvaSpace.screen, 0, AvaSpace.screen, AvaSpace.screen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                child: Text(
                  ctx.tr('home_create_shop_where'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: c.ink,
                  ),
                ),
              ),
              _Card(
                children: [
                  _RowTile(
                    icon: Icons.storefront_outlined,
                    label: ctx.tr('tv_shop_to_market'),
                    subtitle: ctx.tr('home_create_shop_retail_sub'),
                    onTap: () => Navigator.of(ctx).pop(AvaShopTarget.retail),
                  ),
                  _RowTile(
                    icon: Icons.inventory_2_outlined,
                    label: ctx.tr('home_module_wholesale'),
                    subtitle: ctx.tr('home_create_shop_wholesale_sub'),
                    onTap: () => Navigator.of(ctx).pop(AvaShopTarget.wholesale),
                  ),
                ],
              ),
            ],
          ),
        ),
      ));
    },
  );
}

/// Бир қатор бандининг маълумоти (матн калитлари — 3 тилда).
class _Item {
  const _Item(this.action, this.icon, this.labelKey, this.subKey,
      {this.active = false});

  final AvaCreateAction action;
  final IconData icon;
  final String labelKey;
  final String subKey;

  /// Ҳозир иш бораётган (яшил «Фаол» белгиси).
  final bool active;
}

class _BusinessSheet extends StatelessWidget {
  const _BusinessSheet({
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

  List<_Item> _visible(List<_Item> items) =>
      items.where((e) => !hidden.contains(e.action)).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<_Item>)>[
      (
        'home_create_group_quick',
        _visible(const [
          _Item(AvaCreateAction.video, Icons.videocam_rounded,
              'home_create_video', 'home_create_video_sub'),
          _Item(AvaCreateAction.ad, Icons.campaign_rounded, 'home_create_ad',
              'home_create_ad_sub'),
          _Item(AvaCreateAction.service, Icons.handyman_rounded,
              'home_create_service', 'home_create_service_sub'),
        ]),
      ),
      (
        'home_create_group_sell',
        _visible(const [
          _Item(AvaCreateAction.shopOnline, Icons.storefront_rounded,
              'home_create_shop_online', 'home_create_shop_online_hint'),
          // Бизнес харитаси (2026-10-23): жисмоний жойни (дўкон, кафе, хизмат) харитага қўшиш.
          _Item(AvaCreateAction.businessMap, Icons.add_business_rounded,
              'home_create_business_map', 'home_create_business_map_sub'),
        ]),
      ),
      (
        'home_create_group_work',
        _visible([
          _Item(
            AvaCreateAction.driver,
            Icons.local_taxi_rounded,
            driverRoles.isDriver
                ? 'home_create_driver_open'
                : 'home_create_driver',
            'home_create_driver_sub',
            active: driverRoles.hasActive,
          ),
          _Item(
            AvaCreateAction.courier,
            Icons.delivery_dining_rounded,
            _courierHasPanel
                ? 'home_create_courier_open'
                : 'home_create_courier',
            'home_create_courier_sub',
            active: driverRoles.courierOnline,
          ),
          const _Item(AvaCreateAction.cargo, Icons.local_shipping_rounded,
              'home_create_cargo', 'home_create_cargo_sub'),
        ]),
      ),
      (
        'home_create_group_food',
        _visible(const [
          _Item(AvaCreateAction.homeCook, Icons.soup_kitchen_rounded,
              'home_create_home_cook', 'home_create_home_cook_sub'),
          _Item(AvaCreateAction.cafe, Icons.restaurant_rounded,
              'restaurants_m_open_cafe', 'home_create_cafe_sub'),
        ]),
      ),
      (
        'home_create_group_help',
        _visible(const [
          _Item(AvaCreateAction.book, Icons.menu_book_rounded,
              'book_menu_title', 'book_menu_subtitle'),
          _Item(AvaCreateAction.assistant, Icons.auto_awesome_rounded,
              'home_module_chatgpt', 'home_create_assistant_sub'),
        ]),
      ),
    ].where((g) => g.$2.isNotEmpty).toList(growable: false);

    void pick(AvaCreateAction a) => Navigator.of(context).pop(a);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // Кичик экранда ҳам сиғади: сарлавҳа туради, рўйхат айланади.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: context.tr('home_create_title'),
              subtitle: context.tr('home_create_subtitle'),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                    AvaSpace.screen, 4, AvaSpace.screen, 20),
                children: [
                  for (final g in groups) ...[
                    _GroupTitle(context.tr(g.$1)),
                    _Card(
                      children: [
                        for (final it in g.$2)
                          _RowTile(
                            icon: it.icon,
                            label: context.tr(it.labelKey),
                            subtitle: context.tr(it.subKey),
                            active: it.active,
                            onTap: () => pick(it.action),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Сарлавҳа: бренд белгиси + «Менинг бизнесим» + қисқа таъриф.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AvaSpace.screen + 4, 0, AvaSpace.screen, 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: c.brand,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: c.brand.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(Icons.rocket_launch_rounded, color: c.brandInk, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.2,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, height: 1.3, color: c.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: context.ava.ink2,
        ),
      ),
    );
  }
}

/// Оқ юмалоқ карта: ичидаги қаторлар ингичка чизиқ билан ажралган.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.line),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, indent: 74, color: c.line),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Карта ичидаги қатор: иконка белгиси · ном + изоҳ · («Фаол») · ›.
class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final sub = subtitle;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: c.brandSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 24, color: c.brandText),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: c.ink,
                        ),
                      ),
                      if (sub != null && sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: c.ink2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: 8),
                  _ActivePill(text: context.tr('driver_chip_active')),
                ],
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 22, color: c.ink3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  const _ActivePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.okSoft,
        borderRadius: BorderRadius.circular(AvaRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c.ok, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: c.ok,
            ),
          ),
        ],
      ),
    );
  }
}
