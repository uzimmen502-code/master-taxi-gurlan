import 'dart:async';

import 'package:ava_gurlan/features/tv_market/services/tv_player_pool.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Свайп playback қоидалари — pool даражасида (`_activate()` айнан шу
/// чақирувларни қилади: `markWanted` → `pauseAllExcept(current)` →
/// `prepare` → `applyOutputVolume` → `play`).
///
/// Реал ExoPlayer йўқ — [_FakePlatform] ҳар бир player учун `play/pause/
/// setVolume` чақирувларини ёзиб боради. URL'лар `.m3u8` — [TvClipCacheService]
/// HLS'ни четлаб ўтади, path_provider'га тегилмайди.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlatform fake;
  final pool = TvPlayerPool.shared;

  const a = 'https://cdn.example/clips/a/master.m3u8';
  const b = 'https://cdn.example/clips/b/master.m3u8';
  const c = 'https://cdn.example/clips/c/master.m3u8';

  setUp(() async {
    fake = _FakePlatform();
    VideoPlayerPlatform.instance = fake;
    await pool.releaseAll();
  });

  tearDown(() async => pool.releaseAll());

  /// `_activate(url)`нинг pool қисми.
  Future<VideoPlayerController?> activate(String url, List<String> around) async {
    pool.markWanted(around);
    pool.pauseAllExcept(url);
    final ctrl = await pool.prepare(url);
    if (ctrl == null) return null;
    await pool.applyOutputVolume(ctrl, muted: false);
    await ctrl.play();
    return ctrl;
  }

  int playingCount() =>
      [a, b, c].map((u) => pool[u]).where((c) => c?.value.isPlaying == true).length;

  int audibleCount() =>
      [a, b, c].map((u) => pool[u]).where((c) => (c?.value.volume ?? 0) > 0).length;

  test('preload (NEXT) ўйнамайди ва овозсиз — фақат current play/audible', () async {
    final ca = await activate(a, [a, b]);
    // NEXT prefetch — `_prefetchAfterHealthy` → retain
    await pool.retain([a, b]);
    final cb = pool[b];

    expect(ca!.value.isPlaying, isTrue);
    expect(ca.value.volume, 1.0);
    expect(cb, isNotNull);
    expect(cb!.value.isPlaying, isFalse, reason: 'preload ўйнамасин (6-қоида)');
    expect(cb.value.volume, 0, reason: 'preload овозсиз (8-қоида)');
    expect(fake.plays[fake.idOf(b)] ?? 0, 0);
    expect(playingCount(), 1);
    expect(audibleCount(), 1);
  });

  test('свайп: аввалги видео дарҳол pause + volume 0 (1, 2, 8-қоида)', () async {
    final ca = await activate(a, [a, b]);
    await pool.retain([a, b]);
    final idA = fake.idOf(a);
    final pausesBefore = fake.pauses[idA] ?? 0;

    // Свайп → B
    pool.markWanted([b, c]);
    pool.pauseAllExcept(b); // синхрон — prepare()дан олдин

    expect(ca!.value.isPlaying, isFalse, reason: 'аввалги дарҳол pause');
    expect(ca.value.volume, 0, reason: 'аввалги овозсиз');
    expect(fake.pauses[idA], pausesBefore + 1, reason: 'native pause() чақирилди');
    expect(fake.lastVolume[idA], 0.0, reason: 'native setVolume(0) чақирилди');

    final cb = await pool.prepare(b);
    await pool.applyOutputVolume(cb!, muted: false);
    await cb.play();

    expect(playingCount(), 1, reason: 'бир вақтда фақат битта playback');
    expect(audibleCount(), 1, reason: 'audio фақат current');
    expect(pool[b]!.value.isPlaying, isTrue);
  });

  test('20 та кетма-кет свайп: ҳеч қачон 2 та видео бир вақтда ўйнамайди', () async {
    final seq = [a, b, c, b, a, c, a, b, c, a, b, a, c, b, a, b, c, a, c, b];
    for (var i = 0; i < seq.length; i++) {
      final cur = seq[i];
      final next = seq[(i + 1) % seq.length];
      await activate(cur, [cur, next]);
      expect(playingCount(), lessThanOrEqualTo(1),
          reason: 'свайп #${i + 1}: $cur ўйнаётганда бошқаси ҳам play');
      expect(audibleCount(), lessThanOrEqualTo(1),
          reason: 'свайп #${i + 1}: иккита audio');
      expect(pool[cur]!.value.isPlaying, isTrue);
      expect(pool[cur]!.value.volume, 1.0);
    }
    // maxReady = 2 — 3 та URL алмашса ҳам pool ҳеч қачон 2 дан ошмайди.
    expect([a, b, c].where((u) => pool[u] != null).length, lessThanOrEqualTo(2));
  });

  test('rapid swipe: markWanted эскирган inflight controller\'ни dispose қилади '
      '(эски видео кечикиб play бўлмайди — 7-қоида)', () async {
    fake.initDelay = const Duration(milliseconds: 80);
    pool.markWanted([a]);
    final fa = pool.prepare(a); // initialize ҳали тугамаган
    // Фойдаланувчи дарҳол B'га ўтди
    pool.markWanted([b]);
    pool.pauseAllExcept(b);
    final ca = await fa;
    expect(ca, isNull, reason: 'эскирган A _ready\'га қўшилмайди');
    expect(pool[a], isNull);
    expect(fake.disposed.contains(fake.idOf(a)), isTrue);
    expect(fake.plays[fake.idOf(a)] ?? 0, 0, reason: 'A ҳеч қачон play бўлмади');
  });
}

class _FakePlatform extends VideoPlayerPlatform {
  int _next = 1;
  final _idByUri = <String, int>{};
  final _events = <int, StreamController<VideoEvent>>{};
  final plays = <int, int>{};
  final pauses = <int, int>{};
  final lastVolume = <int, double>{};
  final disposed = <int>{};
  Duration initDelay = Duration.zero;

  int idOf(String url) => _idByUri[url] ?? -1;

  @override
  Future<void> init() async {}

  Future<int?> _create(String uri) async {
    final id = _next++;
    _idByUri[uri] = id;
    final sc = StreamController<VideoEvent>.broadcast();
    _events[id] = sc;
    Future<void>.delayed(initDelay, () {
      if (sc.isClosed) return;
      sc.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 12),
        size: const Size(360, 640),
      ));
    });
    return id;
  }

  @override
  Future<int?> create(DataSource dataSource) => _create(dataSource.uri ?? '');

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      _create(options.dataSource.uri ?? '');

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    await _events[playerId]?.close();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {
    plays[playerId] = (plays[playerId] ?? 0) + 1;
  }

  @override
  Future<void> pause(int playerId) async {
    pauses[playerId] = (pauses[playerId] ?? 0) + 1;
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    lastVolume[playerId] = volume;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox.shrink();

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}
}
