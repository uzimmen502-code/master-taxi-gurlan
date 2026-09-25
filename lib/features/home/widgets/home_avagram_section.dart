import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/widgets/tv_clip_poster.dart';
import 'ava_section.dart';

/// 11-бўлим: AVAGram.
///
/// Тавсиф талаби бўйича бу ерда ФАҚАТ МУҚОВАЛАР — видео ўз-ўзидан
/// ўйнамайди. Эски `HomeVideoStage` экран баландлигининг 80% ини
/// эгаллаган карточкаларда видеони овозсиз автоматик ўйнатар,
/// `TvPlayerPool` ни ушлаб турар ва HLS сегментларини олдиндан
/// юкларди. Ўйнатиш энди фақат AVAGram экранида.
class HomeAvagramSection extends StatefulWidget {
  const HomeAvagramSection({
    super.key,
    required this.onOpenAll,
    required this.onOpenClip,
  });

  /// «Барчаси →» — AVAGram экрани.
  final VoidCallback onOpenAll;

  /// Муқова босилганда — ўша клипдан бошлаб очиш.
  final void Function(TvClip clip) onOpenClip;

  static const limit = 5;

  @override
  State<HomeAvagramSection> createState() => _HomeAvagramSectionState();
}

class _HomeAvagramSectionState extends State<HomeAvagramSection> {
  final _repo = TvClipsRepository();

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<TvClip> _clips = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _status = AvaSectionStatus.loading);
    try {
      final page = await _repo.fetchHomePage(
        districtId: ServiceConfigHolder.districtId,
        limit: HomeAvagramSection.limit,
      );
      if (!mounted) return;
      setState(() {
        _clips = page.clips;
        _status = page.clips.isEmpty
            ? AvaSectionStatus.empty
            : AvaSectionStatus.ready;
      });
    } catch (e) {
      debugPrint('[HomeAvagram] $e');
      if (!mounted) return;
      setState(() => _status = AvaSectionStatus.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AvaSection(
      title: context.tr('home_module_tv_market'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _load,
      skeletonRows: 1,
      child: SizedBox(
        // Муқова 140 + оралиқ 4 + сарлавҳанинг бир қатори. Қатъий 168
        // бўлса, шрифт катталашганда ёзув муқовадан тошиб кетади.
        height: 144 +
            MediaQuery.textScalerOf(context)
                .scale(AvaText.caption.fontSize ?? 12) *
                1.5,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: _clips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) => _ClipCover(
            clip: _clips[i],
            onTap: () => widget.onOpenClip(_clips[i]),
          ),
        ),
      ),
    );
  }
}

class _ClipCover extends StatelessWidget {
  const _ClipCover({required this.clip, required this.onTap});

  final TvClip clip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AvaRadius.card),
      child: SizedBox(
        width: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AvaRadius.card),
              child: SizedBox(
                height: 140,
                width: 112,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: c.surface2),
                    TvClipPoster(url: clip.posterUrl),
                    // Видео эканини билдирувчи белги — автоматик
                    // ўйнатиш ўрнига.
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius:
                              BorderRadius.circular(AvaRadius.chip),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(3),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              clip.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AvaText.caption.copyWith(color: c.ink2),
            ),
          ],
        ),
      ),
    );
  }
}
