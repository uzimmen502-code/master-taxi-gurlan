// Таом формасида расм ЁНИДАГИ «Видео» катак (эга, 2026-10-19: «расм ёнига ихтиёрий видео
// қўшиш мумкин бўлсин, видео АВАГрамга ҳам жойлансин»).
//
// Катак ҳолатни кўрсатади (йўқ · текширувда · жонли · рад этилган · хато); босилса варақ
// очилади ва ичида ресторан видеоси билан БИР ХИЛ карта ([RestaurantVideoCard], таом режимида):
// қўшиш/алмаштириш/ўчириш, АВАГрамда очиш. Жойлаш ва боғлаш — умумий қатламда
// ([TvClipLink.publish], `restaurant_item`): клип АВАГрам лентасига оддий клип сифатида тушади
// (модерация, R2 — ўша қатлам), янги нусха йўқ.
//
// Таом ҳали САҚЛАНМАГАН бўлса (янги таом) клип унга боғланиши учун ID керак — шунинг учун босилганда
// аввал [ensureSaved] таомни сақлайди (хато бўлса — `null`, хабар форманинг ўзида).

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/services/tv_clip_link.dart';
import 'restaurant_video_card.dart';

class DishVideoTile extends StatefulWidget {
  const DishVideoTile({
    super.key,
    required this.restaurantId,
    required this.ownerPhone,
    required this.restaurantApproved,
    required this.itemId,
    required this.ensureSaved,
    this.size = 140,
    this.currentPhone,
    this.loader,
    this.publisher,
    this.deleter,
    this.opener,
  });

  final String restaurantId;
  final String ownerPhone;
  final bool restaurantApproved;

  /// Таом ID'си; `null` — таом ҳали сақланмаган.
  final String? itemId;

  /// Янги таомни сақлайди ва ID қайтаради; сақлаб бўлмаса `null`.
  final Future<String?> Function() ensureSaved;
  final double size;
  final String? currentPhone;

  /// Тест учун алмаштириладиган боғловчилар (ҳақиқийси — умумий қатлам).
  final Future<List<TvClip>> Function(String itemId)? loader;
  final Future<bool> Function(String itemId)? publisher;
  final Future<void> Function(TvClip clip)? deleter;
  final void Function(TvClip clip)? opener;

  @override
  State<DishVideoTile> createState() => _DishVideoTileState();
}

class _DishVideoTileState extends State<DishVideoTile> {
  late String? _itemId = widget.itemId;
  List<TvClip> _clips = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DishVideoTile old) {
    super.didUpdateWidget(old);
    // Таом ташқарида сақланган бўлса (форманинг «Сақлаш»и) — ID'ни қабул қиламиз.
    if (_itemId == null && widget.itemId != null) {
      _itemId = widget.itemId;
      _load();
    }
  }

  Future<void> _load() async {
    final id = _itemId;
    if (id == null) return;
    try {
      final clips = widget.loader != null
          ? await widget.loader!(id)
          : await TvClipsRepository().fetchItemClips(restaurantId: widget.restaurantId, itemId: id);
      if (!mounted) return;
      setState(() => _clips = clips);
    } catch (_) {
      // Катак ҳолатни кўрсатолмаса — «қўшиш» ҳолатида қолади; варақ ўзи хатони кўрсатади.
    }
  }

  Future<void> _openSheet() async {
    if (_busy) return;
    var id = _itemId;
    if (id == null) {
      setState(() => _busy = true);
      try {
        id = await widget.ensureSaved();
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (id == null || !mounted) return;
      setState(() => _itemId = id);
    }
    final itemId = id;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          child: RestaurantVideoCard(
            restaurantId: widget.restaurantId,
            ownerPhone: widget.ownerPhone,
            restaurantApproved: widget.restaurantApproved,
            linkItemId: itemId,
            currentPhone: widget.currentPhone,
            loader: widget.loader == null ? null : () => widget.loader!(itemId),
            publisher: widget.publisher == null ? null : () => widget.publisher!(itemId),
            deleter: widget.deleter,
            opener: widget.opener,
          ),
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final clip = _clips.isEmpty ? null : _clips.first;
    final status = clip == null ? null : TvClipLink.statusKey(clip);
    final (IconData icon, Color fg) = switch (status) {
      'active' => (Icons.play_circle_fill_rounded, c.ok),
      'pending' => (Icons.hourglass_top_rounded, c.warn),
      'blocked' || 'error' => (Icons.error_outline_rounded, c.danger),
      'other' => (Icons.videocam_off_outlined, c.ink3),
      _ => (Icons.videocam_outlined, c.ink3),
    };
    final label = status == null ? context.tr('restaurants_m_dish_video_add') : context.tr('restaurants_m_dish_video_st_$status');
    final title = context.tr('restaurants_m_dish_video_tile');
    return Semantics(
      button: true,
      label: '$title. $label',
      onTap: _openSheet,
      child: ExcludeSemantics(
        child: InkWell(
          key: const ValueKey('dish-video-tile'),
          onTap: _busy ? null : _openSheet,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: widget.size,
            height: widget.size,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: status == null ? c.line : fg.withValues(alpha: 0.6), width: status == null ? 1 : 1.5),
            ),
            child: _busy
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                // Катта шрифт (×2) ва тор катакда мазмун КИЧРАЯДИ (кесилмайди ва overflow бермайди).
                : Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 32, color: fg),
                          const SizedBox(height: 4),
                          Text(title, style: AvaText.caption.copyWith(color: c.ink, fontWeight: FontWeight.w700)),
                          Text(
                            label,
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style: AvaText.caption.copyWith(color: status == null ? c.ink3 : fg),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
