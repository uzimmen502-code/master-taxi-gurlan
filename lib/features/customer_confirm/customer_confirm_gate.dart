import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Мижоз тасдиғи хусусияти ёқиқми — харажат назорати.
///
/// Сервер `module_config/customer_confirm` = `{enabled: bool}` ҳужжатини
/// юритади (хусусият ҳеч бўлмаса битта модулда ёқилса `true`; ҳужжат йўқ = ўчиқ).
/// Бош саҳифа блоки `getCustomerPendingConfirmations`ни ФАҚАТ шу ҳужжат
/// `enabled == true` бўлганда чақиради; ҳужжат йўқ / `false` → чақирув
/// қилинмайди (ҳар мижозга ҳар очилишда Cloud Function чақирувини тежаймиз).
/// ЎҚИБ БЎЛМАСА (тармоқ, вақт) — чақирув ҚИЛИНАДИ ("очиқ" ҳолат): мижоз
/// ҳақиқатан тасдиқ кутаётган бўлса, тасодифий ўқиш хатоси уни яшириб
/// қўймасин. Қоида — серверда; бу фақат клиент томонидаги тежам.
class CustomerConfirmGate {
  CustomerConfirmGate({
    Future<bool> Function()? reader,
    this.ttl = const Duration(minutes: 10),
    this.falseTtl = const Duration(minutes: 1),
    DateTime Function()? now,
  })  : _reader = reader ?? _readFirestore,
        _now = now ?? DateTime.now;

  /// Иловадаги умумий нусха (сессия давомида кеш битта).
  static final CustomerConfirmGate instance = CustomerConfirmGate();

  static const String collection = 'module_config';
  static const String docId = 'customer_confirm';

  final Future<bool> Function() _reader;
  /// `true` натижа кеши (хусусият ёқилган — барқарор).
  final Duration ttl;

  /// `false` (ўчиқ/ҳужжат йўқ) натижа кеши — қисқа: админ ёқса, пушсиз ҳам
  /// мижоз тез кўради.
  final Duration falseTtl;
  final DateTime Function() _now;

  bool? _cached;
  DateTime? _cachedAt;
  Future<bool>? _inflight;

  /// Ҳужжатдан `enabled`ни ўқийди (ҳужжат йўқ → `false`). Хато → ташлайди.
  static Future<bool> _readFirestore() async {
    final snap = await FirebaseFirestore.instance
        .collection(collection)
        .doc(docId)
        .get()
        .timeout(const Duration(seconds: 8));
    return parseEnabled(snap.exists ? snap.data() : null);
  }

  /// `{enabled: true}` бўлсагина `true` (қатъий булев; "true"/1 — рад).
  @visibleForTesting
  static bool parseEnabled(Map<String, dynamic>? data) =>
      data != null && data['enabled'] == true;

  /// Хусусият ёқиқми. Муваффақиятли ўқиш кешланади: `true` — [ttl], `false` —
  /// [falseTtl] (параллел чақирувлар битта ўқишга бирлашади). Ўқиш хатоси
  /// кешланмайди ва `true` қайтаради — «билмасак, мижозни яширмаймиз» (сервер
  /// ўчиқ бўлса бўш рўйхат қайтаради). [force] — кешни четлаб қайта ўқийди
  /// (push келганда: ҳолат ўзгарган бўлиши мумкин).
  Future<bool> isEnabled({bool force = false}) {
    if (!force) {
      final at = _cachedAt;
      final c = _cached;
      if (c != null && at != null && _now().difference(at) < (c ? ttl : falseTtl)) {
        return Future.value(c);
      }
      final inflight = _inflight;
      if (inflight != null) return inflight;
    }
    final f = _fetch();
    _inflight = f;
    f.whenComplete(() {
      if (identical(_inflight, f)) _inflight = null;
    });
    return f;
  }

  Future<bool> _fetch() async {
    try {
      final v = await _reader();
      _cached = v;
      _cachedAt = _now();
      return v;
    } catch (e) {
      debugPrint('CustomerConfirmGate: o\'qib bo\'lmadi ($e) — ochiq holat, chaqiriladi');
      return true;
    }
  }
}