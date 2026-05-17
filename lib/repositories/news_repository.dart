import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/news_item.dart';

/// `admin_news` collection учун репозиторий.
///
/// Жуфт йукуни:
///   - **ёзиш** — фақат админ (Cloud rules томонидан текширилади).
///   - **ўқиш** — ҳаммаси.
///
/// Барча хабарлар Firestore'дан `orderBy('createdAt', desc)` билан олинади.
/// Audience фильтри клиент томонда қилинади (ва server-rules ҳам).
class NewsRepository {
  NewsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('admin_news');

  /// Барча янгиликларни оқим бўйича.
  /// [audiences] — фойдаланувчи аудитория ўзи учун қандай категория мос келади
  /// (ўз ролига қараб, мисол: `['all', 'users']`).
  Stream<List<NewsItem>> watchAll({
    List<String> audiences = const ['all'],
    int limit = 50,
  }) {
    return _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map(NewsItem.fromDoc)
            .where((n) =>
                audiences.contains('all') || audiences.contains(n.audience))
            .toList(growable: false));
  }

  /// Бир мартагина олиш.
  Future<List<NewsItem>> fetchRecent({
    int limit = 50,
  }) async {
    final snap = await _col
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(NewsItem.fromDoc).toList(growable: false);
  }

  /// `lastNewsReadAt`дан кейин келган хабарлар сони (badge учун).
  Future<int> countUnread(
      String userId, DateTime? lastReadAt, List<String> audiences) async {
    if (userId.isEmpty) return 0;
    Query<Map<String, dynamic>> q = _col;
    if (lastReadAt != null) {
      q = q.where('createdAt',
          isGreaterThan: Timestamp.fromDate(lastReadAt));
    }
    final snap = await q.limit(50).get();
    var count = 0;
    for (final d in snap.docs) {
      final n = NewsItem.fromDoc(d);
      if (audiences.contains('all') || audiences.contains(n.audience)) {
        count++;
      }
    }
    return count;
  }

  /// `lastNewsReadAt`ни ҳозирги вақтга ўзгартириш.
  Future<void> markAllRead(String userId) async {
    if (userId.isEmpty) return;
    await _db
        .collection('users')
        .doc(userId)
        .set({'lastNewsReadAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
  }

  /// Янги хабар яратиш (фақат админ).
  Future<DocumentReference<Map<String, dynamic>>> create(NewsItem item) async {
    return _col.add(item.toCreateMap());
  }

  /// Хабарни ўчириш.
  Future<void> delete(String id) async {
    if (id.isEmpty) return;
    await _col.doc(id).delete();
  }
}
