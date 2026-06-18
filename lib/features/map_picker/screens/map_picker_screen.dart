import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';

/// Xaritada manzil tanlash ekrani.
///
/// `Navigator.pop(context, String)` orqali tanlangan manzilni qaytaradi.
/// State butunlay lokal bo'lgani uchun `ChangeNotifier` ishlatilmaydi —
/// `setState` yetarli.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, required this.title});

  final String title;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  /// Boshlang'ich xarita markazi (Gurlan, Xorazm).
  static const _initialCenter = LatLng(41.4957, 60.5822);

  /// Placeholder "so'nggi manzillar" — kelajakda foydalanuvchi tarixidan kelishi kerak.
  static const _recentAddresses = <_RecentPlace>[
    _RecentPlace(name: 'Гурлан маркази', lat: 41.4957, lng: 60.5822),
    _RecentPlace(name: 'Гурлан бозори', lat: 41.4980, lng: 60.5850),
    _RecentPlace(name: 'Гурлан МФЙ-1', lat: 41.4940, lng: 60.5800),
    _RecentPlace(name: 'Гурлан МФЙ-2', lat: 41.4920, lng: 60.5780),
  ];

  LatLng? _selectedLocation;
  String? _selectedAddress;
  bool _showRecentPlaces = false;

  void _toggleRecentPlaces() {
    setState(() => _showRecentPlaces = !_showRecentPlaces);
  }

  void _hideRecentPlaces() {
    if (_showRecentPlaces) {
      setState(() => _showRecentPlaces = false);
    }
  }

  void _onMapTap(LatLng latLng) {
    _hideRecentPlaces();
    setState(() {
      _selectedLocation = latLng;
      _selectedAddress =
          '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_selectedAddress != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _selectedAddress),
              child: const Text('Танлаш',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
        ],
      ),
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition:
              const CameraPosition(target: _initialCenter, zoom: 12),
          onMapCreated: (_) {},
          onTap: _onMapTap,
          onCameraMove: (_) => _hideRecentPlaces(),
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          markers: _selectedLocation != null
              ? {
                  Marker(
                      markerId: const MarkerId('selected'),
                      position: _selectedLocation!),
                }
              : const <Marker>{},
        ),
        if (_selectedAddress != null) _selectedAddressBanner(),
        if (!_showRecentPlaces) _recentPlacesButton(),
        if (_showRecentPlaces) _recentPlacesSheet(),
      ]),
      bottomNavigationBar: _selectedAddress != null ? _confirmButton() : null,
    );
  }

  // ─── Tanlangan manzil banner ───────────────────────────────────────
  Widget _selectedAddressBanner() {
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
        ),
        child: Row(children: [
          const Icon(Icons.location_on, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_selectedAddress!,
                style: const TextStyle(fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  // ─── "So'nggi manzillar" tugmasi ──────────────────────────────────
  Widget _recentPlacesButton() {
    return Positioned(
      bottom: 20,
      left: 16,
      child: GestureDetector(
        onTap: _toggleRecentPlaces,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 8),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.history, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'Сўнгги ${_recentAddresses.length} та',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ]),
        ),
      ),
    );
  }

  // ─── So'nggi manzillar paneli ──────────────────────────────────────
  Widget _recentPlacesSheet() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, -3)),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(children: [
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
              const Spacer(),
              const Text('Сўнгги манзиллар',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: _hideRecentPlaces,
              ),
            ]),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: _recentAddresses.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final place = _recentAddresses[index];
                return ListTile(
                  leading: const Icon(Icons.location_on,
                      color: Colors.red, size: 22),
                  title: Text(place.name,
                      style: const TextStyle(fontSize: 14)),
                  dense: true,
                  onTap: () => Navigator.pop(context, place.name),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ─── Tasdiqlash tugmasi ────────────────────────────────────────────
  Widget _confirmButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, _selectedAddress),
            icon: const Icon(Icons.check, size: 20),
            label: const Text('Тасдиқлаш',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.button,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }
}

/// "So'nggi manzillar" panelidagi bitta yozuv.
class _RecentPlace {
  const _RecentPlace({
    required this.name,
    required this.lat,
    required this.lng,
  });

  final String name;
  final double lat;
  final double lng;
}
