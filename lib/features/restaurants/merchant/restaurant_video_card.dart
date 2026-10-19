// Ресторан панели («Дўкон») — таомлар обзори видеоси: қўшиш, алмаштириш,
// ўчириш, ҳолатини кўриш (эга, 2026-10-18).
//
// Аввал видеони фақат рўйхатдан ўтишда қўшиш мумкин эди — ўтказиб юборилган
// ёки рад этилган видеони кейин тузатиб бўлмасди. Энди ШУ ердан: бутун
// жойлаш/боғлаш мантиқи ўша умумий қатламда ([TvClipLink.publish] —
// `linkKind='restaurant'`, `linkId=ресторан id`), янги нусха йўқ.
//
// Икки алоҳида тасдиқ борлиги эгага очиқ айтилади: ресторан (админ) ва
// видео (модерация) — мижозга иккаласи ҳам тасдиқлангандан кейин кўринади.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/services/tv_clip_link.dart';

class RestaurantVideoCard extends StatefulWidget {
  const RestaurantVideoCard({
    super.key,
    required this.restaurantId,
    required this.ownerPhone,
    required this.restaurantApproved,
    this.loader,
    this.publisher,
    this.deleter,
    this.opener,
  });

  final String restaurantId;
  final String ownerPhone;

  /// Ресторан `approved` бўлмаса эгага «тасдиқдан кейин кўринади» дейилади.
  final bool restaurantApproved;

  /// Тест учун алмаштириладиган боғловчилар (ҳақиқийси — умумий қатлам).
  final Future<List<TvClip>> Function()? loader;
  final Future<bool> Function()? publisher;
  final Future<void> Function(TvClip clip)? deleter;
  final void Function(TvClip clip)? opener;

  @override
  State<RestaurantVideoCard> createState() => _RestaurantVideoCardState();
}

class _RestaurantVideoCardState extends State<RestaurantVideoCard> {
  List<TvClip> _clips = const [];
  bool _loading = true;
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<TvClip>> _fetch() => widget.loader != null
      ? widget.loader!()
      : TvClipsRepository().fetchOwnLinked(
          linkId: widget.restaurantId,
          ownerPhone: widget.ownerPhone,
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
      // Янги видео жонли бўлгач эскилари ортиқча (бир ресторанда битта
      // видео) — шу ерда тозаланади. Ўчириш йиқилса рўйхатда қолади.
      final gone = <String>{};
      for (final stale in TvClipLink.supersededClips(clips)) {
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
            kind: TvClipLink.kindRestaurant,
            linkId: widget.restaurantId,
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
        content: Text(ctx.tr('restaurants_m_video_delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('restaurants_m_delete'))),
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
          SnackBar(content: Text(context.tr('restaurants_err_generic')), backgroundColor: Colors.red.shade700),
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
      key: const ValueKey('restaurant-video-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('restaurants_m_video_title'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 2),
          Text(context.tr('restaurants_m_video_hint'), style: TextStyle(fontSize: 12, color: c.ink3)),
          if (!widget.restaurantApproved) ...[
            const SizedBox(height: 4),
            Text(context.tr('restaurants_m_video_after_approval'), style: TextStyle(fontSize: 12, color: c.warn)),
          ],
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
          else if (_failed)
            Row(children: [
              Expanded(child: Text(context.tr('restaurants_m_video_load_failed'), style: TextStyle(fontSize: 12, color: c.danger))),
              TextButton(key: const ValueKey('video-retry'), onPressed: _load, child: Text(context.tr('restaurants_m_video_retry'))),
            ])
          else ...[
            for (final clip in _clips) _ClipRow(clip: clip, busy: _busy, onOpen: () => _open(clip), onDelete: () => _delete(clip)),
            if (_clips.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(context.tr('restaurants_m_video_replace_hint'), style: TextStyle(fontSize: 11, color: c.ink3)),
              const SizedBox(height: 6),
            ],
            OutlinedButton.icon(
              key: const ValueKey('video-publish'),
              onPressed: _busy ? null : _publish,
              icon: Icon(_clips.isEmpty ? Icons.videocam_outlined : Icons.sync_rounded, size: 18),
              label: Text(context.tr(_clips.isEmpty ? 'restaurants_m_video_add' : 'restaurants_m_video_replace')),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClipRow extends StatelessWidget {
  const _ClipRow({required this.clip, required this.busy, required this.onOpen, required this.onDelete});

  final TvClip clip;
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
                  key: ValueKey('video-status-$status'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                  child: Text(context.tr('restaurants_m_video_st_$status'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
                ),
                if (reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(reason, style: TextStyle(fontSize: 11, color: c.ink3)),
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
          IconButton(
            key: ValueKey('video-delete-${clip.id}'),
            tooltip: context.tr('restaurants_m_delete'),
            onPressed: busy ? null : onDelete,
            icon: Icon(Icons.delete_outline, color: c.danger),
          ),
        ],
      ),
    );
  }
}
