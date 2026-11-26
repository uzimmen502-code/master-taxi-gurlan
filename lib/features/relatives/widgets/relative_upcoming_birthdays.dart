import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/relative_person.dart';

/// Қариндошлар рўйхати бошида: яқинлашаётган туғилган кунлар + «Саватча тайёрлаш» (эга 2026-11-26).
class RelativeUpcomingBirthdays extends StatelessWidget {
  const RelativeUpcomingBirthdays({super.key, required this.people, required this.onPrepare, required this.avatar});

  final List<RelativePerson> people;
  final ValueChanged<RelativePerson> onPrepare;
  final Widget Function(RelativePerson p) avatar;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      key: const ValueKey('rel_upcoming_birthdays'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('hb_rel_upcoming_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
          for (final p in people) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                avatar(p),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.fullName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
                      Text(
                        p.daysUntilBirthday == 0
                            ? context.tr('rel_today')
                            : context.tr('rel_days_left').replaceAll('{count}', '${p.daysUntilBirthday}'),
                        style: TextStyle(fontSize: 14, color: c.ink2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              key: ValueKey('rel_prepare_basket_${p.id}'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              onPressed: () => onPrepare(p),
              icon: const Icon(Icons.shopping_basket_outlined, size: 20),
              label: Text(context.tr('hb_rel_prepare'), textAlign: TextAlign.center),
            ),
          ],
        ],
      ),
    );
  }
}
