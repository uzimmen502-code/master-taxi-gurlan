import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Ҳозирги + қўшни клиплар учун плеер пули.
/// initialize аввал; қўшнилар кетма-кет (параллел эмас) — декодер тўлмасин.
/// retain тартиби сақланади: ҳозирги, кейинги, олдинги.
class TvPlayerPool {
  TvPlayerPool({this.alwaysMuted = false});

  /// Home — ҳеч қачон овоз чиқмасин.
  final bool alwaysMuted;

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
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(0);
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

  Future<void> applyOutputVolume(VideoPlayerController ctrl) async {
    await ctrl.setVolume(alwaysMuted ? 0 : 1);
  }

  void muteAll() {
    for (final ctrl in _ready.values) {
      ctrl.setVolume(0);
    }
  }

  void pauseAll() => pauseAllExcept('');

  Future<void> retain(Iterable<String> urls) async {
    final ordered = <String>[];
    final keep = <String>{};
    for (final url in urls) {
      if (url.isEmpty || !keep.add(url)) continue;
      ordered.add(url);
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

  Future<void> dispose() async {
    final all = [..._ready.values];
    _ready.clear();
    _inflight.clear();
    for (final ctrl in all) {
      await ctrl.dispose();
    }
  }
}
