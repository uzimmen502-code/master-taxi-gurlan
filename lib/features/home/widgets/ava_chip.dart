import 'package:flutter/material.dart';

import '../../../core/theme/ava_tokens.dart';

/// Чипнинг оҳанги.
enum AvaChipTone {
  /// Нейтрал — тур белгиси, ҳудуд, машина.
  neutral,

  /// Бренд — асосий белги.
  brand,

  /// Ижобий — «бўш ўрин бор», «ишламоқда».
  ok,

  /// Огоҳлантириш — «шошилинч», «тугаяпти».
  warn,
}

/// Кичик белги: тур («Эълон», «Видео»), вақт («Бугун»), ҳолат («Бўш»).
class AvaChip extends StatelessWidget {
  const AvaChip({
    super.key,
    required this.label,
    this.tone = AvaChipTone.neutral,
    this.icon,
  });

  final String label;
  final AvaChipTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final (bg, fg) = switch (tone) {
      AvaChipTone.neutral => (c.chip, c.ink2),
      AvaChipTone.brand => (c.brandSoft, c.brand),
      AvaChipTone.ok => (c.okSoft, c.ok),
      AvaChipTone.warn => (c.warnSoft, c.warn),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AvaRadius.chip),
        border: tone == AvaChipTone.neutral
            ? Border.all(color: c.line)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          // Матн 130% гача катталашганда чип кенгаяди, матн қирқилмайди.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AvaText.caption.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
