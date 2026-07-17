import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/formatters.dart';
import '../models/news_item.dart';
import '../models/user_model.dart';

/// `admin_news` — broadcast / мурожаат / буюртма (алохида фильтр).
enum NewsFeedKind { broadcast, dialog, order }

/// `admin_news` — умумий янгиликлар ва буюртма хабарлари (алохида фильтр).
class NewsRepository {
  NewsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('admin_news');

  static bool _matchesFeed(NewsItem n, NewsFeedKind feed) {
    switch (feed) {
      case NewsFeedKind.broadcast:
        return n.isBroadcastNews;
      case NewsFeedKind.dialog:
        return n.isDialogNews;
      case NewsFeedKind.order:
        return n.isOrderNews;
    }
  }

  static List<NewsItem> _filterForUser(
    Iterable<NewsItem> items, {
    required List<String> audiences,
    required String userId,
    required NewsFeedKind feed,
  }) {
    final uid = phoneDigits(userId);
    return items
        .where((n) => _matchesFeed(n, feed))
        .where((n) => n.isVisibleTo(userId: uid, audiences: audiences))
        .toList(growable: false);
  }

  static List<NewsItem> _mergeDedupe(List<NewsItem> a, List<NewsItem> b) {
    final byId = <String, NewsItem>{};
    for (final n in [...a, ...b]) {
      byId[n.id] = n;
    }
    final merged = byId.values.toList()
      ..sort((x, y) {
        if (x.priority != y.priority) {
          return y.priority.compareTo(x.priority);
        }
        return y.createdAt.compareTo(x.createdAt);
      });
    return merged;
  }

  Stream<List<NewsItem>> _watchForUser({
    required List<String> audiences,
    required String userId,
    required NewsFeedKind feed,
    int limit = 50,
  }) {
    final uid = canonicalPhoneId(userId);
    final controller = StreamController<List<NewsItem>>.broadcast();
    List<NewsItem>? global;
    List<NewsItem>? personal;
    var personalReady = uid.length < 9;

    void emit() {
      if (global == null) return;
      if (!personalReady) return;
      final merged = _mergeDedupe(
        _filterForUser(global!, audiences: audiences, userId: uid, feed: feed),
        personal != null
            ? _filterForUser(personal!,
                audiences: audiences, userId: uid, feed: feed)
            : const [],
      );
      if (!controller.isClosed) controller.add(merged.take(limit).toList());
    }

    final subGlobal = _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .listen((snap) {
      global = snap.docs.map(NewsItem.fromDoc).toList(growable: false);
      emit();
    }, onError: controller.addError);

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subPersonal;
    if (uid.length >= 9) {
      final aliases = phoneAliases(uid);
      final queryAliases =
          aliases.length > 10 ? aliases.sublist(0, 10) : aliases;
      subPersonal = _col
          .where('targetUserId', whereIn: queryAliases)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .snapshots()
          .listen((snap) {
        personal = snap.docs.map(NewsItem.fromDoc).toList(growable: false);
        personalReady = true;
        emit();
      }, onError: (e, _) {
        personal = const [];
        personalReady = true;
        emit();
        if (!controller.isClosed) controller.addError(e);
      });
    } else {
      personal = const [];
      personalReady = true;
      emit();
    }

    controller.onCancel = () async {
      await subGlobal.cancel();
      await subPersonal?.cancel();
    };

    return controller.stream;
  }

  /// Админ broadcast янгиликлар (шахсий/буюртма эмас).
  Stream<List<NewsItem>> watchBroadcastNews({
    List<String> audiences = const ['all'],
    String userId = '',
    int limit = 50,
  }) =>
      _watchForUser(
        audiences: audiences,
        userId: userId,
        feed: NewsFeedKind.broadcast,
        limit: limit,
      );

  /// Шахсий мурожаат жавоблари (`targetUserId`).
  Stream<List<NewsItem>> watchDialogNews({
    String userId = '',
    int limit = 50,
  }) =>
      _watchForUser(
        audiences: const ['all', 'user'],
        userId: userId,
        feed: NewsFeedKind.dialog,
        limit: limit,
      );

  /// Фақат буюртма статус хабарлари.
  Stream<List<NewsItem>> watchOrderNews({
    String userId = '',
    int limit = 50,
  }) =>
      _watchForUser(
        audiences: const ['all', 'user'],
        userId: userId,
        feed: NewsFeedKind.order,
        limit: limit,
      );

