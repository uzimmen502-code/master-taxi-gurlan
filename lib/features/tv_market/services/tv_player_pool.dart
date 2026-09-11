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
  TvPlayerPool._({this.maxReady = 3});

  /// Butun ilova bo'yicha YAGONA pool — screen'lar o'z pool'ini
  /// yaratmaydi (avvalgi dual-pool OOM xavfi: `TvMarketFeedScreen`
  /// (maxReady 3) + `HomeVideoStage` (maxReady 1) bir vaqtda tirik
  /// bo'lganda jami 4 tagacha ExoPlayer). Screen almashganda `retain()`
  /// yangi `wanted` to'plamiga mos kelmagan eski controller'larni
  /// avtomatik evict qiladi — shared bo'lgani uchun ham xavfsiz.
  static final TvPlayerPool shared = TvPlayerPool._(maxReady: 3);

  /// Бир вақтда тирик (ready) ExoPlayer сони — бутун илова учун умумий чегара.
  final int maxReady;

  final _ready = <String, VideoPlayerController>{};
  final _inflight = <String, Future<VideoPlayerController?>>{};

  /// Joriy generatsiya endi qaysi url'larni xohlashi — tez svayp paytida
  /// eskirgan (superseded) so'rovlarni "bekor qilish" signali sifatida
  /// ishlatiladi (`_create` va `_evictIfNeeded`ga qarang). `VideoPlayerController`
  /// haqiqiy cancel()ni qo'llab-quvvatlamaydi — shuning uchun bekor qilish
  /// amalda "kerak emas" deb belgilash va tugagan zahoti dispose qilishdan
  /// iborat.
  final _wanted = <String>{};

  VideoPlayerController? operator [](String url) => _ready[url];

  /// Sinxron, dispose qilmaydi — faqat signal. Screen har yangi
  /// generatsiya boshida (`prepare()`dan OLDIN) chaqiradi.
  void markWanted(Iterable<String> urls) {
    _wanted
      ..clear()
      ..addAll(urls.where((u) => u.isNotEmpty));
  }

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
      if (shouldDiscardOnComplete(url, _wanted)) {
        // Shu url tayyor bo'lguncha generatsiya eskirib ulgurdi (foydalanuvchi
        // allaqachon boshqa joyga svayp qilgan) — _ready'ga hech qachon
        // qo'shilmaydi, zudlik bilan dispose qilinadi.
        await ctrl.dispose();
        return null;
      }
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
    while (true) {
      final victim = selectEvictionVictim(
        readyKeys: _ready.keys.toList(),
        inflightKeys: _inflight.keys.toSet(),
        wanted: _wanted,
        keep: keep,
        maxReady: maxReady,
      );
      if (victim == null) break;
      final ctrl = _ready.remove(victim);
      await ctrl?.dispose();
    }
  }

  /// [muted] — chaqiruvchi screen belgilaydi (Home — doim `true`,
  /// TV Market feed — doim `false`). Pool o'zi ovoz siyosatini bilmaydi,
  /// chunki endi bir nechta screen o'rtasida umumiy.
  Future<void> applyOutputVolume(VideoPlayerController ctrl, {required bool muted}) async {
    await ctrl.setVolume(muted ? 0 : 1);
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
    markWanted(ordered);
    final drop = _ready.keys.where((k) => !keep.contains(k)).toList();
    for (final url in drop) {
      final ctrl = _ready.remove(url);
      await ctrl?.dispose();
    }
    // Керакмаслар юқорида аллақачон бўшатилди — `_ready` энди фақат
    // `keep` (<= maxReady) дан иборат, шунинг учун параллел prepare
    // eviction race'сиз хавфсиз (жой олдиндан кафолатланган). Кейинги
    // видео (swipe'дан кейинги) фонда бир вақтда юклана бошлайди —
    // навбат билан кутиш ўрнига.
    await Future.wait(ordered.map(prepare));
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

/// Sof qaror mantig'i (VideoPlayerController'siz, testlanadigan): `ready`
/// va `inflight`ni birlashtirib (dublikatsiz) sig'imni hisoblaydi va
/// kerak bo'lsa qaysi `ready` controller evict qilinishini tanlaydi —
/// `wanted`da yo'qlarga ustuvorlik berib, `keep`ni hech qachon tanlamay.
/// `inflight` controller'lar (hali `initialize()` tugamagan) haqiqiy
/// cancel API yo'qligi sababli bu yerda majburan evict qilinmaydi — ular
/// `shouldDiscardOnComplete` orqali tugagan zahoti o'z-o'zidan tozalanadi.
/// Evict qilish kerak bo'lmasa yoki qiladigan hech narsa topilmasa — `null`.
String? selectEvictionVictim({
  required List<String> readyKeys,
  required Set<String> inflightKeys,
  required Set<String> wanted,
  required String keep,
  required int maxReady,
}) {
  final live = <String>{...readyKeys, ...inflightKeys};
  final over = live.length > maxReady ||
      (live.length >= maxReady && !live.contains(keep));
  if (!over) return null;
  for (final k in readyKeys) {
    if (k != keep && !wanted.contains(k)) return k;
  }
  for (final k in readyKeys) {
    if (k != keep) return k;
  }
  return null;
}

/// `_create()` uchun: `initialize()` muvaffaqiyatli tugagan controller
/// hali ham kerakmi (generatsiya eskirmaganmi)?
bool shouldDiscardOnComplete(String url, Set<String> wanted) =>
    !wanted.contains(url);
