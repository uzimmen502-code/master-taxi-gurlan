import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';

/// Хабар катагидаги «ўчириш» тугмаси: аввал тасдиқ сўрайди, кейин [onDelete].
class NewsDeleteButton extends StatelessWidget {
  const NewsDeleteButton({
    super.key,
    required this.onDelete,
    this.titleKey = 'news_delete_title',
    this.bodyKey = 'news_delete_body',
    this.doneKey = 'news_deleted_snack',
  });

  final Future<void> Function() onDelete;

  /// Тасдиқ матнлари (масалан, «Админ билан чат» — тарих тозаланади, қатор қолади).
  final String titleKey;
  final String bodyKey;
  final String doneKey;

  Future<void> _ask(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(titleKey)),
        content: Text(ctx.tr(bodyKey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('news_delete_cancel')),
          ),
          TextButton(
            key: const ValueKey('news-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              ctx.tr('news_delete_confirm'),
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await onDelete();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.tr(doneKey))));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('news-delete'),
      tooltip: context.tr('news_delete_tooltip'),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
      icon: Icon(Icons.delete_outline, color: Colors.grey.shade600, size: 22),
      onPressed: () => _ask(context),
    );
  }
}
