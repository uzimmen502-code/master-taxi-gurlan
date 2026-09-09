import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../repositories/tv_clips_repository.dart';

/// Har bir klip ko'rilishi uchun playback sifat metrikalarini kuzatadi:
/// birinchi kadr vaqti, buferlanish (rebuffer), tomosha davomiyligi,
/// completion/skip. Bitta ko'rish = bitta yakuniy yozuv ([detach]da) —
/// `TvClipViewRecorder`dagi kabi event-stream emas.
class TvPlaybackAnalyticsRecorder {
  TvPlaybackAnalyticsRecorder({TvClipsRepository? repo})
      : _repo = repo ?? TvClipsRepository();

  final TvClipsRepository _repo;

  /// Shundan kam tomosha qilingan va completion'ga yetmagan — skip.
  static const _skipThreshold = Duration(seconds: 3);
  static const _completionFraction = 0.9;

  VideoPlayerController? _ctrl;
  VoidCallback? _listener;
  String? _clipId;
  DateTime? _attachedAt;
  DateTime? _firstFrameAt;
  bool _wasBuffering = false;
  DateTime? _bufferStartedAt;
  Duration _bufferedTotal = Duration.zero;
  int _bufferEvents = 0;
  Duration _maxPosition = Duration.zero;

  void attach({
    required VideoPlayerController controller,
    required String clipId,
  }) {
    detach();
    if (clipId.isEmpty) return;
    _ctrl = controller;
    _clipId = clipId;
    _attachedAt = DateTime.now();
    _listener = _onTick;
    controller.addListener(_listener!);
    _onTick();
  }

  void _onTick() {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final v = ctrl.value;

    if (_firstFrameAt == null && v.position > Duration.zero) {
      _firstFrameAt = DateTime.now();
    }

    if (v.isBuffering && !_wasBuffering) {
      _wasBuffering = true;
      _bufferStartedAt = DateTime.now();
      _bufferEvents++;
    } else if (!v.isBuffering && _wasBuffering) {
      _wasBuffering = false;
      final start = _bufferStartedAt;
      if (start != null) {
        _bufferedTotal += DateTime.now().difference(start);
      }
      _bufferStartedAt = null;
    }

    if (v.position > _maxPosition) _maxPosition = v.position;
  }

  /// Klip endi ko'rinmay qoladi (svayp / ekran yopilishi) — yakuniy yozuv.
  void detach() {
    final ctrl = _ctrl;
    final listener = _listener;
    final clipId = _clipId;
    final attachedAt = _attachedAt;
    if (ctrl != null && listener != null) {
      ctrl.removeListener(listener);
    }
    if (ctrl != null && clipId != null && attachedAt != null) {
      if (_wasBuffering && _bufferStartedAt != null) {
        _bufferedTotal += DateTime.now().difference(_bufferStartedAt!);
      }
      final dur = ctrl.value.duration;
      final watched = _maxPosition;
      final completed = dur > Duration.zero &&
          watched.inMilliseconds >=
              (dur.inMilliseconds * _completionFraction).round();
      final skipped = !completed && watched < _skipThreshold;
      unawaited(_repo.recordPlaybackStats(
        clipId: clipId,
        watched: watched,
        buffered: _bufferedTotal,
        bufferEvents: _bufferEvents,
        firstFrame: _firstFrameAt?.difference(attachedAt),
        completed: completed,
        skipped: skipped,
      ));
    }
    _ctrl = null;
    _listener = null;
    _clipId = null;
    _attachedAt = null;
    _firstFrameAt = null;
    _wasBuffering = false;
    _bufferStartedAt = null;
    _bufferedTotal = Duration.zero;
    _bufferEvents = 0;
    _maxPosition = Duration.zero;
  }

  void dispose() => detach();
}
