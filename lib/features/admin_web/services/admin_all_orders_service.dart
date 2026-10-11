import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/order_index_entry.dart';

/// «Барча буюртмалар» фильтри. `stuckOnly` да ҳолат фильтри ишлатилмайди
/// (индекс: `module + stuckAt`).
@immutable
class AllOrdersFilter {
  const AllOrdersFilter({this.module, this.status, this.stuckOnly = false});

  final String? module;
  final String? status;
  final bool stuckOnly;

  AllOrdersFilter copyWith({
    Object? module = _keep,
    Object? status = _keep,
    bool? stuckOnly,
  }) =>
      AllOrdersFilter(
        module: identical(module, _keep) ? this.module : module as String?,
        status: identical(status, _keep) ? this.status : status as String?,
        stuckOnly: stuckOnly ?? this.stuckOnly,
      );

  static const _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is AllOrdersFilter &&
      other.module == module &&
      other.status == status &&
      other.stuckOnly == stuckOnly;

  @override
  int get hashCode => Object.hash(module, status, stuckOnly);
}

@immutable
class AllOrdersCounts {
  const AllOrdersCounts({required this.byStatus, required this.stuck});
  final Map<String, int> byStatus;
  final int stuck;
}

/// Маълумот манбаи — экран тестида fake билан алмаштирилади.
abstract class AllOrdersSource {
  Stream<List<OrderIndexEntry>> watch(AllOrdersFilter filter, int limit);
  Future<AllOrdersCounts> counts(AllOrdersFilter filter, DateTime now);

  /// Буюртма ID (тўлиқ) ёки мижоз телефонининг охирги 4 рақами.
  Future<List<OrderIndexEntry>> search(String query);
}

class FirestoreAllOrdersSource implements AllOrdersSource {
  FirestoreAllOrdersSource({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('order_index');

  /// Индекслар: (module, createdAt↓), (normStatus, createdAt↓),
  /// (module, normStatus, createdAt↓), (module, stuckAt↑).
  Query<Map<String, dynamic>> _query(AllOrdersFilter f, DateTime now) {
    Query<Map<String, dynamic>> q = _col;
    if (f.module != null) q = q.where('module', isEqualTo: f.module);
    if (f.stuckOnly) {
      return q
          .where('stuckAt', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .orderBy('stuckAt');
    }
    if (f.status != null) q = q.where('normStatus', isEqualTo: f.status);
    return q.orderBy('createdAt', descending: true);
  }

  @override
  Stream<List<OrderIndexEntry>> watch(AllOrdersFilter filter, int limit) =>
      _query(filter, DateTime.now())
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(OrderIndexEntry.fromDoc).toList());

  @override
  Future<AllOrdersCounts> counts(AllOrdersFilter filter, DateTime now) async {
    Query<Map<String, dynamic>> base = _col;
    if (filter.module != null) {
      base = base.where('module', isEqualTo: filter.module);
    }
    // `count()` — listener эмас; 1000 ҳужжатга 1 ўқиш (37-банд).
    final statuses = OrderIndexEntry.statusOrder;
    final futures = [
      for (final s in statuses)
        base.where('normStatus', isEqualTo: s).count().get(),
      base
          .where('stuckAt', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .count()
          .get(),
    ];
    final res = await Future.wait(futures);
    return AllOrdersCounts(
      byStatus: {
        for (var i = 0; i < statuses.length; i++) statuses[i]: res[i].count ?? 0,
      },
      stuck: res.last.count ?? 0,
    );
  }

  @override
  Future<List<OrderIndexEntry>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final digits = phoneDigits(q);
    final snap = digits.length == 4 && digits == q
        ? await _col.where('customerTail', isEqualTo: digits).limit(50).get()
        : await _col.where('sourceId', isEqualTo: q).limit(20).get();
    return snap.docs.map(OrderIndexEntry.fromDoc).toList();
  }
}

/// Жорий админнинг бўлим рухсатлари (`admin_section_grants/{телефон}`).
/// Сайдбар ва «Буюртмалар» табларини шу белгилайди; ҳақиқий текширув —
/// rules (`order_index` ўқиш).
class AdminSectionGrantsService extends ChangeNotifier {
  AdminSectionGrantsService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String? _forPhone;
  Set<String> _sections = const {};

  bool has(String section) => _sections.contains(section);

  /// Кирган админ телефони ўзгарса — қайта обуна.
  void bind(String? rawPhone) {
    final id = rawPhone == null || rawPhone.isEmpty ? null : canonicalPhoneId(rawPhone);
    if (id == _forPhone) return;
    _forPhone = id;
    _sub?.cancel();
    _sub = null;
    _sections = const {};
    if (id == null || id.length < 12) {
      notifyListeners();
      return;
    }
    _sub = _db.collection('admin_section_grants').doc(id).snapshots().listen(
      (s) {
        final raw = s.data()?['sections'];
        _sections = raw is List ? raw.whereType<String>().toSet() : const {};
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('admin_section_grants: $e');
        _sections = const {};
        notifyListeners();
      },
    );
  }

  /// Бошқа ходимнинг рухсати (Фойдаланувчилар бўлими).
  Stream<bool> watchFor(String rawPhone, String section) {
    final id = canonicalPhoneId(rawPhone);
    return _db
        .collection('admin_section_grants')
        .doc(id)
        .snapshots()
        .map((s) {
      final raw = s.data()?['sections'];
      return raw is List && raw.contains(section);
    });
  }

  /// `null` — муваффақият; акс ҳолда фойдаланувчига матн.
  static Future<String?> setGrant({
    required String targetPhone,
    required String section,
    required bool granted,
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminSetSectionGrant')
          .call<Map<String, dynamic>>({
        'targetPhone': targetPhone,
        'section': section,
        'granted': granted,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      final code = e.details is Map ? (e.details as Map)['code'] : null;
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        return 'Сервер функцияси ҳали deploy қилинмаган: adminSetSectionGrant';
      }
      if (code == 'TARGET_NOT_PANEL') {
        return 'Рухсат фақат админ панел ходимига берилади (аввал рол беринг).';
      }
      return e.message ?? 'Рухсат ўзгармади (${e.code})';
    } catch (e) {
      return 'Хатолик: $e';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
