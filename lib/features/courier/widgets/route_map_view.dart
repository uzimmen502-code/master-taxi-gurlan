import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../models/order_model.dart';
import '../../restaurants/courier/restaurant_courier_logic.dart';

/// Kuryer marshrutining Google Maps ko'rinishi:
/// joriy lokatsiya + buyurtma markerlari (rang index'ga qarab).
/// Restoran buyurtmasi (Б3): olguncha birinchi bekat — restoran (to'q sariq).
class RouteMapView extends StatelessWidget {
  const RouteMapView({
    super.key,
    required this.currentLat,
    required this.currentLng,
    required this.orders,
    required this.currentIndex,
    this.height = 220,
  });

  final double? currentLat;
  final double? currentLng;
  final List<OrderModel> orders;
  final int currentIndex;
  final double height;

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    for (var i = 0; i < orders.length; i++) {
      final o = orders[i];
      final isDone = i < currentIndex;
      final isCurrent = i == currentIndex;
      if (o.isRestaurant && o.hasRestaurantCoordinates && !isDone) {
        final stage = courierStageFor(o);
        if (stage == CourierRestaurantStage.preparing ||
            stage == CourierRestaurantStage.pickup) {
          markers.add(Marker(
            markerId: MarkerId('${o.id}_restaurant'),
            position: LatLng(o.restaurantLat!, o.restaurantLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isCurrent ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueYellow,
            ),
            infoWindow: InfoWindow(
              title: '${i + 1}. 🍽 ${o.restaurantName}',
              snippet: o.restaurantAddress,
            ),
          ));
        }
      }
      if (!o.hasCoordinates) continue;
      markers.add(Marker(
        markerId: MarkerId(o.id),
        position: LatLng(o.lat!, o.lng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isDone
              ? BitmapDescriptor.hueGreen
              : isCurrent
                  ? BitmapDescriptor.hueRed
                  : BitmapDescriptor.hueYellow,
        ),
        infoWindow: InfoWindow(
          title: '${i + 1}. ${o.userName}',
          snippet: o.address,
        ),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final hasGps = currentLat != null && currentLng != null;
    return SizedBox(
      height: height,
      child: !hasGps
          ? Container(
              color: Colors.grey.shade200,
              child: const Center(child: CircularProgressIndicator()),
            )
          : GoogleMap(
              initialCameraPosition: CameraPosition(
                  target: LatLng(currentLat!, currentLng!), zoom: 14),
              markers: _buildMarkers(),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
    );
  }
}
