import 'package:cloud_functions/cloud_functions.dart';

/// Админ панел: «Ҳисобни ўчириш» (functions/account_deletion.js `admin*AccountDeletion*`).
/// Ролни ва сабабни СЕРВЕР текширади; бу ерда фақат чақириш ва натижани моделга ўгириш.

class AdminDeletionRow {
  const AdminDeletionRow({
    required this.uid,
    required this.status,
    required this.source,
    required this.attempts,
    required this.walletAtRequest,
    required this.hidePending,
    required this.lastError,
    required this.blockers,
    this.requestedAt,
    this.scheduledFor,
    this.nextCheckAt,
    this.completedAt,
  });

  final String uid;
  final String status;
  final String source;
  final int attempts;
  final int walletAtRequest;
  final bool hidePending;
  final String lastError;
  final List<String> blockers; // `код:сони`
  final DateTime? requestedAt;
  final DateTime? scheduledFor;
  final DateTime? nextCheckAt;
  final DateTime? completedAt;

  bool get canCancel => status == 'PENDING' || status == 'POSTPONED' || status == 'FAILED';
  bool get canRetry => status == 'FAILED';

  static DateTime? _d(Object? ms) => ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;

  factory AdminDeletionRow.fromMap(Map<Object?, Object?> m) => AdminDeletionRow(
        uid: (m['uid'] ?? '').toString(),
        status: (m['status'] ?? '').toString(),
        source: (m['source'] ?? 'app').toString(),
        attempts: (m['attempts'] as num?)?.toInt() ?? 0,
        walletAtRequest: (m['walletAtRequest'] as num?)?.toInt() ?? 0,
        hidePending: m['hidePending'] == true,
        lastError: (m['lastError'] ?? '').toString(),
        blockers: [
          for (final b in (m['lastBlockers'] as List?) ?? const [])
            if (b is Map) '${b['code']}:${b['count'] ?? 0}',
        ],
        requestedAt: _d(m['requestedAtMs']),
        scheduledFor: _d(m['scheduledForMs']),
        nextCheckAt: _d(m['nextCheckAtMs']),
        completedAt: _d(m['completedAtMs']),
      );
}

class AdminDeletionEvent {
  const AdminDeletionEvent({required this.type, this.at, this.meta = const {}});

  final String type;
  final DateTime? at;
  final Map<String, Object?> meta;
}

class AdminDeletionDetail {
  const AdminDeletionDetail({
    required this.row,
    required this.steps,
    required this.events,
    required this.hiddenCount,
  });

  final AdminDeletionRow row;

  /// қадам номи → тугаганми
  final Map<String, bool> steps;
  final List<AdminDeletionEvent> events;
  final int hiddenCount;

  factory AdminDeletionDetail.fromMap(Map<Object?, Object?> m) {
    final steps = <String, bool>{};
    final raw = m['steps'];
    if (raw is Map) {
      raw.forEach((k, v) => steps[k.toString()] = v is Map && v['done'] == true);
    }
    return AdminDeletionDetail(
      row: AdminDeletionRow.fromMap(m),
      steps: steps,
      hiddenCount: (m['hiddenCount'] as num?)?.toInt() ?? 0,
      events: [
        for (final e in (m['events'] as List?) ?? const [])
          if (e is Map)
            AdminDeletionEvent(
              type: (e['type'] ?? '').toString(),
              at: AdminDeletionRow._d(e['atMs']),
              meta: e['meta'] is Map ? Map<String, Object?>.from(e['meta'] as Map) : const {},
            ),
      ],
    );
  }
}

class AdminDeletionGate {
  const AdminDeletionGate({required this.enabled, required this.waitDays, required this.allow});

  final bool enabled;
  final int waitDays;
  final List<String> allow;

  /// `off` | `internal` | `public`
  String get mode => !enabled ? 'off' : (allow.isNotEmpty ? 'internal' : 'public');

  factory AdminDeletionGate.fromMap(Map<Object?, Object?> m) => AdminDeletionGate(
        enabled: m['enabled'] == true,
        waitDays: (m['waitDays'] as num?)?.toInt() ?? 10,
        allow: [for (final a in (m['allow'] as List?) ?? const []) a.toString()],
      );
}

/// Сервер рад этган ҳолат: `code` (REASON_REQUIRED, ACCOUNT_DELETION_BLOCKED, …) — экран тушунарли матн танлайди.
class AdminDeletionFailure implements Exception {
  const AdminDeletionFailure(this.code, [this.message = '']);

  final String code;
  final String message;

  @override
  String toString() => 'AdminDeletionFailure($code)';
}

class AccountDeletionAdminService {
  AccountDeletionAdminService({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  Future<List<AdminDeletionRow>> list({List<String>? statuses, int limit = 100}) async {
    final res = await _call('adminListAccountDeletions', {
      if (statuses != null) 'statuses': statuses,
      'limit': limit,
    });
    return [
      for (final r in (res['rows'] as List?) ?? const [])
        if (r is Map) AdminDeletionRow.fromMap(Map<Object?, Object?>.from(r)),
    ];
  }

  Future<AdminDeletionDetail> detail(String uid) async =>
      AdminDeletionDetail.fromMap(await _call('adminGetAccountDeletion', {'uid': uid}));

  Future<void> cancel(String uid, String reason) async =>
      _void('adminCancelAccountDeletion', {'uid': uid, 'reason': reason});

  Future<void> retry(String uid, String reason) async =>
      _void('adminRetryAccountDeletion', {'uid': uid, 'reason': reason});

  Future<void> request(String phone, String reason) async =>
      _void('adminRequestAccountDeletion', {'phone': phone, 'reason': reason});

  Future<AdminDeletionGate> gate() async => AdminDeletionGate.fromMap(await _call('adminGetAccountDeletionGate', {}));

  Future<void> setGate({
    required bool enabled,
    required int waitDays,
    required List<String> allow,
    required String reason,
  }) async =>
      _void('adminSetAccountDeletionGate', {
        'enabled': enabled,
        'waitDays': waitDays,
        'allow': allow,
        'reason': reason,
      });

  Future<void> _void(String name, Map<String, Object?> data) async {
    await _call(name, data);
  }

  Future<Map<Object?, Object?>> _call(String name, Map<String, Object?> data) async {
    try {
      final r = await _fns.httpsCallable(name).call<Object?>(data);
      final d = r.data;
      return d is Map ? Map<Object?, Object?>.from(d) : const <Object?, Object?>{};
    } on FirebaseFunctionsException catch (e) {
      final det = e.details;
      final code = det is Map ? (det['code'] ?? '').toString() : '';
      throw AdminDeletionFailure(code.isEmpty ? e.code : code, e.message ?? '');
    }
  }
}
