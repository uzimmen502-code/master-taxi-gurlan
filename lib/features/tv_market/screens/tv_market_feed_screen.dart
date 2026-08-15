import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/utils/phone_launcher.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';
import '../services/tv_player_pool.dart';
import '../widgets/tv_clip_overlay.dart';
import '../widgets/tv_clip_poster.dart';
import '../widgets/tv_play_pause_badge.dart';
import 'tv_publish_screen.dart';

/// TV Market — тўлиқ экран вертикал видео лента.
class TvMarketFeedScreen extends StatefulWidget {
  const TvMarketFeedScreen({super.key, this.initialClip});

  /// Уйдаги клипдан тўлиқ feedга кирганда — шундан давом этади.
  final TvClip? initialClip;

  @override
  State<TvMarketFeedScreen> createState() => _TvMarketFeedScreenState();
}

class _TvMarketFeedScreenState extends State<TvMarketFeedScreen> {
  final _repo = TvClipsRepository();
  final _pool = TvPlayerPool();
  final _clips = <TvClip>[];
  bool _loading = true;
  int _currentIndex = 0;
  late final PageController _pageCtrl;
  bool _showPlayPause = false;
  Timer? _hideBadgeTimer;
  int _activateGen = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _loadClips();
  }

  Future<void> _loadClips() async {
    final districtId = ServiceConfigHolder.districtId;
    if (districtId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      var nearby = await _repo.fetchNearby(districtId: districtId, limit: 30);
      if (nearby.isEmpty) {
        nearby = await _repo.fetchAllActive(limit: 30);
      }
      if (!mounted) return;
      final list = <TvClip>[];
      if (widget.initialClip != null) {
        list.add(widget.initialClip!);
        list.addAll(nearby.where((c) => c.id != widget.initialClip!.id));
      } else {
        list.addAll(nearby);
      }
      setState(() {
        _clips
          ..clear()
          ..addAll(list);
        _loading = false;
        _currentIndex = 0;
      });
      if (_clips.isNotEmpty) unawaited(_activate(0));
    } catch (e) {
      debugPrint('[TvMarketFeed] load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  VideoPlayerController? get _activeCtrl {
    if (_clips.isEmpty || _currentIndex >= _clips.length) return null;
    return _pool[_clips[_currentIndex].videoUrl];
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

  Future<void> _activate(int index) async {
    if (index < 0 || index >= _clips.length) return;
    final gen = ++_activateGen;
    final clip = _clips[index];
    _pool.pauseAllExcept(clip.videoUrl);

    final ctrl = await _pool.prepare(clip.videoUrl);
    if (!mounted || gen != _activateGen || _currentIndex != index) return;
    if (ctrl != null && ctrl.value.isInitialized) {
      if (!mounted || gen != _activateGen) return;
      setState(() => _showPlayPause = false);
      await ctrl.setVolume(1);
      await ctrl.play();
    }
    unawaited(_pool.retain(_urlsAround(index)));
  }

  void _onPageChanged(int index) {
    _hideBadgeTimer?.cancel();
    _showPlayPause = false;
    _currentIndex = index;
    HapticFeedback.lightImpact();
    setState(() {});
    unawaited(_activate(index));
  }

  void _togglePlayPause() {
    final ctrl = _activeCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    _hideBadgeTimer?.cancel();
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      setState(() => _showPlayPause = true);
    } else {
      ctrl.play();
      setState(() => _showPlayPause = true);
      _hideBadgeTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        if (_activeCtrl?.value.isPlaying == true) {
          setState(() => _showPlayPause = false);
        }
      });
    }
  }

  Future<void> _onContact(TvClip clip) async {
    final ok = await callPhone(clip.ownerPhone);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_call_failed'))),
      );
    }
  }

  Future<void> _openPublish() async {
    _activeCtrl?.pause();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TvPublishScreen()),
    );
    if (result == true && mounted) {
      await _loadClips();
    } else if (mounted) {
      _activeCtrl?.play();
    }
  }

  @override
  void dispose() {
    _hideBadgeTimer?.cancel();
    unawaited(_pool.dispose());
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          context.tr('home_module_tv_market'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _PublishArrowHint(),
                const SizedBox(width: 4),
                Tooltip(
                  message: context.tr('tv_publish_fab'),
                  child: Material(
                    color: const Color(0xFFFF1744),
                    borderRadius: BorderRadius.circular(14),
                    elevation: 6,
                    shadowColor: const Color(0xFFFF1744),
                    child: InkWell(
                      onTap: _openPublish,
                      borderRadius: BorderRadius.circular(14),
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Icons.photo_camera,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _clips.isEmpty
              ? _EmptyFeed(onPublish: _openPublish)
              : PageView.builder(
                  controller: _pageCtrl,
                  scrollDirection: Axis.vertical,
                  physics: const PageScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  itemCount: _clips.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final clip = _clips[index];
                    final isActive = index == _currentIndex;
                    final ctrl = _pool[clip.videoUrl];
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        TvClipPoster(url: clip.posterUrl),
                        if (isActive &&
                            ctrl != null &&
                            ctrl.value.isInitialized)
                          Center(
                            child: AspectRatio(
                              aspectRatio: ctrl.value.aspectRatio,
                              child: VideoPlayer(ctrl),
                            ),
                          ),
                        if (isActive)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _togglePlayPause,
                            ),
                          ),
                        TvClipOverlay(
                          clip: clip,
                          onContact: () => _onContact(clip),
                          onLike: () {},
                          onComment: () {},
                          onShare: () {},
                          onSave: () {},
                          onProfile: () {},
                        ),
                        if (isActive)
                          TvPlayPauseBadge(
                            playing: ctrl?.value.isPlaying ?? false,
                            visible: _showPlayPause,
                            onTap: _togglePlayPause,
                          ),
                      ],
                    );
                  },
                ),
    );
  }
}

/// Камерага қараган қалин қизил стрелка — «шу ердан қўшинг».
class _PublishArrowHint extends StatelessWidget {
  const _PublishArrowHint();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(42, 28),
      painter: _ThickRightArrowPainter(),
    );
  }
}

class _ThickRightArrowPainter extends CustomPainter {
  static const _red = Color(0xFFFF1744);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _red
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final shadow = Paint()
      ..color = const Color(0x73000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final shaftH = size.height * 0.42;
    final shaftW = size.width * 0.52;
    final cy = size.height / 2;

    final path = Path()
      ..moveTo(0, cy - shaftH / 2)
      ..lineTo(shaftW, cy - shaftH / 2)
      ..lineTo(shaftW, 0)
      ..lineTo(size.width, cy)
      ..lineTo(shaftW, size.height)
      ..lineTo(shaftW, cy + shaftH / 2)
      ..lineTo(0, cy + shaftH / 2)
      ..close();

    canvas.drawPath(path.shift(const Offset(0, 1.5)), shadow);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.onPublish});
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.videocam_outlined,
                color: Colors.white70,
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.tr('tv_market_empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onPublish,
              icon: const Icon(Icons.photo_camera_outlined, size: 20),
              label: Text(
                context.tr('tv_publish_fab'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
