// Кўчмас мулк эълонини ТАҲРИРЛАШ экранидаги ихтиёрий видео картаси (эга қарори 2026-10-19:
// «сотиш / ижарада фойдаланувчи ИХТИЁРИЙ, максимум 60 секундлик видео жойлаштириши мумкин, видео
// АВАГрамга жойлаштирилади; эълон ўчирилса видео ҳам ўчирилади»).
//
// Жойлаш ва боғлаш — умумий қатламда ([TvClipLink.publish], `realty_listing`): клип АВАГрам
// лентасига оддий клип сифатида тушади (модерация, R2 — ўша қатлам), янги тизим йўқ. Бир эълонда
// битта видео: янгиси жонли бўлгач эскиси ўчади ([TvClipLink.supersededClips]). 60 сония чегараси
// ва эълон ўчганда клипни ўчириш — сервердa (`tv_clip_limits.js`, `functions/realty_video.js`).
//
// Бу карта ресторан/таом видео картаси ([RestaurantVideoCard]) билан бир хил нақшда; ундан
// фарқи — матнлар ва тур. Ресторан картасини умумийлаштириш ресторан хулқига тегар эди (31-қоида),
// шунинг учун алоҳида, лекин барча мантиқий қисмлар умумий қатламдан олинади.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart' show canonicalPhoneId, phonesMatch;
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/services/tv_clip_link.dart';

class RealtyListingVideoCard extends StatefulWidget {
  const RealtyListingVideoCard({
    super.key,
    required this.listingId,
    required this.myPhone,
    this.loader,
    this.publisher,
    this.deleter,
    this.opener,
  });

  final String listingId;

  /// Жорий фойдаланувчи телефони — ким юклаганини ажратиш учун: ўчириш/алмаштириш фақат ўзиникига
  /// (қоида ҳам шуни талаб қилади — жамоа ходими юклаганини бошқаси ўчира олмайди).
  final String myPhone;

  /// Тест учун алмаштириладиган боғловчилар (ҳақиқийси — умумий қатлам).
  final Future<List<TvClip>> Function()? loader;
  final Future<bool> Function()? publisher;
  final Future<void> Function(TvClip clip)? deleter;
  final void Function(TvClip clip)? opener;

  @override
  State<RealtyListingVideoCard> createState() => _RealtyListingVideoCardState();
}

class _RealtyListingVideoCardState extends State<RealtyListingVideoCard> {
  List<TvClip> _clips = const [];
  bool _loading = true;
  bool _failed = false;
  bool _busy = false;
  late final String _me = canonicalPhoneId(widget.myPhone);

  bool _mine(TvClip c) => _me.isNotEmpty && phonesMatch(c.ownerPhone, _me);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<TvClip>> _fetch() => widget.loader != null
      ? widget.loader!()
      : TvClipsRepository().fetchLinkedClips(
          linkKind: TvClipLink.kindRealty,
          linkId: widget.listingId,
        );

  Future<void> _remove(TvClip c) =>
      widget.deleter != null ? widget.deleter!(c) : TvClipsRepository().deleteOwnClip(c);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      var clips = await _fetch();
      // Янги видео жонли бўлгач эскилари ортиқча (бир эълонда битта видео). Ўчириш йиқилса
      // рўйхатда қолади.
      final gone = <String>{};
      for (final stale in TvClipLink.supersededClips(clips).where(_mine)) {
        try {
          await _remove(stale);
          gone.add(stale.id);
        } catch (_) {}
      }
      if (gone.isNotEmpty) {
        clips = clips.where((c) => !gone.contains(c.id)).toList(growable: false);
      }
      if (!mounted) return;
      setState(() {
        _clips = clips;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _publish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await (widget.publisher?.call() ??
          TvClipLink.publish(
            Navigator.of(context),
            kind: TvClipLink.kindRealty,
            linkId: widget.listingId,
          ));
      if (ok && mounted) await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(TvClip clip) async {
    if (_busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.tr('realty_video_delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('realty_video_delete'))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _remove(clip);
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('realty_error_generic')), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(TvClip clip) {
    if (widget.opener != null) {
      widget.opener!(clip);
    } else {
      TvClipLink.open(context, clip);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      key: const ValueKey('realty-video-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('realty_video_card_title'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 2),
          Text(context.tr('realty_video_card_hint'), style: TextStyle(fontSize: 12, color: c.ink3)),
          const SizedBox(height: 8),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (_failed)
            Row(children: [
              Expanded(
                child: Text(context.tr('realty_video_load_failed'), style: TextStyle(fontSize: 12, color: c.danger)),
              ),
              TextButton(
                key: const ValueKey('realty-video-retry'),
                onPressed: _load,
                child: Text(context.tr('realty_video_retry')),
              ),
            ])
          else ...[
            for (final clip in _clips)
              _ClipRow(
                clip: clip,
                mine: _mine(clip),
                busy: _busy,
                onOpen: () => _open(clip),
                onDelete: () => _delete(clip),
              ),
            if (_clips.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(context.tr('realty_video_replace_hint'), style: TextStyle(fontSize: 11, color: c.ink3)),
              const SizedBox(height: 6),
            ],
            OutlinedButton.icon(
              key: const ValueKey('realty-video-publish'),
              onPressed: _busy ? null : _publish,
              icon: Icon(_clips.isEmpty ? Icons.videocam_outlined : Icons.sync_rounded, size: 18),
              label: Text(context.tr(_clips.isEmpty ? 'realty_video_add' : 'realty_video_replace')),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClipRow extends StatelessWidget {
  const _ClipRow({
    required this.clip,
    required this.mine,
    required this.busy,
    required this.onOpen,
    required this.onDelete,
  });

  final TvClip clip;
  final bool mine;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final status = TvClipLink.statusKey(clip);
    final (Color fg, Color bg) = switch (status) {
      'active' => (c.ok, c.okSoft),
      'pending' => (c.warn, c.warnSoft),
      'blocked' || 'error' => (c.danger, c.dangerSoft),
      _ => (c.ink3, c.chip),
    };
    final reason = status == 'blocked' ? clip.rejectReason.trim() : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clip.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.ink)),
                const SizedBox(height: 3),
                Container(
                  key: ValueKey('realty-video-status-$status'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    context.tr('realty_video_st_$status'),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
                  ),
                ),
                if (reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(reason, style: TextStyle(fontSize: 11, color: c.ink3)),
                  ),
                if (!mine)
                  Padding(
                    key: ValueKey('realty-video-by-colleague-${clip.id}'),
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(context.tr('realty_video_by_colleague'), style: TextStyle(fontSize: 11, color: c.ink3)),
                  ),
              ],
            ),
          ),
          if (status == 'active')
            IconButton(
              tooltip: context.tr('link_video_open'),
              onPressed: busy ? null : onOpen,
              icon: const Icon(Icons.play_circle_outline_rounded),
            ),
          if (mine)
            IconButton(
              key: ValueKey('realty-video-delete-${clip.id}'),
              tooltip: context.tr('realty_video_delete'),
              onPressed: busy ? null : onDelete,
              icon: Icon(Icons.delete_outline, color: c.danger),
            ),
        ],
      ),
    );
  }
}
