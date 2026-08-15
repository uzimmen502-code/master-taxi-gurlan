import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';
import '../screens/tv_market_feed_screen.dart';
import '../services/tv_player_pool.dart';
import 'tv_clip_poster.dart';

/// Home пастидаги овозсиз видеолар — пастга скролл кейинги клип, босиш → feed.
class HomeVideoStage extends StatefulWidget {
  const HomeVideoStage({super.key});

  @override
  State<HomeVideoStage> createState() => _HomeVideoStageState();
}

class _HomeVideoStageState extends State<HomeVideoStage> {
  final _repo = TvClipsRepository();
  final _pool = TvPlayerPool();
  final _cardKeys = <GlobalKey>[];

  List<TvClip> _clips = const [];
  bool _loading = true;
  int _activeIndex = 0;
  ScrollPosition? _scrollPos;
  bool _pickScheduled = false;
  int _playGen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pos = Scrollable.maybeOf(context)?.position;
    if (!identical(pos, _scrollPos)) {
      _scrollPos?.removeListener(_onScroll);
      _scrollPos = pos;
      _scrollPos?.addListener(_onScroll);
    }
  }

  Future<void> _load() async {
    try {
      final clips = await _repo.fetchHomeClips(
        districtId: ServiceConfigHolder.districtId,
        limit: 5,
      );
      if (!mounted) return;
      _cardKeys
        ..clear()
        ..addAll(List.generate(clips.length, (_) => GlobalKey()));
      setState(() {
        _clips = clips;
        _loading = false;
        _activeIndex = 0;
      });
      if (clips.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_syncPlayback());
        });
      }
    } catch (e) {
      debugPrint('[HomeVideoStage] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() => _schedulePick();

  void _schedulePick() {
    if (_pickScheduled) return;
    _pickScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pickScheduled = false;
      if (mounted) _pickActive();
    });
  }

  void _pickActive() {
    if (_clips.isEmpty) return;
    final mq = MediaQuery.of(context);
    final screen = Offset.zero & mq.size;
    var best = _activeIndex;
    var bestFrac = 0.0;
    for (var i = 0; i < _cardKeys.length; i++) {
      final box = _cardKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final inter = rect.intersect(screen);
      if (inter.isEmpty) continue;
      final frac = inter.height / rect.height;
      if (frac > bestFrac) {
        bestFrac = frac;
        best = i;
      }
    }
    if (bestFrac < 0.4) {
      _pool.pauseAllExcept('');
      return;
    }
    if (best == _activeIndex) return;
    setState(() => _activeIndex = best);
    unawaited(_syncPlayback());
  }

  List<String> _urlsAround(int index) {
    final urls = <String>[];
    void add(int i) {
      if (i >= 0 && i < _clips.length) {
        final url = _clips[i].videoUrl;
        if (url.isNotEmpty) urls.add(url);
      }
    }

    add(index);
    add(index + 1);
    add(index - 1);
    return urls;
  }

  Future<void> _syncPlayback() async {
    if (_clips.isEmpty) return;
    final gen = ++_playGen;
    final clip = _clips[_activeIndex];
    _pool.pauseAllExcept(clip.videoUrl);
    final ctrl = await _pool.prepare(clip.videoUrl);
    if (!mounted || gen != _playGen) return;
    if (ctrl != null && ctrl.value.isInitialized) {
      await ctrl.setVolume(0);
      await ctrl.play();
      if (mounted) setState(() {});
    }
    unawaited(_pool.retain(_urlsAround(_activeIndex)));
  }

  void _openFeed(TvClip clip) {
    _pool.pauseAllExcept('');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvMarketFeedScreen(initialClip: clip),
      ),
    ).then((_) {
      if (mounted) unawaited(_syncPlayback());
    });
  }

  Future<void> _onContact(TvClip clip) async {
    final ok = await callPhone(clip.ownerPhone);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_call_failed'))),
      );
    }
  }

  @override
  void dispose() {
    _scrollPos?.removeListener(_onScroll);
    unawaited(_pool.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_clips.isEmpty) return const SizedBox.shrink();

    final cardH = MediaQuery.sizeOf(context).height * 0.80;

    return Column(
      children: [
        for (var i = 0; i < _clips.length; i++)
          Padding(
            key: _cardKeys[i],
            padding: EdgeInsets.only(top: i == 0 ? 8 : 10),
            child: _HomeClipCard(
              clip: _clips[i],
              height: cardH,
              playing: i == _activeIndex,
              controller: _pool[_clips[i].videoUrl],
              onOpen: () => _openFeed(_clips[i]),
              onContact: () => _onContact(_clips[i]),
            ),
          ),
      ],
    );
  }
}

class _HomeClipCard extends StatelessWidget {
  const _HomeClipCard({
    required this.clip,
    required this.height,
    required this.playing,
    required this.controller,
    required this.onOpen,
    required this.onContact,
  });

  final TvClip clip;
  final double height;
  final bool playing;
  final VideoPlayerController? controller;
  final VoidCallback onOpen;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final ready = playing &&
        controller != null &&
        controller!.value.isInitialized;
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TvClipPoster(url: clip.posterUrl),
            if (ready)
              Center(
                child: AspectRatio(
                  aspectRatio: controller!.value.aspectRatio,
                  child: VideoPlayer(controller!),
                ),
              ),
            Positioned(
              top: 8,
              left: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  context.tr('home_module_tv_market'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 80,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniBtn(
                    icon: Icons.favorite_border_rounded,
                    label: clip.likeCount > 0 ? '${clip.likeCount}' : '',
                  ),
                  const SizedBox(height: 12),
                  const _MiniBtn(
                      icon: Icons.chat_bubble_outline_rounded, label: ''),
                  const SizedBox(height: 12),
                  const _MiniBtn(icon: Icons.send_rounded, label: ''),
                  const SizedBox(height: 12),
                  const _MiniBtn(
                      icon: Icons.bookmark_border_rounded, label: ''),
                ],
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.white24,
                        child:
                            Icon(Icons.person, color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '@${clip.ownerName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            shadows: [
                              Shadow(blurRadius: 4, color: Colors.black54)
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    clip.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      shadows: [
                        Shadow(blurRadius: 4, color: Colors.black54)
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (clip.hasPrice) ...[
                        Text(
                          formatMoney(clip.price),
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Icon(Icons.location_on,
                          color: Colors.white70, size: 13),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          clip.districtLabel,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: onContact,
                      icon: const Icon(Icons.chat_bubble_outline_rounded,
                          size: 17),
                      label: Text(
                        context.tr('tv_market_contact'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: Colors.white,
          size: 24,
          shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
        ),
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
