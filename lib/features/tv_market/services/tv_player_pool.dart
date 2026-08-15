import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Ҳозирги + қўшни клиплар учун плеер пули.
/// Свайпда initialize кутилмайди — тайёр контроллер дарҳол play.
class TvPlayerPool {
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
      ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      await ctrl.setLooping(true);
      await ctrl.setVolume(0);
      await ctrl.initialize();
      _ready[url] = ctrl;
      return ctrl;
    } catch (e) {
      debugPrint('[TvPlayerPool] $e');
      await ctrl?.dispose();
      return null;
    } finally {
      _inflight.remove(url);
    }
  }

  Future<void> retain(Iterable<String> urls) async {
    final keep = urls.where((u) => u.isNotEmpty).toSet();
    final drop = _ready.keys.where((k) => !keep.contains(k)).toList();
    for (final url in drop) {
      final ctrl = _ready.remove(url);
      await ctrl?.dispose();
    }
    await Future.wait(keep.map(prepare));
  }

  void pauseAllExcept(String? url) {
    for (final entry in _ready.entries) {
      if (entry.key == url) continue;
      final ctrl = entry.value;
      if (ctrl.value.isPlaying) ctrl.pause();
      ctrl.setVolume(0);
    }
  }

  Future<void> dispose() async {
    final all = [..._ready.values];
    _ready.clear();
    _inflight.clear();
    for (final ctrl in all) {
      await ctrl.dispose();
    }
  }
}
