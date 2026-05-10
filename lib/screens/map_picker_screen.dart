import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapPickerScreen extends StatefulWidget {
  final String title;

  const MapPickerScreen({super.key, required this.title});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  String? _selectedAddress;
  bool _showRecentPlaces = false;

  final List<Map<String, dynamic>> _recentAddresses = [
    {'name': 'Юнусобод-14', 'lat': 41.3111, 'lng': 69.2797},
    {'name': 'Чилонзор-19', 'lat': 41.3211, 'lng': 69.2697},
    {'name': 'Миробод-5', 'lat': 41.3011, 'lng': 69.2597},
    {'name': 'Сергели-8', 'lat': 41.2911, 'lng': 69.2497},
  ];

  void _toggleRecentPlaces() {
    setState(() {
      _showRecentPlaces = !_showRecentPlaces;
    });
  }

  void _hideRecentPlaces() {
    if (_showRecentPlaces) {
      setState(() => _showRecentPlaces = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (_selectedAddress != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _selectedAddress),
              child: const Text('Танлаш', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
      body: Stack(
        children: [
          // ============ ХАРИТА (тўлиқ экран) ============
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(41.3111, 69.2797),
              zoom: 12,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onTap: (latLng) {
              _hideRecentPlaces();
              setState(() {
                _selectedLocation = latLng;
                _selectedAddress = '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
              });
            },
            onCameraMove: (_) => _hideRecentPlaces(),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _selectedLocation != null
                ? {Marker(markerId: const MarkerId('selected'), position: _selectedLocation!)}
                : {},
          ),

          // ============ ТАНЛАНГАН МАНЗИЛ КЎРСАТКИЧИ ============
          if (_selectedAddress != null)
            Positioned(
              top: 12, left: 12, right: 12,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
                ),
                child: Row(children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_selectedAddress!, style: const TextStyle(fontSize: 13))),
                ]),
              ),
            ),

          // ============ СЎНГГИ МАНЗИЛЛАР ТУГМАЧАСИ ============
          if (!_showRecentPlaces)
            Positioned(
              bottom: 20, left: 16,
              child: GestureDetector(
                onTap: _toggleRecentPlaces,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history, size: 18, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        'Сўнгги ${_recentAddresses.length} та',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ============ СЎНГГИ МАНЗИЛЛАР РЎЙХАТИ ============
          if (_showRecentPlaces)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -3))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Тутқич + сарлавҳа
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                      child: Row(children: [
                        Container(width: 32, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                        const Spacer(),
                        const Text('Сўнгги манзиллар', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: _hideRecentPlaces,
                        ),
                      ]),
                    ),
                    // Рўйхат
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        itemCount: _recentAddresses.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final place = _recentAddresses[index];
                          return ListTile(
                            leading: const Icon(Icons.location_on, color: Colors.red, size: 22),
                            title: Text(place['name']!, style: const TextStyle(fontSize: 14)),
                            dense: true,
                            onTap: () {
                              Navigator.pop(context, place['name']!);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),

      // ============ ТАСДИҚЛАШ ТУГМАСИ ============
      bottomNavigationBar: _selectedAddress != null
          ? SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, _selectedAddress),
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Тасдиқлаш', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      )
          : null,
    );
  }
}