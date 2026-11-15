import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/formatters.dart';
import 'data/favorites_repository.dart';
import 'domain/favorite_ref.dart';

/// Юракни босиш натижаси (UI шунга қараб хабар кўрсатади).
enum FavoriteToggleOutcome { added, removed, guest, busy, invalid, failed }

/// ❤ Танланганлар — илова бўйича ЯГОНА ҳолат (эга 2026-11-15: сақланган рўйхат, барча бозорлар).
///
/// * Битта Firestore тингловчи (`users/{uid}/favorites`) — ҳисоблагич ва барча юраклар шундан;
///   карточкалар алоҳида ўқимайди.
/// * `uid` — Phone Auth токенидаги рақам (`canonicalPhoneId`), rules ҳам шуни текширади.
///   Телефонсиз/аноним — меҳмон ([FavoriteToggleOutcome.guest]).
/// * Босиш — оптимистик: юрак дарров ўзгаради, хато бўлса олдинги ҳолатга қайтади.
class FavoritesController extends ChangeNotifier {
  FavoritesController({FavoritesRepository? repository, Stream<String>? uidStream})
      : _repository = repository,
        _uidStream = uidStream;

  static FavoritesController? _instance;

  /// Илова бўйича нусха (биринчи мурожаатда яратилади, тингловчи [ensureStarted] да).
  static FavoritesController get instance => _instance ??= FavoritesController();

  @visibleForTesting
  static set debugInstance(FavoritesController? c) => _instance = c;

  FavoritesRepository? _repository;
  Stream<String>? _uidStream;
  StreamSubscription<String>? _uidSub;
  StreamSubscription<List<FavoriteRef>>? _favSub;
  bool _started = false;

  String _uid = '';
  List<FavoriteRef> _items = const [];
  Set<String> _keys = const {};

  /// Жавоби кутилаётган босишлар: калит → кўрсатиладиган ҳолат (оптимистик).
  final Map<String, bool> _pending = {};

  String get uid => _uid;
  bool get isGuest => _uid.length < 11;

  /// Сервердаги рўйхат (янгилари биринчи).
  List<FavoriteRef> get items => _items;

  /// Ҳисоблагич: сервер рўйхати + оптимистик ўзгаришлар.
  int get count {
    var n = _keys.length;
    _pending.forEach((k, v) {
      final has = _keys.contains(k);
      if (v && !has) n++;
      if (!v && has) n--;
    });
    return n < 0 ? 0 : n;
  }

  bool isFavorite(String key) => _pending[key] ?? _keys.contains(key);

  /// Тингловчини бир марта ишга туширади. Firebase йўқ муҳитда (widget тестлар) жим қолади.
  void ensureStarted() {
    if (_started) return;
    _started = true;
    try {
      _repository ??= FirestoreFavoritesRepository();
      _uidStream ??= FirebaseAuth.instance
          .authStateChanges()
          .map((u) => u == null || u.isAnonymous ? '' : canonicalPhoneId(u.phoneNumber ?? ''));
      _uidSub = _uidStream!.distinct().listen(_onUid, onError: (Object e) => _log('auth', e));
    } catch (e) {
      _log('start', e);
    }
  }

  void _onUid(String uid) {
    if (uid == _uid && _favSub != null) return;
    _uid = uid;
    _favSub?.cancel();
    _favSub = null;
    _items = const [];
    _keys = const {};
    _pending.clear();
    notifyListeners();
    if (isGuest) return;
    _favSub = _repository!.watch(uid).listen((list) {
      _items = list;
      _keys = list.map((e) => e.key).toSet();
      notifyListeners();
    }, onError: (Object e) => _log('watch', e));
  }

  /// Юракни алмаштиради. Натижа UI учун; хато бўлса ҳолат қайтарилади ва диагностика ёзилади.
  Future<FavoriteToggleOutcome> toggle(FavoriteRef ref) async {
    ensureStarted();
    if (isGuest) return FavoriteToggleOutcome.guest;
    if (!ref.isValid) return FavoriteToggleOutcome.invalid;
    final key = ref.key;
    if (_pending.containsKey(key)) return FavoriteToggleOutcome.busy;
    final wasFav = isFavorite(key);
    _pending[key] = !wasFav;
    notifyListeners();
    final uid = _uid;
    try {
      if (wasFav) {
        await _repository!.remove(uid, key);
      } else {
        await _repository!.add(uid, ref);
      }
      // Муваффақият: сервер рўйхати (кеш орқали дарров) ҳақиқатни беради.
      if (!wasFav) {
        _keys = {..._keys, key};
      } else {
        _keys = {..._keys}..remove(key);
        _items = _items.where((e) => e.key != key).toList();
      }
      _pending.remove(key);
      notifyListeners();
      return wasFav ? FavoriteToggleOutcome.removed : FavoriteToggleOutcome.added;
    } catch (e) {
      _pending.remove(key); // rollback
      notifyListeners();
      _log('toggle ${ref.collection} ${wasFav ? 'remove' : 'add'}', e);
      return FavoriteToggleOutcome.failed;
    }
  }

  /// «Мавжуд эмас» элементни рўйхатдан олиб ташлаш.
  Future<bool> remove(String key) async {
    if (isGuest || _pending.containsKey(key)) return false;
    _pending[key] = false;
    notifyListeners();
    try {
      await _repository!.remove(_uid, key);
      _keys = {..._keys}..remove(key);
      _items = _items.where((e) => e.key != key).toList();
      _pending.remove(key);
      notifyListeners();
      return true;
    } catch (e) {
      _pending.remove(key);
      notifyListeners();
      _log('remove', e);
      return false;
    }
  }

  Future<Map<String, Map<String, dynamic>?>> fetchSources(List<FavoriteRef> refs) {
    ensureStarted();
    final repo = _repository;
    if (repo == null || refs.isEmpty) return Future.value(const {});
    return repo.fetchSources(refs);
  }

  /// Диагностика (кодли, PII'сиз): фойдаланувчига умумий хабар, бу ерда — сабаб.
  void _log(String action, Object e) {
    final code = e is FirebaseException ? e.code : e.runtimeType.toString();
    debugPrint('[Favorites] FAVORITES_${action.split(' ').first.toUpperCase()}_FAILED action=$action code=$code');
  }

  @override
  void dispose() {
    _uidSub?.cancel();
    _favSub?.cancel();
    super.dispose();
  }
}
