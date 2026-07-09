import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/map_picker_result.dart';
import '../../../models/saved_place.dart';
import '../../../services/location_service.dart';

/// Xaritada manzil tanlash ekrani.
///
/// `Navigator.pop(context, MapPickerResult)` orqali tanlangan nuqta qaytariladi.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({
    super.key,
    required this.title,
    this.recentPlaces = const [],
  });

  final String title;
  final List<SavedPlace> recentPlaces;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const _fallbackCenter = LatLng(41.2995, 69.2401);

  GoogleMapController? _mapController;
  LatLng? _mapCenter;
  LatLng? _selectedLocation;
  String? _selectedAddress;
  bool _showRecentPlaces = false;
  bool _loadingGps = true;
  String? _gpsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialCenter());
  }

  Future<void> _loadInitialCenter() async {
    try {
      final coords =
          await context.read<LocationService>().getFreshCoords();
      if (!mounted) return;
      final center = LatLng(coords.lat, coords.lng);
      setState(() {
        _mapCenter = center;
        _loadingGps = false;
      });
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(center, 14),
      );
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingGps = false;
        _gpsError = LocationException.userMessage(e.kind);
        _mapCenter = _fallbackCenter;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingGps = false;
        _gpsError = LocationException.userMessage(
          LocationErrorKind.lookupFailed,
        );
        _mapCenter = _fallbackCenter;
      });
    }
  }

  LatLng get _initialCenter => _mapCenter ?? _fallbackCenter;

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

  void _confirmSelection() {
    final loc = _selectedLocation;
    if (loc == null) return;
    Navigator.pop(
      context,
      MapPickerResult(
        lat: loc.latitude,
        lng: loc.longitude,
        label: _selectedAddress ?? '',
      ),
    );
  }

  void _pickRecent(SavedPlace place) {
    if (place.lat != null && place.lng != null) {
      Navigator.pop(
        context,
        MapPickerResult(
          lat: place.lat!,
          lng: place.lng!,
          label: place.address,
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      MapPickerResult(lat: 0, lng: 0, label: place.address),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_selectedLocation != null)
            TextButton(
              onPressed: _confirmSelection,
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
              CameraPosition(target: _initialCenter, zoom: 14),
          onMapCreated: (c) => _mapController = c,
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
        if (_loadingGps)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('GPS...'),
                  ],
                ),
              ),
            ),
          ),
        if (_gpsError != null)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              color: Colors.orange.shade800,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _gpsError!,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        if (_selectedAddress != null) _selectedAddressBanner(),
        if (!_showRecentPlaces && widget.recentPlaces.isNotEmpty)
          _recentPlacesButton(),
        if (_showRecentPlaces) _recentPlacesSheet(),
      ]),
      bottomNavigationBar: _selectedLocation != null ? _confirmButton() : null,
    );
  }

  Widget _selectedAddressBanner() {
    return Positioned(
      top: _gpsError != null ? 72 : 12,
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
              'Сақланган ${widget.recentPlaces.length}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ]),
        ),
      ),
    );
  }

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
              const Text('Сақланган манзиллар',
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
              itemCount: widget.recentPlaces.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final place = widget.recentPlaces[index];
                return ListTile(
                  leading: const Icon(Icons.location_on,
                      color: Colors.red, size: 22),
                  title: Text(place.name,
                      style: const TextStyle(fontSize: 14)),
                  subtitle: place.address.isNotEmpty
                      ? Text(place.address,
                          maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  dense: true,
                  onTap: () => _pickRecent(place),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _confirmButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _confirmSelection,
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
