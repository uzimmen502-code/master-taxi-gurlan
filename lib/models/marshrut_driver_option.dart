import 'schedule.dart';
import 'queue_entry.dart';

/// Marshrut taksi tanlashda yo'lovchiga ko'rsatiladigan haydovchi varianti.
///
/// `MarshrutTaxiScreen` `schedules` collection'idan haydovchilarni ro'yxat
/// qiladi, har biri shu modelga aylantiriladi va waiting screen'ga uzatiladi.
class MarshrutDriverOption {
  const MarshrutDriverOption({
    required this.scheduleId,
    required this.driverId,
    this.driverName = '',
    this.driverPhone = '',
    this.car = '',
    this.plate = '',
    this.price = 0,
    this.lat,
    this.lng,
  });

  final String scheduleId;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String car;
  final String plate;
  final int price;
  final double? lat;
  final double? lng;

  /// Schedule'dan tipli option yaratish (qidiruv → waiting flow).
  factory MarshrutDriverOption.fromSchedule(Schedule s) {
    return MarshrutDriverOption(
      scheduleId: s.id,
      driverId: s.driverId.isNotEmpty ? s.driverId : s.id,
      driverName: s.driverName.isNotEmpty ? s.driverName : 'Ҳайдовчи',
      driverPhone: s.driverPhone,
      car: s.car,
      plate: s.plate,
      price: s.price,
      lat: s.lat,
      lng: s.lng,
    );
  }

  factory MarshrutDriverOption.fromQueueEntry(QueueEntry q) {
    return MarshrutDriverOption(
      scheduleId: q.scheduleId,
      driverId: q.driverId,
      driverName: q.driverName.isNotEmpty ? q.driverName : 'Ҳайдовчи',
      driverPhone: q.driverPhone,
      car: q.car,
      plate: q.plate,
      price: q.price,
      lat: q.lat,
      lng: q.lng,
    );
  }
}
