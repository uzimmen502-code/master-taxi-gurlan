import 'dart:async';

import '../../models/agro_pickup_order.dart';
import '../../models/carpet_wash_order.dart';
import '../../models/order_model.dart';
import '../../repositories/agro_pickup_orders_repository.dart';
import '../../repositories/carpet_wash_orders_repository.dart';
import '../../repositories/orders_repository.dart';

enum CustomerOrderKind { food, carpet, milk }

/// Bitta ro'yxatda non/taom + gilam + sut buyurtmalari.
class CustomerOrderEntry {
  const CustomerOrderEntry._({
    required this.kind,
    required this.createdAt,
    required this.isActive,
    this.food,
    this.carpet,
    this.milk,
  });

  factory CustomerOrderEntry.food(OrderModel order) => CustomerOrderEntry._(
        kind: CustomerOrderKind.food,
        createdAt: order.createdAt,
        isActive: const {'new', 'accepted', 'ready', 'in_delivery'}
            .contains(order.status),
        food: order,
      );

  factory CustomerOrderEntry.carpet(CarpetWashOrder order) =>
      CustomerOrderEntry._(
        kind: CustomerOrderKind.carpet,
        createdAt: order.createdAt,
        isActive: order.isActive,
        carpet: order,
      );

  factory CustomerOrderEntry.milk(AgroPickupOrder order) => CustomerOrderEntry._(
        kind: CustomerOrderKind.milk,
        createdAt: order.createdAt,
        isActive: order.isActive,
        milk: order,
      );

  final CustomerOrderKind kind;
  final DateTime? createdAt;
  final bool isActive;
  final OrderModel? food;
  final CarpetWashOrder? carpet;
  final AgroPickupOrder? milk;
}

/// Uchta Firestore streamini birlashtiradi.
class CustomerOrdersHub {
  CustomerOrdersHub({
    required OrdersRepository orders,
    required CarpetWashOrdersRepository carpet,
    required AgroPickupOrdersRepository agro,
  })  : _orders = orders,
        _carpet = carpet,
        _agro = agro;

  final OrdersRepository _orders;
  final CarpetWashOrdersRepository _carpet;
  final AgroPickupOrdersRepository _agro;

  Stream<List<CustomerOrderEntry>> watchUnified({
    required List<String> phoneAliases,
    required String customerPhone,
  }) {
    final controller = StreamController<List<CustomerOrderEntry>>();
    var food = const <OrderModel>[];
    var carpets = const <CarpetWashOrder>[];
    var milks = const <AgroPickupOrder>[];

    void publish() {
      if (controller.isClosed) return;
      final entries = <CustomerOrderEntry>[
        ...food.map(CustomerOrderEntry.food),
        ...carpets.map(CustomerOrderEntry.carpet),
        ...milks.map(CustomerOrderEntry.milk),
      ]..sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
      controller.add(entries);
    }

    final subs = <StreamSubscription<dynamic>>[
      _orders.watchByUser(phoneAliases).listen((v) {
        food = v;
        publish();
      }),
      _carpet.watchForCustomer(customerPhone).listen((v) {
        carpets = v;
        publish();
      }),
      _agro.watchForCustomer(customerPhone).listen((v) {
        milks = v
            .where((o) => o.productType == AgroPickupOrder.productMilk)
            .toList(growable: false);
        publish();
      }),
    ];

    controller.onCancel = () {
      for (final s in subs) {
        unawaited(s.cancel());
      }
    };

    return controller.stream;
  }
}
