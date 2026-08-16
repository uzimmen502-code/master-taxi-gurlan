import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/geo_area.dart';
import '../../../repositories/service_config_repository.dart';
import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';
import '../repositories/tv_shop_repository.dart';
import '../services/tv_clip_delete.dart';
import '../services/tv_clip_share.dart';
import '../services/tv_owner_name.dart';
import '../services/tv_player_pool.dart';
import '../services/tv_screen_playback.dart';
import '../widgets/tv_clip_overlay.dart';
import '../widgets/tv_clip_poster.dart';
import '../widgets/tv_play_pause_badge.dart';
import 'tv_clip_search_screen.dart';
import 'tv_my_shop_screen.dart';
import 'tv_owner_clips_screen.dart';
import 'tv_publish_screen.dart';
import 'tv_shop_public_screen.dart';

/// TV Market — тўлиқ экран вертикал видео лента.
class TvMarketFeedScreen extends StatefulWidget {
  const TvMarketFeedScreen({super.key, this.initialClip});

  /// Уйдаги клипдан тўлиқ feedга кирганда — шундан давом этади.
  final TvClip? initialClip;

  @override
  State<TvMarketFeedScreen> createState() => _TvMarketFeedScreenState();
}

class _TvMarketFeedScreenState extends State<TvMarketFeedScreen>
    with WidgetsBindingObserver, RouteAware, TvScreenPlayback {
  final _repo = TvClipsRepository();
  final _pool = TvPlayerPool(alwaysMuted: false);
  final _clips = <TvClip>[];
  bool _loading = true;
  int _currentIndex = 0;
  late final PageController _pageCtrl;
  bool _showPlayPause = false;
  Timer? _hideBadgeTimer;
  int _activateGen = 0;
  String _mePhone = '';
  String _meGivenName = '';
  String _filterDistrictId = '';
  List<GeoDistrict> _districts = const [];
  final _likedIds = <String>{};
  final _savedIds = <String>{};
  final _likeBusy = <String>{};
  final _saveBusy = <String>{};
  final _shopRepo = TvShopRepository();

  @override
  void initState() {
    super.initState();
    tvBindPlayback();
    _pageCtrl = PageController();
    unawaited(_loadMe());
    unawaited(_loadDistricts());
    _loadClips();
  }

  Future<void> _loadMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _mePhone = phoneDigits(prefs.getString('user_phone') ?? '');
      _meGivenName = tvOwnerGivenName(prefs.getString('user_name') ?? '');
    });
    if (_meGivenName.isEmpty) {
      final resolved = await resolveLocalTvOwnerGivenName(phone: _mePhone);
      if (mounted && resolved.isNotEmpty) {
        setState(() => _meGivenName = resolved);
      }
    }
    await _refreshSocialState();
  }

  Future<void> _loadDistricts() async {
    final regionId = ServiceConfigHolder.regionId;
    if (regionId.isEmpty) return;
    try {
      final list = await ServiceConfigRepository().fetchDistricts(regionId);
      if (!mounted) return;
      setState(() => _districts = list);
    } catch (e) {
      debugPrint('[TvMarketFeed] districts $e');
    }
  }

  Future<void> _refreshSocialState() async {
    final uid = canonicalPhoneId(_mePhone);
    if (uid.isEmpty || _clips.isEmpty) return;
    try {
      final liked = await _repo.likedClipIds(
        likerId: uid,
        clipIds: _clips.map((c) => c.id).take(40),
      );
      final saved = await _repo.savedClipIds(uid);
      if (!mounted) return;
      setState(() {
        _likedIds
          ..clear()
          ..addAll(liked);
        _savedIds
          ..clear()
          ..addAll(saved);
      });
    } catch (e) {
      debugPrint('[TvMarketFeed] social $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    tvSubscribeRoute();
  }

  @override
  void tvOnPlaybackBlocked() {
    _pool.pauseAll();
    _pool.muteAll();
  }

  @override
  void tvOnPlaybackAllowed() {
    if (!tvCanPlay || _clips.isEmpty) return;
    unawaited(_activate(_currentIndex));
  }

  Future<void> _loadClips() async {
    try {
      List<TvClip> nearby;
      if (_filterDistrictId.isEmpty) {
        nearby = await _repo.fetchAllActive(limit: 40);
      } else {
        nearby = await _repo.fetchNearby(
          districtId: _filterDistrictId,
          limit: 40,
        );
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
      unawaited(_refreshSocialState());
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
    if (index < 0 || index >= _clips.length || !tvCanPlay) return;
    final gen = ++_activateGen;
    final clip = _clips[index];
    _pool.pauseAllExcept(clip.videoUrl);

    final ctrl = await _pool.prepare(clip.videoUrl);
    if (!mounted || gen != _activateGen || _currentIndex != index) return;
    if (!tvCanPlay) {
      _pool.pauseAll();
      _pool.muteAll();
      return;
    }
    if (ctrl != null && ctrl.value.isInitialized) {
      if (!mounted || gen != _activateGen) return;
      setState(() => _showPlayPause = false);
      await _pool.applyOutputVolume(ctrl);
      await ctrl.play();
      if (!tvCanPlay) {
        ctrl.pause();
        ctrl.setVolume(0);
        return;
      }
    }
    unawaited(_pool.retain(_urlsAround(index)));
    unawaited(_maybePatchOwnerName(clip));
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
    if (!tvCanPlay) return;
    final ctrl = _activeCtrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    _hideBadgeTimer?.cancel();
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      setState(() => _showPlayPause = true);
    } else {
      unawaited(_pool.applyOutputVolume(ctrl));
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
    tvOnPlaybackBlocked();
    final ok = await callPhone(clip.ownerPhone);
    if (mounted && tvCanPlay) tvOnPlaybackAllowed();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_call_failed'))),
      );
    }
  }

  bool _isOwner(TvClip clip) => phonesMatch(clip.ownerPhone, _mePhone);

  String _overlayName(BuildContext context, TvClip clip) {
    final stored = clip.displayOwnerName('');
    if (stored.isNotEmpty) return stored;
    if (_isOwner(clip) && _meGivenName.isNotEmpty) return _meGivenName;
    return context.tr('tv_market_user');
  }

  Future<void> _maybePatchOwnerName(TvClip clip) async {
    if (!_isOwner(clip) || _meGivenName.isEmpty) return;
    if (!tvOwnerNameLooksFake(clip.ownerName)) return;
    try {
      await _repo.patchOwnerName(clipId: clip.id, ownerName: _meGivenName);
      if (!mounted) return;
      final i = _clips.indexWhere((c) => c.id == clip.id);
      if (i >= 0) {
        setState(() {
          _clips[i] = _clips[i].copyWith(ownerName: _meGivenName);
        });
      }
    } catch (e) {
      debugPrint('[TvMarketFeed] patch name $e');
    }
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
      if (i >= 0) _clips.removeAt(i);
      if (_clips.isEmpty) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('tv_market_delete_done'))),
        );
        return;
      }
      final next = i.clamp(0, _clips.length - 1);
      _currentIndex = next;
      setState(() {});
      if (_pageCtrl.hasClients) {
        _pageCtrl.jumpToPage(next);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_delete_done'))),
      );
      if (tvCanPlay) unawaited(_activate(next));
    } catch (e) {
      debugPrint('[TvMarketFeed] delete $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('tv_market_delete_failed'))),
        );
        if (tvCanPlay) tvOnPlaybackAllowed();
      }
    }
  }

  Future<void> _openSearch() async {
    tvOnPlaybackBlocked();
    final clip = await Navigator.push<TvClip>(
      context,
      MaterialPageRoute(
        builder: (_) => TvClipSearchScreen(
          districtId: _filterDistrictId,
          districtLabel: _filterChipLabel(),
        ),
      ),
    );
    if (!mounted) return;
    if (clip == null) {
      if (tvCanPlay) tvOnPlaybackAllowed();
      return;
    }
    final existing = _clips.indexWhere((c) => c.id == clip.id);
    if (existing >= 0) {
      _currentIndex = existing;
      setState(() {});
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(existing);
      unawaited(_activate(existing));
      return;
    }
    setState(() {
      _clips.insert(0, clip);
      _currentIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
      unawaited(_activate(0));
    });
  }

  Future<void> _openPublish() async {
    tvOnPlaybackBlocked();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TvPublishScreen()),
    );
    if (!mounted) return;
    if (result == true) {
      await _loadClips();
    } else if (tvCanPlay) {
      tvOnPlaybackAllowed();
    }
  }

  String get _meId => canonicalPhoneId(_mePhone);

  Future<void> _onLike(TvClip clip) async {
    final uid = _meId;
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_like_need_auth'))),
      );
      return;
    }
    if (!_likeBusy.add(clip.id)) return;
    final was = _likedIds.contains(clip.id);
    setState(() {
      if (was) {
        _likedIds.remove(clip.id);
      } else {
        _likedIds.add(clip.id);
      }
      final i = _clips.indexWhere((c) => c.id == clip.id);
      if (i >= 0) {
        final n = _clips[i].likeCount + (was ? -1 : 1);
        _clips[i] = _clips[i].copyWith(likeCount: n < 0 ? 0 : n);
      }
    });
    try {
      final liked = await _repo.toggleLike(clipId: clip.id, likerId: uid);
      if (!mounted) return;
      setState(() {
        if (liked) {
          _likedIds.add(clip.id);
        } else {
          _likedIds.remove(clip.id);
        }
      });
    } catch (e) {
      debugPrint('[TvMarketFeed] like $e');
      if (!mounted) return;
      setState(() {
        if (was) {
          _likedIds.add(clip.id);
        } else {
          _likedIds.remove(clip.id);
        }
        final i = _clips.indexWhere((c) => c.id == clip.id);
        if (i >= 0) {
          final n = _clips[i].likeCount + (was ? 1 : -1);
          _clips[i] = _clips[i].copyWith(likeCount: n < 0 ? 0 : n);
        }
      });
    } finally {
      _likeBusy.remove(clip.id);
    }
  }

  Future<void> _onShare(TvClip clip) async {
    try {
      await shareTvClip(clip);
    } catch (e) {
      debugPrint('[TvMarketFeed] share $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('tv_market_share_failed'))),
        );
      }
    }
  }

  Future<void> _onSave(TvClip clip) async {
    final uid = _meId;
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_save_need_auth'))),
      );
      return;
    }
    if (!_saveBusy.add(clip.id)) return;
    final was = _savedIds.contains(clip.id);
    setState(() {
      if (was) {
        _savedIds.remove(clip.id);
      } else {
        _savedIds.add(clip.id);
      }
    });
    try {
      final saved = await _repo.toggleSave(userId: uid, clipId: clip.id);
      if (!mounted) return;
      setState(() {
        if (saved) {
          _savedIds.add(clip.id);
        } else {
          _savedIds.remove(clip.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(saved ? 'tv_market_saved' : 'tv_market_unsaved'),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[TvMarketFeed] save $e');
      if (!mounted) return;
      setState(() {
        if (was) {
          _savedIds.add(clip.id);
        } else {
          _savedIds.remove(clip.id);
        }
      });
    } finally {
      _saveBusy.remove(clip.id);
    }
  }

  Future<void> _onProfile(TvClip clip) async {
    tvOnPlaybackBlocked();
    final shop = await _shopRepo.fetchShop(clip.ownerPhone);
    if (!mounted) return;
    final owner = _isOwner(clip);
    Widget screen;
    if (shop != null) {
      screen = owner
          ? TvMyShopScreen(ownerPhone: clip.ownerPhone)
          : TvShopPublicScreen(ownerPhone: clip.ownerPhone);
    } else {
      screen = TvOwnerClipsScreen(
        ownerPhone: clip.ownerPhone,
        ownerName: clip.displayOwnerName(context.tr('tv_market_user')),
      );
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted && tvCanPlay) tvOnPlaybackAllowed();
  }

  Future<void> _onOpenShop(TvClip clip) async {
    tvOnPlaybackBlocked();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvShopPublicScreen(
          ownerPhone: clip.ownerPhone,
          highlightItemId: clip.shopItemId,
        ),
      ),
    );
    if (mounted && tvCanPlay) tvOnPlaybackAllowed();
  }

  Future<void> _pickDistrictFilter() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              ListTile(
                title: Text(
                  context.tr('tv_market_all_districts'),
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: _filterDistrictId.isEmpty
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : null,
                onTap: () => Navigator.pop(ctx, ''),
              ),
              for (final d in _districts)
                ListTile(
                  title: Text(
                    d.displayName,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: _filterDistrictId == d.id
                      ? const Icon(Icons.check_rounded, color: Colors.white)
                      : null,
                  onTap: () => Navigator.pop(ctx, d.id),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filterDistrictId = picked;
      _loading = true;
    });
    await _loadClips();
  }

  String _filterChipLabel() {
    if (_filterDistrictId.isEmpty) {
      return context.tr('tv_market_all_districts');
    }
    for (final d in _districts) {
      if (d.id == _filterDistrictId) return d.displayName;
    }
    return context.tr('tv_market_all_districts');
  }

  @override
  void dispose() {
    tvUnbindPlayback();
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
        titleSpacing: 0,
        title: Align(
          alignment: Alignment.centerLeft,
          child: _DistrictFilterChip(
            label: _filterChipLabel(),
            onTap: _pickDistrictFilter,
          ),
        ),
        actions: [
          IconButton(
            tooltip: context.tr('tv_market_search'),
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded, color: Colors.white, size: 26),
          ),
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
                          Icons.videocam_rounded,
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
                          isOwner: _isOwner(clip),
                          ownerLabel: _overlayName(context, clip),
                          liked: _likedIds.contains(clip.id),
                          saved: _savedIds.contains(clip.id),
                          onContact: () => _onContact(clip),
                          onDelete: () => _onDelete(clip),
                          onLike: () => _onLike(clip),
                          onShare: () => _onShare(clip),
                          onSave: () => _onSave(clip),
                          onProfile: () => _onProfile(clip),
                          onOpenShop: clip.hasShopItem
                              ? () => _onOpenShop(clip)
                              : null,
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

class _DistrictFilterChip extends StatelessWidget {
  const _DistrictFilterChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_drop_down_rounded,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
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
      size: const Size(34, 22),
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
              icon: const Icon(Icons.videocam_rounded, size: 20),
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
