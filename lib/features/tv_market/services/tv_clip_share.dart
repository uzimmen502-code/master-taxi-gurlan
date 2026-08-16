import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';

const kTvMarketShareUrl = 'https://master-taxi-gurlan.web.app/downloads/';

Future<void> shareTvClip(TvClip clip) async {
  final lines = <String>[
    if (clip.title.trim().isNotEmpty) clip.title.trim(),
    if (clip.hasPrice) formatMoney(clip.price),
    if (clip.districtLabel.trim().isNotEmpty) clip.districtLabel.trim(),
    'AVA',
    kTvMarketShareUrl,
  ];
  await Share.share(lines.join('\n'));
}
