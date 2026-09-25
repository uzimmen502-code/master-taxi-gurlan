import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/active_trip.dart';
import '../../../models/intercity_booking.dart';
import '../../../repositories/intercity_bookings_repository.dart';
import '../../../repositories/rides_repository.dart';

/// Фаол буюртманинг кўринадиган ҳолати.
enum ActiveOrderStage {
  /// Ҳайдовчи қидирилмоқда.
  searching,

  /// Йўлда — ҳайдовчи топилди, келмоқда.
  onWay,

  /// Етиб келди (қаранг: `ActiveTrip.arrivedAt`).
  arrived,
}

/// Фаол буюртманинг тури — босилганда қайси экран очилишини аниқлайди.
enum ActiveOrderKind { localTaxi, marshrut, intercity }

/// Бош саҳифадаги карточка учун бир хилга келтирилган буюртма.
@immutable
class HomeActiveOrder {
  const HomeActiveOrder({
    required this.id,
    required this.kind,
    required this.stage,
    required this.title,
    required this.sortAt,
    this.subtitle = '',
    this.trip,
  });

  final String id;
  final ActiveOrderKind kind;
  final ActiveOrderStage stage;

  /// Йўналиш — «Гурлан → Урганч».
  final String title;
  final String subtitle;

  /// Саралаш вақти — «энг яқин вақтдагиси» биринчи бўлиши учун.
  final DateTime sortAt;

  /// Такси сафари (кузатиш экранига ўтиш учун); бронда `null`.
  final ActiveTrip? trip;

  /// Ҳозир кетаётган сафар режалаштирилган брондан устун туради.
  int get priority => kind == ActiveOrderKind.intercity ? 1 : 0;
}

/// Бош саҳифадаги фаол буюртмаларни реал вақтда кузатади.
///
/// Уч манба: `trips` (маҳаллий), `trips` (маршрут), `intercity_bookings`.
/// Ҳеч нарса топилмаса [orders] бўш — карточка бутунлай кўринмайди.
///
/// Эслатма: илгари бош саҳифа фаол буюртма топилса ДАРҲОЛ кузатиш
/// экранига ўтиб кетарди. Эга қарори бўйича у олиб ташланди — энди
/// фақат карточка кўринади, ўтиш фойдаланувчи босганда бўлади.
class ActiveOrdersController extends ChangeNotifier {
  ActiveOrdersController({
    required RidesRepository rides,
    IntercityBookingsRepository? intercity,
  })  : _rides = rides,
        _intercity = intercity ?? IntercityBookingsRepository();

  final RidesRepository _rides;
  final IntercityBookingsRepository _intercity;

  StreamSubscription<List<ActiveTrip>>? _localSub;
  StreamSubscription<List<ActiveTrip>>? _marshrutSub;
  StreamSubscription<List<IntercityBooking>>? _intercitySub;

  List<ActiveTrip> _local = const [];
  List<ActiveTrip> _marshrut = const [];
  List<IntercityBooking> _bookings = const [];

  bool _disposed = false;
  String _phone = '';

  /// Ҳали биринчи маълумот келмаган — карточка ўрнида скелет.
  bool _loading = false;
  bool get loading => _loading;

  List<HomeActiveOrder> _orders = const [];

  /// Энг яқин вақтдагиси биринчи.
  List<HomeActiveOrder> get orders => _orders;

  /// Карточкада кўрсатиладиган буюртма; йўқ бўлса `null`.
  HomeActiveOrder? get primary => _orders.isEmpty ? null : _orders.first;

  /// «+1» белгиси учун — қолганлари сони.
  int get extraCount => _orders.isEmpty ? 0 : _orders.length - 1;

  /// Телефон ўзгарса (кириш/чиқиш) — обуналар қайта уланади.
  void bind(String phone) {
    final p = phone.trim();
    if (p == _phone) return;
    _phone = p;
    _cancel();
    _local = const [];
    _marshrut = const [];
    _bookings = const [];
    if (p.isEmpty) {
      _loading = false;
      _recompute();
      return;
    }
    _loading = true;
    _notify();

    _localSub = _rides.watchActiveLocalTripsForUser(p).listen((v) {
      _local = v;
      _loading = false;
      _recompute();
    }, onError: (_) {
      _loading = false;
      _recompute();
    });

    _marshrutSub = _rides.watchActiveMarshrutTripsForUser(p).listen((v) {
      _marshrut = v;
      _loading = false;
      _recompute();
    }, onError: (_) {
      _loading = false;
      _recompute();
    });

    _intercitySub = _intercity.watchByUser(p).listen((v) {
      _bookings = v;
      _loading = false;
      _recompute();
    }, onError: (_) {
      _loading = false;
      _recompute();
    });
  }

  static ActiveOrderStage _stageOf(ActiveTrip t) {
    if (t.status == 'searching' || t.status == 'pending') {
      return ActiveOrderStage.searching;
    }
    return t.hasArrived ? ActiveOrderStage.arrived : ActiveOrderStage.onWay;
  }

  static String _route(String from, String to) {
    final f = from.trim();
    final s = to.trim();
    if (f.isEmpty && s.isEmpty) return '';
    if (s.isEmpty) return f;
    if (f.isEmpty) return s;
    return '$f → $s';
  }

  void _recompute() {
    final out = <HomeActiveOrder>[];

    for (final t in _local) {
      out.add(HomeActiveOrder(
        id: t.id,
        kind: ActiveOrderKind.localTaxi,
        stage: _stageOf(t),
        title: _route(t.fromAddr, t.toAddr),
        sortAt: t.createdAt ?? DateTime.now(),
        trip: t,
      ));
    }
    for (final t in _marshrut) {
      out.add(HomeActiveOrder(
        id: t.id,
        kind: ActiveOrderKind.marshrut,
        stage: _stageOf(t),
        title: _route(
          t.pickupMfy.isNotEmpty ? t.pickupMfy : t.fromAddr,
          t.dropoffMfy.isNotEmpty ? t.dropoffMfy : t.toAddr,
        ),
        sortAt: t.createdAt ?? DateTime.now(),
        trip: t,
      ));
    }
    for (final b in _bookings) {
      // Моделнинг ўз рўйхати — статуслар иккита жойда такрорланмасин.
      if (!IntercityBookingStatus.active.contains(b.status)) continue;
      out.add(HomeActiveOrder(
        id: b.id,
        kind: ActiveOrderKind.intercity,
        stage: ActiveOrderStage.onWay,
        title: _route(b.fromCity, b.toCity),
        sortAt: b.createdAt,
      ));
    }

    out.sort((a, b) {
      final byPriority = a.priority.compareTo(b.priority);
      if (byPriority != 0) return byPriority;
      // Энг яқин вақтдагиси — яъни энг янги ҳаракат.
      return b.sortAt.compareTo(a.sortAt);
    });

    _orders = List.unmodifiable(out);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _cancel() {
    _localSub?.cancel();
    _marshrutSub?.cancel();
    _intercitySub?.cancel();
    _localSub = null;
    _marshrutSub = null;
    _intercitySub = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    super.dispose();
  }
}
