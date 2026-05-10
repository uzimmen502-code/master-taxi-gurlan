import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../services/price_service.dart';
import '../services/local_taxi_driver_request_listener.dart';
import 'driver_trip_map_screen.dart'; // 🔥 УЛАНДИ

class LocalTaxiDriverHomeScreen extends StatefulWidget {
  final String driverId;

  const LocalTaxiDriverHomeScreen({super.key, required this.driverId});

  @override
  State<LocalTaxiDriverHomeScreen> createState() =>
      _LocalTaxiDriverHomeScreenState();
}

class _LocalTaxiDriverHomeScreenState
    extends State<LocalTaxiDriverHomeScreen> {

  final listener = LocalTaxiDriverRequestListener();

  bool isOnline = false;

  double distanceKm = 0;
  Position? lastPos;
  StreamSubscription<Position>? positionStream;

  String? activeRequestId;

  @override
  void dispose() {
    positionStream?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────
  // ONLINE / OFFLINE
  // ─────────────────────────────────────
  void toggleOnline() {
    setState(() => isOnline = !isOnline);
  }

  // ─────────────────────────────────────
  // ACCEPT REQUEST
  // ─────────────────────────────────────
  Future<void> acceptRequest(String requestId) async {
    final doc = await FirebaseFirestore.instance
        .collection('ride_requests')
        .doc(requestId)
        .get();

    if (!doc.exists) return;

    final data = doc.data()!;
    if (data['status'] != 'searching') return;

    await FirebaseFirestore.instance
        .collection('ride_requests')
        .doc(requestId)
        .update({
      'status': 'accepted',
      'driverId': widget.driverId,
    });

    setState(() {
      activeRequestId = requestId;
    });
  }

  // ─────────────────────────────────────
  // START TRIP (🔥 УЛАНГАН)
  // ─────────────────────────────────────
  Future<void> startTrip() async {
    if (activeRequestId == null) return;

    await FirebaseFirestore.instance
        .collection('ride_requests')
        .doc(activeRequestId)
        .update({
      'status': 'on_trip',
      'startTime': FieldValue.serverTimestamp(),
    });

    // 🔥 МУҲИМ: карта экранига ўтиш
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DriverTripMapScreen(),
      ),
    );
  }

  // ─────────────────────────────────────
  // FINISH TRIP (fallback)
  // ─────────────────────────────────────
  Future<void> finishTrip() async {
    if (activeRequestId == null) return;

    final price = PriceService.calculate(distanceKm: distanceKm);

    await FirebaseFirestore.instance
        .collection('ride_requests')
        .doc(activeRequestId)
        .update({
      'status': 'finished',
      'distanceKm': distanceKm,
      'price': price,
      'endTime': FieldValue.serverTimestamp(),
    });

    positionStream?.cancel();

    setState(() {
      activeRequestId = null;
      distanceKm = 0;
      lastPos = null;
    });
  }

  // ─────────────────────────────────────
  // UI
  // ─────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ҳайдовчи панели'),
      ),
      body: Column(
        children: [

          // ONLINE
          SwitchListTile(
            title: const Text('Онлайн'),
            value: isOnline,
            onChanged: (_) => toggleOnline(),
          ),

          // ACTIVE REQUEST
          if (activeRequestId != null) ...[
            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: startTrip,
              child: const Text('Йўлга чиқдим'),
            ),

            ElevatedButton(
              onPressed: finishTrip,
              child: const Text('Етиб келдим (fallback)'),
            ),
          ],

          // REQUEST LIST
          if (isOnline && activeRequestId == null)
            Expanded(
              child: StreamBuilder(
                stream: listener.listenRequests(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data!.docs;

                  if (docs.isEmpty) {
                    return const Center(child: Text('Сўровлар йўқ'));
                  }

                  return ListView(
                    children: docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;

                      return Card(
                        child: ListTile(
                          title: Text(data['from'] ?? ''),
                          subtitle: Text(data['to'] ?? 'Бўш такси'),
                          trailing: ElevatedButton(
                            onPressed: () => acceptRequest(doc.id),
                            child: const Text('Қабул қилиш'),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}