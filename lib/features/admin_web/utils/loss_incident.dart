// Админ: йўқолган посилкалар (D1) — `adminListLossIncidents` жавобини
// ҳимояланган ўқиш (майдон йўқ/нотўғри тур бўлса ҳам йиқилмайди) ва
// сўм киритишни текшириш. ҲИСОБ-КИТОБ СЕРВЕРДА (`refundedNow`, `outstanding`
// тайёр келади); бу ерда фақат кўрсатиш (44-банд).

class LossIncident {
  const LossIncident({
    required this.id,
    required this.shipmentId,
    required this.status,
    required this.goodsValue,
    required this.refundedNow,
    required this.outstanding,
    this.declaredAtMs,
    this.courier = '',
    this.reason = '',
    this.trackingNumber = '',
  });

  final String id;
  final String shipmentId;

  /// `declared` | `settled` | `repaid` (номаълум қиймат — шундай кўрсатилади).
  final String status;

  /// Бутун сўм.
  final int goodsValue;
  final int refundedNow;
  final int outstanding;
  final int? declaredAtMs;

  /// Сервер маскалаган курьер белгиси.
  final String courier;
  final String reason;
  final String trackingNumber;

  /// Қарз қолган бўлса — «Тўлов ёзиш» таклиф қилинади (қоида — серверда).
  bool get canRecordPayment => outstanding > 0;

  DateTime? get declaredAt =>
      declaredAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(declaredAtMs!);

  static LossIncident fromMap(Map<String, dynamic> m) {
    int num0(Object? v) => v is num ? v.toInt() : 0;
    final shipmentId = (m['shipmentId'] ?? '').toString();
    final courier = m['courier'];
    var courierText = '';
    if (courier is String) {
      courierText = courier;
    } else if (courier is Map) {
      for (final k in const ['masked', 'phone', 'name', 'id']) {
        final v = courier[k];
        if (v is String && v.isNotEmpty) {
          courierText = v;
          break;
        }
      }
    }
    return LossIncident(
      id: (m['id'] ?? shipmentId).toString(),
      shipmentId: shipmentId,
      status: (m['status'] ?? '').toString(),
      goodsValue: num0(m['goodsValue']),
      refundedNow: num0(m['refundedNow']),
      outstanding: num0(m['outstanding']),
      declaredAtMs: m['declaredAtMs'] is num ? (m['declaredAtMs'] as num).toInt() : null,
      courier: courierText,
      reason: (m['reason'] ?? '').toString(),
      trackingNumber: (m['trackingNumber'] ?? '').toString(),
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
