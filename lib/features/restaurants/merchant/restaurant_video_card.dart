// Ресторан панели («Дўкон») — таомлар обзори видеоси: қўшиш, алмаштириш,
// ўчириш, ҳолатини кўриш (эга, 2026-10-18).
//
// Ўша карта БИТТА ТАОМнинг видеоси учун ҳам ишлатилади (`linkItemId` берилса — эга,
// 2026-10-19: «таом расми ёнига ихтиёрий видео, АВАГрамга ҳам жойлансин»): `restaurant_item` тури,
// `linkId` — ресторан, `linkItemId` — таом; бир таомда битта видео, янгиси жонли бўлгач эскиси
// ўчади. Ресторан видеоси ва таом видеолари ЎЗАРО аралашмайди (тур бўйича сузилади).
//
// Аввал видеони фақат рўйхатдан ўтишда қўшиш мумкин эди — ўтказиб юборилган
// ёки рад этилган видеони кейин тузатиб бўлмасди. Энди ШУ ердан: бутун
// жойлаш/боғлаш мантиқи ўша умумий қатламда ([TvClipLink.publish] —
// `linkKind='restaurant'`, `linkId=ресторан id`), янги нусха йўқ.
//
// Икки алоҳида тасдиқ борлиги эгага очиқ айтилади: ресторан (админ) ва
// видео (модерация) — мижозга иккаласи ҳам тасдиқлангандан кейин кўринади.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart' show canonicalPhoneId, phonesMatch;
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/services/tv_clip_link.dart';

class RestaurantVideoCard extends StatefulWidget {
  const RestaurantVideoCard({
    super.key,
    required this.restaurantId,
    required this.ownerPhone,
    required this.restaurantApproved,
    this.linkItemId = '',
    this.currentPhone,
    this.loader,
    this.publisher,
    this.deleter,
    this.opener,
  });

  final String restaurantId;
  final String ownerPhone;

  /// Ресторан `approved` бўлмаса эгага «тасдиқдан кейин кўринади» дейилади.
  final bool restaurantApproved;

  /// Бўш — ресторан видеоси; берилса — шу ТАОМнинг видеоси.
  final String linkItemId;

  /// Жорий фойдаланувчи телефони (ким юклаганини ажратиш учун). Берилмаса
  /// кириш ҳисобидан олинади.
  final String? currentPhone;

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
  late final String _me = _resolveMe();

  bool get _forDish => widget.linkItemId.isNotEmpty;
  String get _kind => _forDish ? TvClipLink.kindRestaurantItem : TvClipLink.kindRestaurant;

  String _resolveMe() {
    final given = widget.currentPhone;
    if (given != null) return canonicalPhoneId(given);
    try {
      return canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
    } catch (_) {
      return '';
    }
  }

  /// Клипни ЎЗИМ юкладимми: ўчириш/алмаштириш фақат ўзиникига (қоида ҳам
  /// шуни талаб қилади — бошқа ходим юклаганини ўчириб бўлмайди).
  bool _mine(TvClip c) => _me.isNotEmpty && phonesMatch(c.ownerPhone, _me);

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Эга ва БАРЧА ходимлар (`members`) юклаган видеолар. `members`ни фақат
  /// а'золар ўқий олади — бу панел шундайларга очилади; ўқилмаса фақат эга.
  Future<List<TvClip>> _fetch() async {
    if (widget.loader != null) return widget.loader!();
    final repo = TvClipsRepository();
    // Таом видеоси: телефон бўйича сузилмайди (ваколат қоидада) — membersни ўқиш шарт эмас.
    if (_forDish) return repo.fetchItemClips(restaurantId: widget.restaurantId, itemId: widget.linkItemId);
    final phones = <String>{widget.ownerPhone};
    try {
      final m = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('members')
          .get();
      phones.addAll(m.docs.map((d) => d.id));
    } catch (_) {}
    // Тур билан: таом видеолари ҳам `linkId` = ресторан id — турсиз ўқилса ресторан видеоси ўрнига ўтарди.
    return repo.fetchLinkedByPhones(
      linkId: widget.restaurantId,
      ownerPhones: phones,
      linkKind: TvClipLink.kindRestaurant,
    );
  }

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
            kind: _kind,
            linkId: widget.restaurantId,
            linkItemId: widget.linkItemId,
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
      key: ValueKey(_forDish ? 'dish-video-card' : 'restaurant-video-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr(_forDish ? 'restaurants_m_dish_video_title' : 'restaurants_m_video_title'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 2),
          Text(context.tr(_forDish ? 'restaurants_m_dish_video_hint' : 'restaurants_m_video_hint'),
              style: TextStyle(fontSize: 12, color: c.ink3)),
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
            for (final clip in _clips)
              _ClipRow(clip: clip, mine: _mine(clip), busy: _busy, onOpen: () => _open(clip), onDelete: () => _delete(clip)),
            if (_clips.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(context.tr('restaurants_m_video_replace_hint'), style: TextStyle(fontSize: 12, color: c.ink3)),
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
  const _ClipRow({required this.clip, required this.mine, required this.busy, required this.onOpen, required this.onDelete});

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
                  key: ValueKey('video-status-$status'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                  child: Text(context.tr('restaurants_m_video_st_$status'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
                ),
                if (reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(reason, style: TextStyle(fontSize: 12, color: c.ink3)),
                  ),
                if (!mine)
                  Padding(
                    key: ValueKey('video-by-colleague-${clip.id}'),
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(context.tr('restaurants_m_video_by_colleague'), style: TextStyle(fontSize: 12, color: c.ink3)),
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
