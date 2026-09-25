import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';

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
            child: Center(
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

/// «＋» босилганда пастдан чиқадиган меню.
enum AvaCreateAction { video, ad, product, service, seller }

/// Танланган амални қайтаради; бекор қилинса `null`.
Future<AvaCreateAction?> showAvaCreateSheet(BuildContext context) {
  return showModalBottomSheet<AvaCreateAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => const _CreateSheet(),
  );
}

class _CreateSheet extends StatelessWidget {
  const _CreateSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    const items = <(AvaCreateAction, IconData, String)>[
      (AvaCreateAction.video, Icons.videocam_outlined, 'home_create_video'),
      (AvaCreateAction.ad, Icons.campaign_outlined, 'home_create_ad'),
      (
        AvaCreateAction.product,
        Icons.add_shopping_cart_outlined,
        'home_create_product'
      ),
      (
        AvaCreateAction.service,
        Icons.handyman_outlined,
        'home_create_service'
      ),
      (AvaCreateAction.seller, Icons.storefront_outlined, 'home_create_seller'),
    ];

    return SafeArea(
      top: false,
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
            for (final (action, icon, key) in items)
              InkWell(
                onTap: () => Navigator.of(context).pop(action),
                borderRadius: BorderRadius.circular(AvaRadius.card),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: AvaTap.minSize),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c.brandSoft,
                            borderRadius:
                                BorderRadius.circular(AvaRadius.card - 2),
                          ),
                          child: Icon(icon, size: 20, color: c.brand),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.tr(key),
                            style: AvaText.body.copyWith(color: c.ink),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: c.ink3,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
