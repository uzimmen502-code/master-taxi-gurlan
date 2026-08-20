import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../core/utils/crash_report.dart';

/// Ҳозирги + (ихтиёрий) кейинги клип учун плеер пули.
///
/// Play vitals 1.0.24: бир нечта тўлиқ ExoPlayer + Home остида Feed
/// → OutOfMemoryError (`ExoPlayerImplInternal.shouldContinueLoading`).
/// Паузада декодерни тирик қолдирмаймиз — [releaseAll].
class TvPlayerPool {
  TvPlayerPool({
    this.alwaysMuted = false,
    this.maxReady = 1,
  });

  /// Home — ҳеч қачон овоз чиқмасин.
  final bool alwaysMuted;

  /// Бир вақтда тирик ExoPlayer сони (Home=1, Feed=2).
  final int maxReady;

  final _ready = <String, VideoPlayerController>{};
  final _inflight = <String, Future<VideoPlayerController?>>{};

  VideoPlayerController? operator [](String url) => _ready[url];

  Future<VideoPlayerController?> prepare(String url) {
    if (url.isEmpty) return Future.value(null);
    final existing = _ready[url];
    if (existing != null && existing.value.isInitialized) {
      return Future.value(existing);
    }
    return _inflight.putIfAbsent(url, () => _create(url));
  }

  Future<VideoPlayerController?> _create(String url) async {
    VideoPlayerController? ctrl;
    try {
      await _evictIfNeeded(keep: url);
      ctrl = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );
      await ctrl.initialize().timeout(const Duration(seconds: 15));
      await ctrl.setLooping(true);
      await ctrl.setVolume(0);
      _ready[url] = ctrl;
      await _evictIfNeeded(keep: url);
      return ctrl;
    } catch (e, st) {
      debugPrint('[TvPlayerPool] $e');
      unawaited(CrashReport.nonFatal(
        e,
        st,
        reason: 'tv_player_init',
      ));
      await ctrl?.dispose();
      return null;
    } finally {
      _inflight.remove(url);
    }
  }

  Future<void> _evictIfNeeded({required String keep}) async {
    while (_ready.length > maxReady ||
        (_ready.length >= maxReady && !_ready.containsKey(keep))) {
      final victim = _ready.keys.firstWhere(
        (k) => k != keep,
        orElse: () => '',
      );
      if (victim.isEmpty) break;
      final ctrl = _ready.remove(victim);
      await ctrl?.dispose();
    }
  }

  Future<void> applyOutputVolume(VideoPlayerController ctrl) async {
    await ctrl.setVolume(alwaysMuted ? 0 : 1);
  }

  void muteAll() {
    for (final ctrl in _ready.values) {
      ctrl.setVolume(0);
    }
  }

  void pauseAll() => pauseAllExcept('');

  /// Хотирани бўшатиш: пауза етарли эмас, ExoPlayer deallocate қилинади.
  Future<void> releaseAll() async {
    final all = [..._ready.values];
    _ready.clear();
    _inflight.clear();
    for (final ctrl in all) {
      try {
        await ctrl.dispose();
      } catch (_) {}
    }
  }

  Future<void> retain(Iterable<String> urls) async {
    final ordered = <String>[];
    final keep = <String>{};
    for (final url in urls) {
      if (url.isEmpty || !keep.add(url)) continue;
      ordered.add(url);
      if (ordered.length >= maxReady) break;
    }
    final drop = _ready.keys.where((k) => !keep.contains(k)).toList();
    for (final url in drop) {
      final ctrl = _ready.remove(url);
      await ctrl?.dispose();
    }
    for (final url in ordered) {
      await prepare(url);
    }
  }

  void pauseAllExcept(String? url) {
    for (final entry in _ready.entries) {
      if (entry.key == url) continue;
      final ctrl = entry.value;
      if (ctrl.value.isPlaying) {
        ctrl.pause();
      }
      ctrl.setVolume(0);
    }
  }

  Future<void> dispose() => releaseAll();
}
