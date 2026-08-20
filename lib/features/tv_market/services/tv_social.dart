import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';

/// Расмий AVA саҳифалари + фойдаланувчининг ўз IG/FB/TT улашиши.
class TvSocial {
  TvSocial._();

  static const instagram = 'instagram';
  static const facebook = 'facebook';
  static const tiktok = 'tiktok';
  static const ordered = [instagram, facebook, tiktok];

  static String labelKey(String id) => 'tv_social_$id';

  static List<String> parse(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final e in raw) {
      final id = '$e'.trim().toLowerCase();
      if (ordered.contains(id) && !out.contains(id)) out.add(id);
    }
    return out;
  }

  static Uri officialOpenUri(String network) {
    switch (network) {
      case facebook:
        return Uri.parse('https://www.facebook.com/');
      case tiktok:
        return Uri.parse('https://www.tiktok.com/tiktokstudio/upload');
      default:
        return Uri.parse('https://www.instagram.com/');
    }
  }

  static Future<void> shareLocalVideo(String filePath) async {
    if (kIsWeb || filePath.trim().isEmpty) return;
    await Share.shareXFiles([XFile(filePath)]);
  }

  static Future<void> openOfficialComposer({
    required String network,
    required String videoUrl,
  }) async {
    if (videoUrl.trim().isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: videoUrl.trim()));
    }
    final uri = officialOpenUri(network);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> showPublishFollowUp(
    BuildContext context, {
    required String filePath,
    required List<String> networks,
  }) async {
    if (networks.isEmpty || !context.mounted) return;
    final names = [
      for (final id in ordered)
        if (networks.contains(id)) context.tr(labelKey(id)),
    ].join(', ');
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ctx.tr('tv_social_share_now'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ctx.tr('tv_social_share_now_hint').replaceAll('{apps}', names),
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () async {
                    await shareLocalVideo(filePath);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(ctx.tr('tv_social_share_button')),
                ),
                const SizedBox(height: 8),
                Text(
                  ctx.tr('tv_social_admin_pending'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
