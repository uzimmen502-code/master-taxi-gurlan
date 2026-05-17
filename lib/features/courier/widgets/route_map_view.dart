import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../models/order_model.dart';

/// Kuryer marshrutining Google Maps ko'rinishi:
/// joriy lokatsiya + buyurtma markerlari (rang index'ga qarab).
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
      if (!o.hasCoordinates) continue;
      final isDone = i < currentIndex;
      final isCurrent = i == currentIndex;
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
