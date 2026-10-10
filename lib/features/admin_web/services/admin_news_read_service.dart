import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Admin web — «Хабарлар» / «Буюртма хабар» қachon ochilgan (ўқилган).
class AdminNewsReadService extends ChangeNotifier {
  static const _kGeneralSeenMs = 'admin_news_general_seen_ms';
  static const _kOrderSeenMs = 'admin_news_order_seen_ms'; // эски (ms)
  static const _kOrderSeenUs = 'admin_news_order_seen_us';

  DateTime? _generalSeen;
  DateTime? _orderSeen;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  DateTime? get lastGeneralSeen => _generalSeen;
  DateTime? get lastOrderSeen => _orderSeen;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final g = prefs.getInt(_kGeneralSeenMs);
    final oUs = prefs.getInt(_kOrderSeenUs);
    final oMs = prefs.getInt(_kOrderSeenMs);
    _generalSeen = g != null ? DateTime.fromMillisecondsSinceEpoch(g) : null;
    _orderSeen = oUs != null
        ? DateTime.fromMicrosecondsSinceEpoch(oUs)
        : (oMs != null ? DateTime.fromMillisecondsSinceEpoch(oMs) : null);
    _loaded = true;
    notifyListeners();
  }

  Future<void> markGeneralSeen() async {
    final now = DateTime.now();
    _generalSeen = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGeneralSeenMs, now.millisecondsSinceEpoch);
    notifyListeners();
  }

  /// [newest] — экранда кўрилган энг янги хабарнинг СЕРВЕР вақти
  /// (`createdAt`). Админ компьютери соати сервердан орқада/олдинда бўлса
  /// `DateTime.now()` белгиси badge'ни нотўғри санарди. Белги фақат олдинга
  /// силжийди.
  Future<void> markOrderSeen(DateTime newest) async {
    final current = _orderSeen;
    if (current != null && !newest.isAfter(current)) return;
    _orderSeen = newest;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // Микросекунд: сервер вақти миллисекунддан аниқ — ms га қирқилса энг
    // янги хабар қайта «янги» саналарди.
    await prefs.setInt(_kOrderSeenUs, newest.microsecondsSinceEpoch);
  }
}
