import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/app_share.dart';
import '../models/tv_clip.dart';

Future<void> shareTvClip(TvClip clip) async {
  final lines = <String>[
    if (clip.title.trim().isNotEmpty) clip.title.trim(),
    if (clip.hasPrice) formatMoney(clip.price),
    if (clip.districtLabel.trim().isNotEmpty) clip.districtLabel.trim(),
    'AVA',
    kAvaAppDownloadPage,
  ];
  await Share.share(lines.join('\n'));
}
