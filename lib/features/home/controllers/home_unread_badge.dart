import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';

/// Пастки менюдаги «Хабарлар» таби белгиси: ўқилмаган хабарлар сони.
///
/// Манба — `NewsRepository.watchUnreadTotal` (шахсий: мурожаат + буюртма +
/// қўллаб-қувватлаш чати, плюс умумий янгиликлар). Эски пастки панелда шу
/// оқим уланган эди; `AvaBottomNav`га ўтишда (B-3) белги параметри қолди,
/// лекин ҳеч ким уни бермади — янги хабар борлиги кўринмай қолди.
///
/// [watchExtra] — қўшимча ўқилмаганлар (Улгуржи/Хитой «Буюртма чатлари»,
/// `DealChatRepository.watchUnreadTotal`; эга 2026-11-01: «бош саҳифада
/// ўқилмаган хабарлар сони кўрсатилсин»). Белги = иккаласининг йиғиндиси;
/// бир оқим хато берса — унинг охирги сони қолади, иккинчиси ишлайверади.
///
/// Аудитория (`['all', роль]`) `NewsHubScreen` билан бир хил қоида бўйича
/// олинади (`UserAudience`) — белги ва очилган экран сони бир хил чиқсин.
class HomeUnreadBadge extends ChangeNotifier {
  HomeUnreadBadge({required this.watch, required this.audience, this.watchExtra});

  /// `NewsRepository.watchUnreadTotal`.
  final Stream<int> Function({
    required String userId,
    required List<String> audiences,
  }) watch;

  /// Ҳозирги аудитория роли (`UserAudience.current`).
  final Future<String> Function() audience;

  /// Рақам (`phoneDigits`) бўйича қўшимча ўқилмаганлар; роль/аудиторияга боғлиқ эмас.
  final Stream<int> Function(String userId)? watchExtra;

  /// Кўрсатиладиган сон (0 — белги йўқ).
  int total = 0;

  int _news = 0;
  int _extra = 0;
  String _key = '';
  int _generation = 0;
  bool _disposed = false;
  StreamSubscription<int>? _sub;
  StreamSubscription<int>? _extraSub;

  /// Телефон ёки роль ўзгарганда оқимни қайта улайди; ўзгармаган бўлса —
  /// ҳеч нарса қилмайди (бош саҳифага қайтишда ортиқча Firestore тингловчиси
  /// очилмайди).
  Future<void> sync(String phone) async {
    final uid = phoneDigits(phone);
    final gen = ++_generation;
    if (uid.length < 9) {
      _stop();
      _set();
      return;
    }
    final role = await audience();
    // Кейинроқ келган `sync` устун: эски чақирув натижаси ташланади.
    if (_disposed || gen != _generation) return;
    final key = '$uid|$role';
    if (key == _key) return;
    _stop();
    _key = key;
    _sub = watch(userId: uid, audiences: ['all', role]).listen(
      (n) => _set(news: n),
      // Оқим узилса охирги сон қолади — белги «сакраб» 0 бўлмайди.
      onError: (_) {},
    );
    final extra = watchExtra;
    if (extra != null) {
      try {
        _extraSub = extra(uid).listen((n) => _set(extra: n), onError: (_) {});
      } catch (e) {
        // Қўшимча манба очилмаса (Firebase йўқ — тест) асосий белги ишлайверади.
        debugPrint('[HomeUnreadBadge] extra: $e');
      }
    }
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _extraSub?.cancel();
    _extraSub = null;
    _key = '';
    _news = 0;
    _extra = 0;
  }

  void _set({int? news, int? extra}) {
    if (_disposed) return;
    if (news != null) _news = news;
    if (extra != null) _extra = extra;
    final n = _news + _extra;
    if (n == total) return;
    total = n;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _extraSub?.cancel();
    super.dispose();
  }
}
