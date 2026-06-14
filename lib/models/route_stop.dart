import 'order_model.dart';

/// Delivery route ichidagi bitta to'xtash nuqtasi.
class RouteStop {
  const RouteStop({
    required this.orderId,
    required this.sequence,
    required this.lat,
    required this.lng,
    this.userName = '',
    this.userPhone = '',
    this.address = '',
    this.total = 0,
    this.type = 'bread',
    this.estimatedArrivalMin,
  });

  final String orderId;
  final int sequence;
  final double lat;
  final double lng;
  final String userName;
  final String userPhone;
  final String address;
  final int total;
  final String type;
  final int? estimatedArrivalMin;

  factory RouteStop.fromMap(Map<String, dynamic> m) => RouteStop(
        orderId: (m['orderId'] ?? '') as String,
        sequence: (m['sequence'] as num?)?.toInt() ?? 0,
        lat: (m['lat'] as num?)?.toDouble() ?? 0,
        lng: (m['lng'] as num?)?.toDouble() ?? 0,
        userName: (m['userName'] ?? '') as String,
        userPhone: (m['userPhone'] ?? '') as String,
        address: (m['address'] ?? '') as String,
        total: (m['total'] as num?)?.toInt() ?? 0,
        type: (m['type'] ?? 'bread') as String,
        estimatedArrivalMin: (m['estimatedArrivalMin'] as num?)?.toInt(),
      );

  factory RouteStop.fromOrder(
    OrderModel order,
    int sequence, {
    double? lat,
    double? lng,
  }) =>
      RouteStop(
        orderId: order.id,
        sequence: sequence,
        lat: lat ?? order.lat ?? 0,
        lng: lng ?? order.lng ?? 0,
        userName: order.userName,
        userPhone: order.userPhone,
        address: order.address,
        total: order.total,
        type: order.type,
      );

  Map<String, dynamic> toMap() => {
        'orderId': orderId,
        'sequence': sequence,
        'lat': lat,
        'lng': lng,
        'userName': userName,
        'userPhone': userPhone,
        'address': address,
        'total': total,
        'type': type,
        if (estimatedArrivalMin != null)
          'estimatedArrivalMin': estimatedArrivalMin,
      };
}
