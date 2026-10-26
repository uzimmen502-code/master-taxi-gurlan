import 'package:cloud_firestore/cloud_firestore.dart';

/// «Хабарлар» табидаги ҳайдовчи аризаси ва «Админ билан чат» учун «яширилди» белгилари (эга, 2026-10-26:
/// «ўчириш тугмасини кирит»). Белги — `users/{uid}/dismissed_news/{ID}` ҳужжати (мавжуд механизм: rules фақат
/// `create` — `at == request.time`; серверда ҳеч нарса ўчирилмайди).
abstract final class InboxHideKeys {
  static const _driverPrefix = 'driver_req_';
  static const _chatPrefix = 'support_chat_cleared_';

  /// Ҳайдовчи аризаси картаси: калит ҳолат ва вақтга боғлиқ — ариза ҳолати ўзгарса (тасдиқ/рад) карта яна чиқади.
  /// Вақт йўқ бўлса 0 (`DateTime.now()` эмас — акс ҳолда калит ҳар чизишда ўзгарарди).
  static String driverRequest(Map<String, dynamic> data) {
    final status = (data['status'] ?? 'pending').toString();
    final at = (data['updatedAt'] as Timestamp?) ?? (data['createdAt'] as Timestamp?);
    return '$_driverPrefix${status}_${at?.millisecondsSinceEpoch ?? 0}';
  }

  /// «Админ билан чат» тарихини тозалаш белгиси. Қатор ЎЗИ қолади — у админга ёзишнинг ягона йўли.
  static String supportChatCleared(DateTime at) => '$_chatPrefix${at.millisecondsSinceEpoch}';

  /// Энг охирги тозалаш вақти (бир неча марта тозаланган бўлиши мумкин — ҳар бири алоҳида ҳужжат).
  static DateTime? supportChatClearedAt(Iterable<String> ids) {
    int? best;
    for (final id in ids) {
      if (!id.startsWith(_chatPrefix)) continue;
      final ms = int.tryParse(id.substring(_chatPrefix.length));
      if (ms != null && (best == null || ms > best)) best = ms;
    }
    return best == null ? null : DateTime.fromMillisecondsSinceEpoch(best);
  }

  /// Тозалашдан кейин келган хабарларгина кўринади. Вақти номаълум (ҳозиргина юборилган, сервер вақти кутилмоқда) — кўринади.
  static bool visibleAfterClear(DateTime? createdAt, DateTime? clearedAt) =>
      clearedAt == null || createdAt == null || createdAt.isAfter(clearedAt);
}
