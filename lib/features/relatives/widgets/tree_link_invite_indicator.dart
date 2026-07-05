import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/tree_link_invite.dart';
import '../../../repositories/tree_repository.dart';
import '../l10n/relatives_l10n.dart';

/// Kutilayotgan daraxt ulash takliflari soni (real-time).
class TreeLinkInviteCount extends StatelessWidget {
  const TreeLinkInviteCount({
    super.key,
    required this.userId,
    required this.builder,
  });

  final String userId;
  final Widget Function(BuildContext context, int count) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TreeLinkInvite>>(
      stream: TreeRepository().watchIncomingInvites(userId),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        return builder(context, count);
      },
    );
  }
}

/// Tab yoki boshqa joy uchun raqamli badge.
Widget treeLinkInviteTabLabel(String label, int count) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label),
      if (count > 0) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ],
  );
}

/// AppBar / kartochka uchun link ikonkasi + badge.
class TreeLinkInviteIconButton extends StatelessWidget {
  const TreeLinkInviteIconButton({
    super.key,
    required this.userId,
    required this.onTap,
    this.color = Colors.white,
  });

  final String userId;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TreeLinkInviteCount(
      userId: userId,
      builder: (context, count) {
        return IconButton(
          tooltip: count > 0
              ? RelativesL10n.trParams(
                  context, 'rel_invite_tooltip', {'count': '$count'})
              : context.tr('rel_invite_tooltip_empty'),
          onPressed: count > 0 ? onTap : null,
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            backgroundColor: const Color(0xFFFF9800),
            child: Icon(Icons.link, color: color),
          ),
        );
      },
    );
  }
}
