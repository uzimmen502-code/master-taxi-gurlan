import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';

/// Тасдиқ диалоги + ўчириш. Муваффақиятда `true`.
Future<bool> confirmDeleteTvClip(BuildContext context, TvClip clip) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.tr('tv_market_delete_title')),
      content: Text(context.tr('tv_market_delete_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.tr('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            context.tr('tv_market_delete'),
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await TvClipsRepository().deleteOwnClip(clip);
  return true;
}
