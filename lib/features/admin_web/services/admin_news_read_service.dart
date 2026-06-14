import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Admin web — «Хабарлар» / «Буюртма хабар» қachon ochilgan (ўқилган).
class AdminNewsReadService extends ChangeNotifier {
  static const _kGeneralSeenMs = 'admin_news_general_seen_ms';
  static const _kOrderSeenMs = 'admin_news_order_seen_ms';

  DateTime? _generalSeen;
  DateTime? _orderSeen;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  DateTime? get lastGeneralSeen => _generalSeen;
  DateTime? get lastOrderSeen => _orderSeen;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final g = prefs.getInt(_kGeneralSeenMs);
    final o = prefs.getInt(_kOrderSeenMs);
    _generalSeen = g != null ? DateTime.fromMillisecondsSinceEpoch(g) : null;
    _orderSeen = o != null ? DateTime.fromMillisecondsSinceEpoch(o) : null;
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

  Future<void> markOrderSeen() async {
    final now = DateTime.now();
    _orderSeen = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kOrderSeenMs, now.millisecondsSinceEpoch);
    notifyListeners();
  }
}
