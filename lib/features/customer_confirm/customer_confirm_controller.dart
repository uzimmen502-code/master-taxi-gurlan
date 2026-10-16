import 'package:flutter/foundation.dart';

import '../../models/customer_confirm.dart';
import '../../services/customer_confirm_service.dart';
import 'customer_confirm_gate.dart';

/// FCM `customer_confirm` келганда (илова очиқ) очиқ банер/экран рўйхатини
/// қайта юклаши учун сигнал. Қиймат аҳамиятсиз — ўзгариши керак.
abstract final class CustomerConfirmSignal {
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static void bump() => tick.value++;
}

/// «Тасдиқлаш кутилмоқда» рўйхати ҳолати. UI фақат кўрсатади ва тугма босади;
/// рухсат ва ҳолат — сервер (`getCustomerPendingConfirmations`,
/// `customerConfirmHandover`).
class CustomerConfirmController extends ChangeNotifier {
  /// [gate] берилса — рўйхат чақируви ФАҚАТ `module_config/customer_confirm`
  /// ёқиқ бўлганда қилинади (бош саҳифа блоки). Берилмаса — ҳар доим чақиради
  /// (тўлиқ экран: push босилган, хусусият ёқиқлиги маълум).
  CustomerConfirmController({
    CustomerConfirmService? service,
    CustomerConfirmGate? gate,
  })  : _service = service ?? CustomerConfirmService(),
        _gate = gate;

  final CustomerConfirmService _service;
  final CustomerConfirmGate? _gate;

  List<CustomerConfirmation> _items = const [];
  bool _loading = false;
  bool _loaded = false;
  Object? _loadError;
  DateTime? _lastLoadAt;
  bool _disposed = false;
  final Set<String> _busy = <String>{};

  List<CustomerConfirmation> get items => _items;
  bool get loading => _loading;

  /// Камида бир марта муваффақиятли юкланган.
  bool get loaded => _loaded;
  Object? get loadError => _loadError;
  bool isBusy(CustomerConfirmation c) => _busy.contains(c.key);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Рўйхатни юклайди. Хато бўлса эски рўйхат сақланади ([loadError] қўйилади):
  /// тармоқ узилиши тасдиқ кутаётган мижозни рўйхатсиз қолдирмасин.
  ///
  /// Gate берилган бўлса ва хусусият ўчиқ / ҳужжат йўқ / ўқиб бўлмаган бўлса —
  /// Cloud Function чақирилмайди, рўйхат бўш. [forceGate] — gate кешини
  /// четлаб қайта ўқийди (push келганда).
  Future<void> load({bool forceGate = false}) async {
    if (_loading) return;
    _loading = true;
    _notify();
    try {
      final gate = _gate;
      if (gate != null && !await gate.isEnabled(force: forceGate)) {
        _items = const [];
        _loadError = null;
        return;
      }
      _items = await _service.listPending();
      _loaded = true;
      _loadError = null;
    } catch (e) {
      _loadError = e;
    } finally {
      _loading = false;
      _lastLoadAt = DateTime.now();
      _notify();
    }
  }

  /// Тез-тез чақириладиган жойлар (қайтиш, push) учун: [minAge] ичида қайта юкламайди.
  Future<void> loadIfStale({Duration minAge = const Duration(seconds: 20)}) {
    final last = _lastLoadAt;
    if (last != null && DateTime.now().difference(last) < minAge) {
      return Future.value();
    }
    return load();
  }

  /// Тасдиқлайди. Муваффақият → `null`. Хато → мижозга кўрсатиладиган матн
  /// калити (`customer_confirm_err_*`). Бир элементга параллел босиш — иккинчиси
  /// рад (икки марта юборилмайди; сервер ҳам идемпотент).
  Future<String?> confirm(CustomerConfirmation c) async {
    if (_busy.contains(c.key)) return null;
    _busy.add(c.key);
    _notify();
    try {
      await _service.confirm(module: c.module, id: c.id, step: c.step);
      _items = [
        for (final i in _items)
          if (i.key != c.key) i,
      ];
      _notify();
      // Бошқа қадам пайдо бўлган бўлиши мумкин — сервер ҳақиқатини оламиз.
      await _refreshAfterChange();
      return null;
    } on CustomerConfirmException catch (e) {
      if (customerConfirmErrorNeedsRefresh(e.reason)) {
        await _refreshAfterChange();
      }
      return customerConfirmErrorKey(e.reason);
    } catch (_) {
      return customerConfirmErrorKey('');
    } finally {
      _busy.remove(c.key);
      _notify();
    }
  }

  Future<void> _refreshAfterChange() async {
    _loading = false; // кутилаётган юклаш бўлса ҳам янгидан олинади
    await load();
  }
}
