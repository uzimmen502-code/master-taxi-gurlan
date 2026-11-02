import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import 'inbox_entries.dart';
import 'inbox_time.dart';

/// «Хабарлар» қатори (Telegram/WhatsApp услуби): доира белги, сарлавҳа, охирги
/// хабарнинг бир қатори, ўнгда вақт ва ўқилмаганлар сони. Ўқилмаган қатор —
/// жирний сарлавҳа ва тўқ матн (эга, 2026-10-19 қоидаси сақланди).
class InboxTile extends StatelessWidget {
  const InboxTile({
    super.key,
    required this.entry,
    required this.now,
    required this.onTap,
    this.onLongPress,
  });

  final InboxEntry entry;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const double avatar = 48;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final e = entry;
    final bold = e.isBold;
    final t = e.time;
    final time = t == null
        ? ''
        : inboxRowTime(
            t,
            now: now,
            yesterday: context.tr('inbox_yesterday'),
            weekdays: [for (var i = 1; i <= 7; i++) context.tr('inbox_wd_$i')],
          );
    return Material(
      color: c.surface,
      child: InkWell(
        key: ValueKey('inbox-row-${e.key}'),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 10, AvaSpace.screen, 10),
          child: Row(
            children: [
              _Avatar(entry: e),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AvaText.body.copyWith(
                              fontSize: 15,
                              color: c.ink,
                              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (time.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: AvaText.caption.copyWith(
                              color: bold ? c.brandText : c.ink3,
                              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AvaText.body.copyWith(
                              fontSize: 13,
                              color: bold ? c.inkRow : c.ink2,
                              fontWeight: bold ? FontWeight.w500 : FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _Trailing(entry: e),
                      ],
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

class _Trailing extends StatelessWidget {
  const _Trailing({required this.entry});

  final InboxEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final n = entry.unreadCount;
    if (n > 0) {
      return Container(
        key: ValueKey('inbox-count-${entry.key}'),
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(10)),
        child: Text(
          n > 99 ? '99+' : '$n',
          style: AvaText.caption.copyWith(color: c.brandInk, fontWeight: FontWeight.w700, height: 1),
        ),
      );
    }
    if (entry.unread) {
      return Container(
        key: ValueKey('inbox-dot-${entry.key}'),
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
      );
    }
    if (entry.pinned) {
      return Icon(Icons.push_pin_outlined, size: 16, color: c.ink3);
    }
    return const SizedBox.shrink();
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry});

  final InboxEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final e = entry;
    if (e.kind == InboxKind.deal && e.photoUrl.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: InboxTile.avatar,
          height: InboxTile.avatar,
          child: Image.network(
            e.photoUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _circle(c.brandSoft, Icons.inventory_2_outlined, c.brandText),
          ),
        ),
      );
    }
    return switch (e.kind) {
      InboxKind.support => _circle(c.okSoft, Icons.support_agent, c.ok),
      InboxKind.deal => _circle(
          c.brandSoft, e.category == 'business' ? Icons.storefront_rounded : Icons.inventory_2_outlined, c.brandText),
      InboxKind.dialog => _circle(c.brandSoft, Icons.mail_outline, c.brandText),
      InboxKind.driver => _circle(c.brandSoft, Icons.local_taxi_outlined, c.brandText),
      InboxKind.order => _circle(
          c.warnSoft,
          switch (e.orderType) {
            'bread' => Icons.bakery_dining_outlined,
            'restaurant' => Icons.restaurant_outlined,
            _ => Icons.receipt_long_outlined,
          },
          c.warn),
      InboxKind.news => e.category == 'emergency'
          ? _circle(c.dangerSoft, Icons.priority_high_rounded, c.danger)
          : _circle(c.chip, Icons.campaign_outlined, c.ink2),
    };
  }

  Widget _circle(Color bg, IconData icon, Color fg) => Container(
        width: InboxTile.avatar,
        height: InboxTile.avatar,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: fg, size: 24),
      );
}
