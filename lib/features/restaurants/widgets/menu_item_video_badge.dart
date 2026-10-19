// Мижоз менюсида таом расми устидаги ▶ белгиси: таомнинг ФАОЛ видеоси бор (эга, 2026-10-19).
// Босилса видео АВАГрам лентасида очилади. Кўринадиган доира — 28, босиш майдони — 44
// (`AvaTap.minSize`): расм 72×72 ичида сиғади.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';

class MenuItemVideoBadge extends StatelessWidget {
  const MenuItemVideoBadge({super.key, required this.itemId, required this.onTap});

  final String itemId;
  final VoidCallback onTap;

  static const double circle = 28;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.tr('link_video_open'),
      child: ExcludeSemantics(
        child: InkWell(
          key: ValueKey('item-video-$itemId'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: AvaTap.minSize,
            height: AvaTap.minSize,
            child: Center(
              child: Container(
                width: circle,
                height: circle,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