  static int countUnreadInList(
    List<NewsItem> items,
    DateTime? lastReadAt,
  ) {
    if (lastReadAt == null) return items.length;
    return items.where((n) => n.createdAt.isAfter(lastReadAt)).length;
  }

  static UserModel? _userFromSnapshots(
    DocumentSnapshot<Map<String, dynamic>>? primary,
    DocumentSnapshot<Map<String, dynamic>>? fallback,
  ) {
    if (primary != null && primary.exists) {
      return UserModel.fromDoc(primary);
    }
    if (fallback != null && fallback.exists) {
      return UserModel.fromDoc(fallback);
    }
    return null;
  }

  List<String> _userDocIdsForNews(String userId) {
    final canon = canonicalPhoneId(userId);
    final raw = phoneDigits(userId);
    final ids = <String>{canon, raw};
    if (raw.length >= 12 && raw.startsWith('998')) {
      ids.add(raw.substring(3));
    }
    return ids.where((id) => id.length >= 9).toList(growable: false);
  }

  /// Жонли ўқилмаганлар — пастки badge.
  /// Фақат 2 ta stream: `users/{uid}` + `config/home_news_badge`
  /// (эски вариант 6–8 ta admin_news/support stream очарди).
  Stream<int> watchUnreadTotal({
    required String userId,
    required List<String> audiences,
    int messagesExtra = 0,
    int limit = 50,
  }) {
    final uid = canonicalPhoneId(userId);
    if (uid.length < 9) return Stream.value(0);

    final controller = StreamController<int>.broadcast();
    UserModel? user;
    var broadcastSeq = 0;
    var personalBootstrapStarted = false;

    void emit() {
      if (controller.isClosed) return;
      final personal = user?.homeBadgePersonal;
      if (personal == null && !personalBootstrapStarted) {
        personalBootstrapStarted = true;
        unawaited(recomputeHomeBadgePersonal(uid).catchError((_) => 0));
      }
      final personalN = personal ?? 0;
      // null lastSeen → ретроактив badge чиқармаслик (биринчи deploy).
      final lastSeen = user?.lastSeenBroadcastSeq;
      final broadcastN =
          lastSeen == null ? 0 : (broadcastSeq - lastSeen).clamp(0, 999);
      controller.add(personalN + broadcastN + messagesExtra);
    }

    final subUser = _db.collection('users').doc(uid).snapshots().listen(
      (snap) {
        user = snap.exists ? UserModel.fromDoc(snap) : null;
        emit();
      },
      onError: controller.addError,
    );

    final subBadge =
        _db.collection('config').doc('home_news_badge').snapshots().listen(
      (snap) {
        broadcastSeq = (snap.data()?['broadcastSeq'] as num?)?.toInt() ?? 0;
        emit();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await subUser.cancel();
      await subBadge.cancel();
    };

    return controller.stream;
  }

  /// Dialog + order + support chat → `users.homeBadgePersonal`.
  Future<int> recomputeHomeBadgePersonal(String userId) async {
    final uid = canonicalPhoneId(userId);
    if (uid.length < 9) return 0;

    UserModel? user;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      if (snap.exists) user = UserModel.fromDoc(snap);
    } catch (_) {}

    final dialog = await countUnreadDialog(uid, user?.lastMessagesReadAt);
    final orders = await countUnreadOrders(uid, user?.lastOrderNewsReadAt);
    var support = 0;
    try {
      final chat = await _db.collection('support_chats').doc(uid).get();
      if (chat.exists && (chat.data()?['lastFromAdmin'] ?? false) == true) {
        support = 1;
      }
    } catch (_) {}

    final total = dialog + orders + support;
    for (final id in _userDocIdsForNews(uid)) {
      await _db.collection('users').doc(id).set(
        {
          'homeBadgePersonal': total,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    return total;
  }

  Future<int> _currentBroadcastSeq() async {
    try {
      final snap = await _db.collection('config').doc('home_news_badge').get();
      return (snap.data()?['broadcastSeq'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Битта бўлим учун жонли ўқилмаганлар (таб badge).
  Stream<int> watchUnreadCount({
    required String userId,
    required List<String> audiences,
    required NewsFeedKind feed,
    int chatUnreadExtra = 0,
    int limit = 50,
  }) {
    final uid = canonicalPhoneId(userId);
    if (uid.length < 9) return Stream.value(0);

    final controller = StreamController<int>.broadcast();
    UserModel? user;
    List<NewsItem> items = const [];
    var supportChatUnread = false;
    final docIds = _userDocIdsForNews(userId);
    final primaryId = docIds.isNotEmpty ? docIds.first : uid;
    final fallbackId = docIds.length > 1 ? docIds[1] : null;

    void emit() {
      if (controller.isClosed) return;
      final lastRead = switch (feed) {
        NewsFeedKind.broadcast => user?.lastNewsReadAt,
        NewsFeedKind.dialog => user?.lastMessagesReadAt,
        NewsFeedKind.order => user?.lastOrderNewsReadAt,
      };
      var n = countUnreadInList(items, lastRead);
      if (feed == NewsFeedKind.dialog) {
        n += chatUnreadExtra;
        if (supportChatUnread) n += 1;
      }
      controller.add(n);
    }

    DocumentSnapshot<Map<String, dynamic>>? primarySnap;
    DocumentSnapshot<Map<String, dynamic>>? fallbackSnap;

    void emitUser() {
      user = _userFromSnapshots(primarySnap, fallbackSnap);
      emit();
    }

    final subUser = _db.collection('users').doc(primaryId).snapshots().listen(
      (snap) {
        primarySnap = snap;
        emitUser();
      },
      onError: controller.addError,
    );

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subUserAlt;
    if (fallbackId != null) {
      subUserAlt = _db.collection('users').doc(fallbackId).snapshots().listen(
        (snap) {
          fallbackSnap = snap;
          emitUser();
        },
        onError: controller.addError,
      );
    }

    final newsStream = switch (feed) {
      NewsFeedKind.broadcast => watchBroadcastNews(
          audiences: audiences,
          userId: uid,
          limit: limit,
        ),
      NewsFeedKind.dialog => watchDialogNews(userId: uid, limit: limit),
      NewsFeedKind.order => watchOrderNews(userId: uid, limit: limit),
    };
    final subNews = newsStream.listen(
      (list) {
        items = list;
        emit();
      },
      onError: controller.addError,
    );

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subSupportChat;
    if (feed == NewsFeedKind.dialog) {
      subSupportChat =
          _db.collection('support_chats').doc(uid).snapshots().listen(
        (snap) {
          final d = snap.data();
          supportChatUnread =
              d != null && (d['lastFromAdmin'] ?? false) == true;
          emit();
        },
        onError: controller.addError,
      );
    }

    controller.onCancel = () async {
      await subUser.cancel();
      await subUserAlt?.cancel();
      await subNews.cancel();
      await subSupportChat?.cancel();
    };

    return controller.stream;
  }

  Future<int> _countUnreadFiltered({
    required String userId,
    required List<String> audiences,
    required DateTime? lastReadAt,
    required NewsFeedKind feed,
  }) async {
    final uid = canonicalPhoneId(userId);
    if (uid.isEmpty) return 0;

    final ids = <String>{};
    var total = 0;

    Query<Map<String, dynamic>> globalQ =
        _col.orderBy('createdAt', descending: true);
    if (lastReadAt != null) {
      globalQ = globalQ.where(
        'createdAt',
        isGreaterThan: Timestamp.fromDate(lastReadAt),
      );
    }
    final globalSnap = await globalQ.limit(50).get();
    for (final d in globalSnap.docs) {
      final n = NewsItem.fromDoc(d);
      if (!_matchesFeed(n, feed)) continue;
      if (!n.isVisibleTo(userId: uid, audiences: audiences)) continue;
      if (ids.add(n.id)) total++;
    }

    if (feed != NewsFeedKind.dialog) return total;

    final aliases = phoneAliases(uid);
    final queryAliases = aliases.length > 10 ? aliases.sublist(0, 10) : aliases;
    Query<Map<String, dynamic>> personalQ = _col
        .where('targetUserId', whereIn: queryAliases)
        .orderBy('createdAt', descending: true);
    if (lastReadAt != null) {
      personalQ = personalQ.where(
        'createdAt',
        isGreaterThan: Timestamp.fromDate(lastReadAt),
      );
    }
    final personalSnap = await personalQ.limit(30).get();
    for (final d in personalSnap.docs) {
      final n = NewsItem.fromDoc(d);
      if (!_matchesFeed(n, feed)) continue;
      if (!n.isVisibleTo(userId: uid, audiences: audiences)) continue;
      if (ids.add(n.id)) total++;
    }

    return total;
  }

  Future<int> countUnreadBroadcast(
    String userId,
    DateTime? lastReadAt,
    List<String> audiences,
  ) =>
      _countUnreadFiltered(
        userId: userId,
        audiences: audiences,
        lastReadAt: lastReadAt,
        feed: NewsFeedKind.broadcast,
      );

  Future<int> countUnreadDialog(
    String userId,
    DateTime? lastReadAt,
  ) =>
      _countUnreadFiltered(
        userId: userId,
        audiences: const ['all', 'user'],
        lastReadAt: lastReadAt,
        feed: NewsFeedKind.dialog,
      );

  Future<int> countUnreadGeneral(
    String userId,
    DateTime? lastReadAt,
    List<String> audiences,
  ) =>
      countUnreadBroadcast(userId, lastReadAt, audiences);

  Future<int> countUnreadOrders(
    String userId,
    DateTime? lastOrderReadAt,
  ) =>
      _countUnreadFiltered(
        userId: userId,
        audiences: const ['all', 'user'],
        lastReadAt: lastOrderReadAt,
        feed: NewsFeedKind.order,
      );

  Future<void> markGeneralRead(String userId) async {
    if (userId.isEmpty) return;
    final seq = await _currentBroadcastSeq();
    final patch = {
      'lastNewsReadAt': FieldValue.serverTimestamp(),
      'lastSeenBroadcastSeq': seq,
    };
    for (final id in _userDocIdsForNews(userId)) {
      await _db.collection('users').doc(id).set(patch, SetOptions(merge: true));
    }
  }

  Future<void> markOrderNewsRead(String userId) async {
    if (userId.isEmpty) return;
    final patch = {'lastOrderNewsReadAt': FieldValue.serverTimestamp()};
    for (final id in _userDocIdsForNews(userId)) {
      await _db.collection('users').doc(id).set(patch, SetOptions(merge: true));
    }
    await recomputeHomeBadgePersonal(userId);
  }

  Future<void> markMessagesRead(String userId) async {
    if (userId.isEmpty) return;
    final patch = {'lastMessagesReadAt': FieldValue.serverTimestamp()};
    for (final id in _userDocIdsForNews(userId)) {
      await _db.collection('users').doc(id).set(patch, SetOptions(merge: true));
    }
    // Support chat "lastFromAdmin" client markUserRead орқали тўғриланади;
    // badge қайта ҳисобланади.
    await recomputeHomeBadgePersonal(userId);
  }

  Future<void> markAllRead(String userId) async => markGeneralRead(userId);

  /// Admin panel — барча `admin_news` (фильтр: буюртма ёки умумiy).
  Stream<List<NewsItem>> watchForAdmin({
    required bool orderOnly,
    int limit = 300,
  }) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(NewsItem.fromDoc)
              .where((n) => n.isOrderNews == orderOnly)
              .toList(growable: false),
        );
  }

  /// Admin sidebar badge — яangi (hali ochilmagan) xabarlar soni.
  Stream<int> watchAdminUnreadCount({
    required bool orderOnly,
    required Listenable readListenable,
    required DateTime? Function() lastSeenAt,
    int limit = 300,
  }) {
    final controller = StreamController<int>.broadcast();
    List<NewsItem> items = const [];

    void emit() {
      if (controller.isClosed) return;
      controller.add(countUnreadInList(items, lastSeenAt()));
    }

    void onReadChanged() => emit();

    readListenable.addListener(onReadChanged);

    final subNews = watchForAdmin(orderOnly: orderOnly, limit: limit).listen(
      (list) {
        items = list;
        emit();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      readListenable.removeListener(onReadChanged);
      await subNews.cancel();
    };

    return controller.stream;
  }

  Future<List<NewsItem>> fetchRecent({int limit = 50}) async {
    final snap =
        await _col.orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs.map(NewsItem.fromDoc).toList(growable: false);
  }

  Future<DocumentReference<Map<String, dynamic>>> create(NewsItem item) async {
    return _col.add(item.toCreateMap());
  }

  Future<void> delete(String id) async {
    if (id.isEmpty) return;
    await _col.doc(id).delete();
  }

  /// Админ «Push qayta yuborish» — CF `onAdminNewsUpdate` триггерланadi.
  Future<void> requestPushResend(String id) async {
    if (id.isEmpty) return;
    await _col.doc(id).set(
      {'pushResendAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }
}
