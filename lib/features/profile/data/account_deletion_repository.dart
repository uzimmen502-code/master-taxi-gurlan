import 'package:cloud_functions/cloud_functions.dart';

/// Ҳисобни ўчириш — сервер callable'лари (`functions/account_deletion.js`).
/// Ҳамма қарор серверда (дарвоза, блоклар, муддат); клиент фақат кўрсатади ва сўров юборади (44-банд).

class AccountDeletionBlocker {
  const AccountDeletionBlocker({required this.code, required this.area, this.count = 0});

  final String code;

  /// `orders | trips | courier | money | staff | other` — экранда оддий тилда тушунтирилади (45-банд).
  final String area;
  final int count;

  factory AccountDeletionBlocker.fromMap(Map<Object?, Object?> m) => AccountDeletionBlocker(
        code: (m['code'] ?? '').toString(),
        area: (m['area'] ?? 'other').toString(),
        count: (m['count'] as num?)?.toInt() ?? 0,
      );
}

class AccountDeletionPreview {
  const AccountDeletionPreview({
    required this.enabled,
    required this.waitDays,
    required this.exists,
    required this.blockers,
    required this.walletAmount,
    required this.paidServices,
    this.status,
    this.scheduledFor,
  });

  final bool enabled;
  final int waitDays;
  final bool exists;
  final List<AccountDeletionBlocker> blockers;
  final int walletAmount;

  /// `realty_pro | realty_unlocks | assistant_package`
  final List<String> paidServices;

  /// Жорий сўров ҳолати (`PENDING | POSTPONED | EXECUTING | ...`) ёки `null`.
  final String? status;
  final DateTime? scheduledFor;

  /// Бекор қилса бўладиган фаол сўров борми.
  bool get hasActiveRequest => status == 'PENDING' || status == 'POSTPONED' || status == 'EXECUTING';
  bool get canCancel => status == 'PENDING' || status == 'POSTPONED';

  factory AccountDeletionPreview.fromMap(Map<Object?, Object?> m) {
    final state = m['state'];
    String? status;
    DateTime? scheduled;
    if (state is Map) {
      status = state['status']?.toString();
      final ms = (state['scheduledForMs'] as num?)?.toInt();
      if (ms != null) scheduled = DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return AccountDeletionPreview(
      enabled: m['enabled'] == true,
      waitDays: (m['waitDays'] as num?)?.toInt() ?? 10,
      exists: m['exists'] != false,
      blockers: [
        for (final b in (m['blockers'] as List?) ?? const [])
          if (b is Map) AccountDeletionBlocker.fromMap(b),
      ],
      walletAmount: (m['walletAmount'] as num?)?.toInt() ?? 0,
      paidServices: [for (final s in (m['paidServices'] as List?) ?? const []) s.toString()],
      status: status,
      scheduledFor: scheduled,
    );
  }
}

/// Сервер рад этган ҳолат (`details.code`); экран шу кодга қараб матн танлайди, ичкарини кўрсатмайди (25-банд).
class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure(this.code, {this.blockers = const []});

  final String code;
  final List<AccountDeletionBlocker> blockers;

  @override
  String toString() => 'AccountDeletionFailure($code)';
}

class AccountDeletionRepository {
  AccountDeletionRepository({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  Future<AccountDeletionPreview> preview() async {
    final res = await _call('previewAccountDeletion');
    return AccountDeletionPreview.fromMap(res);
  }

  /// Сўров юборади; қайтаради: режалаштирилган сана.
  Future<DateTime?> request() async {
    final res = await _call('requestAccountDeletion');
    final ms = (res['scheduledForMs'] as num?)?.toInt();
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> cancel() async {
    await _call('cancelAccountDeletion');
  }

  Future<Map<Object?, Object?>> _call(String name) async {
    try {
      final r = await _fns.httpsCallable(name).call<Object?>(const <String, Object?>{});
      final d = r.data;
      return d is Map ? Map<Object?, Object?>.from(d) : const <Object?, Object?>{};
    } on FirebaseFunctionsException catch (e) {
      final det = e.details;
      final code = det is Map ? (det['code'] ?? '').toString() : '';
      final blockers = <AccountDeletionBlocker>[];
      if (det is Map && det['blockers'] is List) {
        for (final b in det['blockers'] as List) {
          if (b is Map) blockers.add(AccountDeletionBlocker.fromMap(Map<Object?, Object?>.from(b)));
        }
      }
      throw AccountDeletionFailure(code.isEmpty ? e.code : code, blockers: blockers);
    }
  }
}
