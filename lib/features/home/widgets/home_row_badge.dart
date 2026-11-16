import 'package:flutter/material.dart';

import '../../../core/theme/ava_tokens.dart';

/// Уйдаги бир қаторли рўйхатларда (Эълонлар, Кафе-ресторанлар) кичик белги: «Мол», «Уй-жой», «Уй таоми».
/// Расмли карточкалардаги [MarketCornerBadge] нинг матнли қатор учун ихчам шакли. Бўш матн — ҳеч нарса.
class HomeRowBadge extends StatelessWidget {
  const HomeRowBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final c = context.ava;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AvaText.feedRow.copyWith(
          color: c.brandText,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}
