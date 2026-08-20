import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../home/controllers/home_controller.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';
import '../screens/tv_market_feed_screen.dart';
import '../screens/tv_publish_screen.dart';
import '../services/tv_clip_delete.dart';
import '../services/tv_owner_name.dart';
import '../services/tv_player_pool.dart';
import '../services/tv_screen_playback.dart';
import 'tv_clip_poster.dart';
import 'tv_owner_action_bar.dart';

/// Home пастидаги овозсиз видеолар (sliver) — пастга скролл кейинги клип.
class HomeVideoStage extends StatefulWidget {
  const HomeVideoStage({super.key});

  @override
  State<HomeVideoStage> createState() => _HomeVideoStageState();
}

class _HomeVideoStageState extends State<HomeVideoStage>
    with WidgetsBindingObserver, RouteAware, TvScreenPlayback {
  static const _firstPage = 7;
  static const _nextPage = 10;

  final _repo = TvClipsRepository();
  final _pool = TvPlayerPool(alwaysMuted: true);

  List<TvClip> _clips = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _nearbyExhausted = false;
  DocumentSnapshot<Map<String, dynamic>>? _nearbyCursor;
  DocumentSnapshot<Map<String, dynamic>>? _allCursor;
  int _activeIndex = 0;
  bool _clipPlaying = false;
  ScrollPosition? _scrollPos;
  bool _pickScheduled = false;
  int _playGen = 0;
  String _meDisplayName = '';
  final _publicNames = <String, String>{};

  @override
  void initState() {
    super.initState();
    tvBindPlayback();
    unawaited(_loadMeName());
    _load();
  }

  Future<void> _loadMeName() async {
    final resolved = await resolveLocalTvOwnerGivenName();
    if (!mounted || resolved.isEmpty) return;
    setState(() => _meDisplayName = resolved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    tvSubscribeRoute();
    final pos = Scrollable.maybeOf(context)?.position;
    if (!identical(pos, _scrollPos)) {
      _scrollPos?.removeListener(_onScroll);
      _scrollPos = pos;
      _scrollPos?.addListener(_onScroll);
    }
  }

  Future<void> _load() async {
    try {
      final page = await _repo.fetchHomePage(
        districtId: ServiceConfigHolder.districtId,
        limit: _firstPage,
      );
      if (!mounted) return;
      setState(() {
        _clips = page.clips;
        _nearbyCursor = page.nearbyCursor;
        _allCursor = page.allCursor;
        _nearbyExhausted = page.nearbyExhausted;
        _hasMore = page.hasMore;
        _loading = false;
        _activeIndex = 0;
      });
      if (page.clips.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _pickActive();
        });
      }
      unawaited(_hydratePublisherNames());
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

  @override
  void tvOnPlaybackBlocked() {
    _clipPlaying = false;
    unawaited(_releasePlayers());
  }

  Future<void> _releasePlayers() async {
    await _pool.releaseAll();
    if (mounted) setState(() {});
  }

  @override
  void tvOnPlaybackAllowed() {
    if (!tvCanPlay) return;
    _pickActive();
  }

  void _pickActive() {
    if (_clips.isEmpty || !tvCanPlay) return;
    final ro = context.findRenderObject();
    if (ro is! RenderSliver) return;
    final geo = ro.geometry;
    if (geo == null || !geo.visible) {
      if (_clipPlaying) {
        _clipPlaying = false;
        _pool.pauseAllExcept('');
      }
      return;
    }
    final stride = _cardStride;
    if (stride <= 0) return;
    final leading = ro.constraints.scrollOffset;
    final viewport = ro.constraints.remainingPaintExtent;
    final center = leading + viewport * 0.42;
    var best = (center / stride).floor();
    if (best < 0) best = 0;
    if (best >= _clips.length) best = _clips.length - 1;
    final itemTop = best * stride;
    final interTop = leading > itemTop ? leading : itemTop;
    final itemBottom = itemTop + stride;
    final visEnd = leading + viewport;
    final interBottom = visEnd < itemBottom ? visEnd : itemBottom;
    final frac = ((interBottom - interTop) / stride).clamp(0.0, 1.0);
    if (frac < 0.35) {
      if (_clipPlaying) {
        _clipPlaying = false;
        _pool.pauseAllExcept('');
      }
      return;
    }
    unawaited(_maybeLoadMore(best));
    if (best == _activeIndex && _clipPlaying) return;
    _activeIndex = best;
    _clipPlaying = true;
    setState(() {});
    unawaited(_syncPlayback());
  }

  double get _cardStride {
    if (!mounted) return 0;
    return MediaQuery.sizeOf(context).height * 0.80 + 10;
  }

  Future<void> _syncPlayback() async {
    if (_clips.isEmpty || !tvCanPlay) return;
    final gen = ++_playGen;
    final clip = _clips[_activeIndex];
    _pool.pauseAllExcept(clip.videoUrl);
    final ctrl = await _pool.prepare(clip.videoUrl);
    if (!mounted || gen != _playGen || !tvCanPlay) {
      _pool.pauseAll();
      _pool.muteAll();
      return;
    }
    if (ctrl != null && ctrl.value.isInitialized) {
      await _pool.applyOutputVolume(ctrl);
      await ctrl.play();
      await ctrl.setVolume(0);
      if (!tvCanPlay) {
        ctrl.pause();
        return;
      }
      if (mounted) setState(() {});
    }
    unawaited(_pool.retain([clip.videoUrl]));
  }

  Future<void> _maybeLoadMore(int visibleIndex) async {
    if (!_hasMore || _loadingMore || _clips.isEmpty) return;
    final triggerAt = _clips.length <= 3 ? 0 : _clips.length - 3;
    if (visibleIndex < triggerAt) return;
    _loadingMore = true;
    if (mounted) setState(() {});
    try {
      var attempts = 0;
      while (mounted && _hasMore && attempts < 3) {
        attempts++;
        final page = await _repo.fetchHomePage(
          districtId: ServiceConfigHolder.districtId,
          limit: _nextPage,
          excludeIds: _clips.map((c) => c.id).toSet(),
          nearbyCursor: _nearbyCursor,
          allCursor: _allCursor,
          nearbyExhausted: _nearbyExhausted,
        );
        if (!mounted) return;
        _nearbyCursor = page.nearbyCursor;
        _allCursor = page.allCursor;
        _nearbyExhausted = page.nearbyExhausted;
        _hasMore = page.hasMore;
        final fresh = page.clips
            .where((c) => _clips.every((e) => e.id != c.id))
            .toList();
        if (fresh.isEmpty) continue;
        _clips = [..._clips, ...fresh];
        unawaited(_hydratePublisherNames());
        break;
      }
    } catch (e) {
      debugPrint('[HomeVideoStage] more: $e');
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  void _openFeed(TvClip clip) {
    tvOnPlaybackBlocked();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvMarketFeedScreen(initialClip: clip),
      ),
    );
  }

  Future<void> _onContact(TvClip clip) async {
    tvOnPlaybackBlocked();
    final ok = await callPhone(clip.ownerPhone);
    if (mounted && tvCanPlay) tvOnPlaybackAllowed();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_call_failed'))),
      );
    }
  }

  bool _isOwner(TvClip clip) {
    final me = context.read<HomeController>().phone;
    return phonesMatch(clip.ownerPhone, me);
  }

  Future<void> _hydratePublisherNames() async {
    final hydrated = await hydrateTvPublisherNames(_clips);
    if (!mounted) return;
    setState(() {
      _publicNames
        ..clear()
        ..addAll(hydrated.publicNames);
      _clips = hydrated.clips;
    });
  }

  String _overlayName(TvClip clip) {
    return tvPublisherOverlayName(
      clip: clip,
      viewerPhone: context.read<HomeController>().phone,
      viewerDisplayName: _meDisplayName,
      publicNames: _publicNames,
    );
  }

  Future<void> _onDelete(TvClip clip) async {
    tvOnPlaybackBlocked();
    try {
      final deleted = await confirmDeleteTvClip(context, clip);
      if (!deleted || !mounted) {
        if (mounted && tvCanPlay) tvOnPlaybackAllowed();
        return;
      }
      final i = _clips.indexWhere((c) => c.id == clip.id);
      if (i >= 0) {
        _clips.removeAt(i);
        if (_activeIndex >= _clips.length) {
          _activeIndex = _clips.isEmpty ? 0 : _clips.length - 1;
        }
        _clipPlaying = false;
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_delete_done'))),
      );
      if (_clips.isNotEmpty && tvCanPlay) _pickActive();
    } catch (e) {
      debugPrint('[HomeVideoStage] delete $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('tv_market_delete_failed'))),
        );
        if (tvCanPlay) tvOnPlaybackAllowed();
      }
    }
  }

  Future<void> _onEdit(TvClip clip) async {
    tvOnPlaybackBlocked();
    final updated = await Navigator.push<TvClip>(
      context,
      MaterialPageRoute(
        builder: (_) => TvPublishScreen(editClip: clip),
      ),
    );
    if (!mounted) return;
    if (updated != null) {
      final i = _clips.indexWhere((c) => c.id == updated.id);
      if (i >= 0) {
        setState(() {
          _clips[i] = updated;
        });
      }
    }
    if (tvCanPlay) tvOnPlaybackAllowed();
  }

  @override
  void dispose() {
    tvUnbindPlayback();
    _scrollPos?.removeListener(_onScroll);
    unawaited(_pool.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_clips.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    final cardH = MediaQuery.sizeOf(context).height * 0.80;
    final hPad = MediaQuery.sizeOf(context).width < 360 ? 12.0 : 16.0;

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
      sliver: SliverFixedExtentList(
        itemExtent: cardH + 10,
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (i >= _clips.length) {
              return const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _HomeClipCard(
                clip: _clips[i],
                height: cardH,
                playing: i == _activeIndex,
                controller: _pool[_clips[i].videoUrl],
                isOwner: _isOwner(_clips[i]),
                ownerLabel: _overlayName(_clips[i]),
                onOpen: () => _openFeed(_clips[i]),
                onContact: () => _onContact(_clips[i]),
                onDelete: () => _onDelete(_clips[i]),
                onEdit: () => _onEdit(_clips[i]),
              ),
            );
          },
          childCount: _clips.length + (_loadingMore ? 1 : 0),
          addAutomaticKeepAlives: false,
        ),
      ),
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
    required this.onDelete,
    required this.onEdit,
    this.isOwner = false,
    this.ownerLabel = '',
  });

  final TvClip clip;
  final double height;
  final bool playing;
  final VideoPlayerController? controller;
  final VoidCallback onOpen;
  final VoidCallback onContact;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final bool isOwner;
  final String ownerLabel;

  @override
  Widget build(BuildContext context) {
    final ready = playing &&
        controller != null &&
        controller!.value.isInitialized;
    final name = tvOwnerDisplayName(ownerLabel);
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
                  if (name.isNotEmpty) ...[
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
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
                  ],
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
                  if (isOwner)
                    GestureDetector(
                      onTap: () {},
                      child: TvOwnerActionBar(
                        onEdit: onEdit,
                        onDelete: onDelete,
                        height: 40,
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: onContact,
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 17,
                        ),
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
