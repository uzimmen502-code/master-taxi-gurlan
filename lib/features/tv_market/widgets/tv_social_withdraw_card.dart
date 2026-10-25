import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../models/tv_clip.dart';
import '../services/tv_social.dart';

/// Клип қайси AVA расмий тармоқларига жойланади — сервер қоидаси билан бир хил
/// (`functions/tv_social_publish.js` `requestedNetworks`): тармоқ танланган бўлса
/// фақат `socialConsent == true` билан; эски клип (тармоқсиз, розилик бор) — барчаси.
/// Пуллик реклама бу ерда йўқ (мажбурий тармоқлар, розилик қайтарилмайди).
List<String> tvSocialTargets(TvClip clip) {
  if (clip.isAd || !clip.socialConsent) return const [];
  return clip.socialNetworks.isNotEmpty ? clip.socialNetworks : TvSocial.ordered;
}

/// Сервер жойлаб бўлган тармоқлар (`socialPost.networks.<id>.status == 'posted'`).
List<String> tvSocialPostedNetworks(TvClip clip) {
  final nets = clip.socialPost['networks'];
  if (nets is! Map) return const [];
  return [
    for (final id in TvSocial.known)
      if (nets[id] is Map && '${(nets[id] as Map)['status'] ?? ''}' == 'posted') id,
  ];
}

/// Эга ўз клипини таҳрирлаганда (7-босқич давоми, 2026-10-25): AVA саҳифаларига
/// жойлаш розилигини қайтариб олиш. Қайтарилгач сервер клипни ҳеч бир тармоққа
/// (қайта уриниш ёки модерациядан кейин ҳам) жойламайди; аллақачон чиққан пост эса
/// тармоқнинг ўзида қолади — бу очиқ айтилади.
class TvSocialWithdrawCard extends StatefulWidget {
  const TvSocialWithdrawCard({super.key, required this.clip, required this.onWithdraw});

  final TvClip clip;
  final Future<void> Function() onWithdraw;

  @override
  State<TvSocialWithdrawCard> createState() => _TvSocialWithdrawCardState();
}

class _TvSocialWithdrawCardState extends State<TvSocialWithdrawCard> {
  bool _busy = false;
  bool _done = false;

  String _names(BuildContext context, List<String> ids) =>
      [for (final id in ids) context.tr(TvSocial.labelKey(id))].join(', ');

  Future<void> _withdraw() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.tr('tv_social_withdraw_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(
            key: const ValueKey('tv_social_withdraw_yes'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('tv_social_withdraw_button')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onWithdraw();
      if (!mounted) return;
      setState(() => _done = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('tv_social_withdraw_done'))));
    } catch (e) {
      debugPrint('[TvSocialWithdraw] $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('tv_social_withdraw_err'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = tvSocialTargets(widget.clip);
    if (targets.isEmpty || _done) return const SizedBox.shrink();
    final posted = tvSocialPostedNetworks(widget.clip);
    final text = posted.isEmpty
        ? context.tr('tv_social_withdraw_pending').replaceAll('{networks}', _names(context, targets))
        : context.tr('tv_social_withdraw_posted').replaceAll('{networks}', _names(context, posted));
    return Card(
      key: const ValueKey('tv_social_withdraw_card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('tv_social_withdraw_title'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(text, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('tv_social_withdraw'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: _busy ? null : _withdraw,
                icon: const Icon(Icons.block_rounded),
                label: Text(context.tr('tv_social_withdraw_button')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
