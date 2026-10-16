// Админ: йўқолган посилкалар (D1) — `adminListLossIncidents` жавобини
// ҳимояланган ўқиш (майдон йўқ/нотўғри тур бўлса ҳам йиқилмайди) ва
// сўм киритишни текшириш. ҲИСОБ-КИТОБ СЕРВЕРДА (`refundedNow`, `outstanding`
// тайёр келади); бу ерда фақат кўрсатиш (44-банд).

import '../../logistics/domain/logistics_models.dart' show logisticsMoney;

class LossIncident {
  const LossIncident({
    required this.id,
    required this.shipmentId,
    required this.status,
    this.goodsValue,
    this.refundedNow,
    this.outstanding,
    this.paidTotal,
    this.declaredAtMs,
    this.courierPhoneMasked = '',
    this.courierAccountId = '',
    this.reason = '',
    this.trackingNumber = '',
    this.legId = '',
  });

  final String id;
  final String shipmentId;

  /// `declared` | `settled` | `repaid` (номаълум қиймат — шундай кўрсатилади).
  final String status;

  /// Бутун сўм. `null` — сервер ҳали ҳисобламаган / бермаган (экран «-» кўрсатади,
  /// 0 деб ўйлаб топилмайди).
  final int? goodsValue;
  final int? refundedNow;
  final int? outstanding;

  /// Курьер аллақачон тўлаган жами (сервер `paidTotal`; бўлмаса `null`).
  final int? paidTotal;
  final int? declaredAtMs;

  /// Сервер маскалаган курьер телефони (`***1234`), `courierPhoneMasked`.
  final String courierPhoneMasked;
  final String courierAccountId;
  final String reason;
  final String trackingNumber;
  final String legId;

  /// Қарз қолган бўлса — «Тўлов ёзиш» таклиф қилинади (қоида — серверда).
  /// `outstanding == null` (ҳали ҳисобланмаган) — таклиф қилинмайди.
  bool get canRecordPayment => (outstanding ?? 0) > 0;

  DateTime? get declaredAt =>
      declaredAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(declaredAtMs!);

  /// `courierPhoneMasked` (янги сервер); йўқ бўлса эски шакл `courier`
  /// (матн ёки `{masked|phone|name|id}`) — орқага мослик.
  static String _courierText(Map<String, dynamic> m) {
    final masked = m['courierPhoneMasked'];
    if (masked is String && masked.isNotEmpty) return masked;
    final courier = m['courier'];
    if (courier is String) return courier;
    if (courier is Map) {
      for (final k in const ['masked', 'phone', 'name', 'id']) {
        final v = courier[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return '';
  }

  static LossIncident fromMap(Map<String, dynamic> m) {
    int? numOrNull(Object? v) => v is num ? v.toInt() : null;
    final shipmentId = (m['shipmentId'] ?? '').toString();
    return LossIncident(
      id: (m['id'] ?? shipmentId).toString(),
      shipmentId: shipmentId,
      status: (m['status'] ?? '').toString(),
      goodsValue: numOrNull(m['goodsValue']),
      refundedNow: numOrNull(m['refundedNow']),
      outstanding: numOrNull(m['outstanding']),
      paidTotal: numOrNull(m['paidTotal']),
      declaredAtMs: numOrNull(m['declaredAtMs']),
      courierPhoneMasked: _courierText(m),
      courierAccountId: (m['courierAccountId'] ?? '').toString(),
      reason: (m['reason'] ?? '').toString(),
      trackingNumber: (m['trackingNumber'] ?? '').toString(),
      legId: (m['legId'] ?? '').toString(),
    );
  }

  /// `items` рўйхати → моделлар (Map бўлмаган элементлар ташланади).
  static List<LossIncident> parseList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map) fromMap(e.map((k, v) => MapEntry(k.toString(), v))),
    ];
  }
}

/// Сўм кўрсатиш: `null` (ҳали ҳисобланмаган) → «-».
String lossMoneyText(int? v) => v == null ? '-' : logisticsMoney(v);
/// Ҳолат → админ матни.
String lossStatusLabel(String status) => switch (status) {
      'declared' => 'Эълон қилинган',
      'settled' => 'Мижозга ҳисобланган',
      'repaid' => 'Қарз ёпилган',
      _ => status.isEmpty ? '—' : status,
    };

/// Сўм киритиш: бўшлиқлар олиб ташланади; фақат рақамлар; мусбат бутун.
/// Нотўғри/0/манфий/ўнли — `null` (floating-point йўқ, 8-банд).
int? parsePositiveSom(String text) {
  final t = text.replaceAll(RegExp(r'[\s ]'), '');
  if (t.isEmpty || !RegExp(r'^\d{1,12}$').hasMatch(t)) return null;
  final v = int.parse(t);
  return v > 0 ? v : null;
}
