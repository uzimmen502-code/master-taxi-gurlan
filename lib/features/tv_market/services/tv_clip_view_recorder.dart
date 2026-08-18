import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/tv_clip.dart';
import '../repositories/tv_clips_repository.dart';

/// Rolik haqiqiy ko‘rilganda view yozadi (3s yoki 25%, 24h dedup).
class TvClipViewRecorder {
  TvClipViewRecorder({TvClipsRepository? repo})
      : _repo = repo ?? TvClipsRepository();

  final TvClipsRepository _repo;
  static const _minWatch = Duration(seconds: 3);
  static const _minFraction = 0.25;

  VideoPlayerController? _ctrl;
  VoidCallback? _listener;
  String? _clipId;
  String? _viewerId;
  String? _ownerPhone;
  VoidCallback? _onRecorded;
  final _sessionRecorded = <String>{};

  void attach({
    required VideoPlayerController controller,
    required TvClip clip,
    required String viewerId,
    VoidCallback? onRecorded,
  }) {
    detach();
    if (viewerId.isEmpty || clip.id.isEmpty) return;
    if (_sessionRecorded.contains(clip.id)) return;

    _ctrl = controller;
    _clipId = clip.id;
    _viewerId = viewerId;
    _ownerPhone = clip.ownerPhone;
    _onRecorded = onRecorded;

    _listener = () => _onTick();
    controller.addListener(_listener!);
  }

  void detach() {
    final l = _listener;
    final c = _ctrl;
    if (l != null && c != null) {
      c.removeListener(l);
    }
    _listener = null;
    _ctrl = null;
    _clipId = null;
    _viewerId = null;
    _ownerPhone = null;
    _onRecorded = null;
  }

  void _onTick() {
    final ctrl = _ctrl;
    final clipId = _clipId;
    final viewerId = _viewerId;
    final ownerPhone = _ownerPhone;
    if (ctrl == null ||
        clipId == null ||
        viewerId == null ||
        ownerPhone == null) {
      return;
    }
    if (!ctrl.value.isInitialized || _sessionRecorded.contains(clipId)) {
      return;
    }
    if (!ctrl.value.isPlaying) return;

    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;
    final watchedEnough = pos >= _minWatch;
    final fractionOk = dur > Duration.zero &&
        pos >= Duration(
          milliseconds: (dur.inMilliseconds * _minFraction).round(),
        );
    if (!watchedEnough && !fractionOk) return;

    _sessionRecorded.add(clipId);
    final onRecorded = _onRecorded;
    detach();
    _repo
        .recordView(
          clipId: clipId,
          viewerId: viewerId,
          ownerPhone: ownerPhone,
        )
        .then((ok) {
      if (ok) onRecorded?.call();
    });
  }

  void dispose() => detach();
}

/// Feed UI — lokal optimistik +1.
void tvClipViewCountBump(List<TvClip> clips, String clipId) {
  final i = clips.indexWhere((c) => c.id == clipId);
  if (i < 0) return;
  clips[i] = clips[i].copyWith(viewCount: clips[i].viewCount + 1);
}
