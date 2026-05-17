import 'driver_model.dart';

/// Haydovchi + yo'lovchidan masofa (km).
class NearbyDriver {
  const NearbyDriver({required this.driver, required this.distanceKm});

  final DriverModel driver;
  final double distanceKm;
}
