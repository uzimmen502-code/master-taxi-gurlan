import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/route_candidate.dart';
import '../../../models/route_stop.dart';
import '../../../models/trip_request.dart';
import '../../../services/google_directions_service.dart';
import '../../../services/location_service.dart';
import '../../../services/polyline_decoder.dart';
import '../../../utils/fare_calculator.dart';
import '../controllers/driver_home_controller.dart';
import '../services/driver_offer_sounds.dart';
import 'active_ride_card.dart';
import 'main_action_buttons.dart';

/// Haydovchi bitta xarita ekrani — kutish / chaqiruvlar / safar rejimlari.
class DriverUnifiedMapView extends StatefulWidget {
  const DriverUnifiedMapView({
    super.key,
    required this.onStartWork,
    required this.onEndWork,
    required this.onCompleteNonLocalRide,
    required this.onFinishLocalTrip,
    required this.onAbandonLocalTrip,
    required this.onSnack,
  });

  final Future<void> Function() onStartWork;
  final Future<void> Function() onEndWork;
  final Future<void> Function() onCompleteNonLocalRide;
  final Future<void> Function(int fare) onFinishLocalTrip;
  final Future<void> Function() onAbandonLocalTrip;
  final void Function(String msg, Color color) onSnack;

  @override
  State<DriverUnifiedMapView> createState() => _DriverUnifiedMapViewState();
}

enum _TripPhase { pick, navigating }

class _DriverUnifiedMapViewState extends State<DriverUnifiedMapView>
    with SingleTickerProviderStateMixin {
  static const _green = AppColors.primaryDark;
  /// Mahalliy taksi max qidiruv radiusi — yo'lovchi bilan bir xil.
  static const _onlineSearchRadiusKm = 7.0;
  static const _onlineCameraPadding = 48.0;

  final _mapController = Completer<GoogleMapController>();
  final _directionsService = GoogleDirectionsService();
  final _polylineDecoder = const PolylineDecoder();
  final _locationService = const LocationService();
  late final AnimationController _pulseController;

  String? _selectedOfferId;
  final Map<String, DateTime> _offerFirstSeen = {};
  final Set<String> _knownOfferIds = {};
  String? _lastPulsedOfferId;

  // Safar holati (local trip).
  _TripPhase _tripPhase = _TripPhase.pick;
  LatLng? _tripOrigin;
  LatLng? _destination;
  final Set<Polyline> _tripPolylines = {};
  double? _routeKm;
  bool _calculating = false;
  String? _calcError;
  StreamSubscription<Position>? _tripPosSub;
  LatLng? _lastTripPos;
  double _drivenKm = 0;
  int _liveFare = 0;
  bool _arrived = false;
  bool _finishing = false;
  bool _prefillingDestination = false;
  double? _distToPassengerM;

  /// Har safar onlayn bo'lganda (2-B) bir marta 7 km kadrga sig'dirish.
  bool _wasOnline = false;
  bool _pendingOnlineCameraFit = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tripPosSub?.cancel();
    super.dispose();
  }

  void _syncPulseAnimation(bool showOffers) {
    if (showOffers) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  String _fmt(String key, Map<String, String> vars) {
    var text = context.tr(key);
    vars.forEach((k, v) => text = text.replaceAll('{$k}', v));
    return text;
  }

  LatLngBounds _boundsForRadius(LatLng center, double radiusKm) {
    const kmPerDegLat = 111.0;
    final kmPerDegLng = 111.0 *
        math.cos(center.latitude * math.pi / 180).abs().clamp(0.01, 1.0);
    final dLat = radiusKm / kmPerDegLat;
    final dLng = radiusKm / kmPerDegLng;
    return LatLngBounds(
      southwest: LatLng(center.latitude - dLat, center.longitude - dLng),
      northeast: LatLng(center.latitude + dLat, center.longitude + dLng),
    );
  }

  Future<void> _fitCameraToOnlineRadius(LatLng center) async {
    if (!_mapController.isCompleted) return;
    try {
      final ctrl = await _mapController.future;
      final bounds = _boundsForRadius(center, _onlineSearchRadiusKm);
      await ctrl.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, _onlineCameraPadding),
      );
    } catch (_) {}
  }

  /// Onlayn bo'lganda GPS kelguncha kutadi (3-A), keyin markaz + 7 km kadr.
  void _syncOnlineCamera(DriverHomeController c) {
    final inLocalTrip = c.isLocalAcceptedRide && c.acceptedRide != null;

    if (!c.isOnline) {
      _wasOnline = false;
      _pendingOnlineCameraFit = false;
      return;
    }

    if (!_wasOnline) {
      _wasOnline = true;
      _pendingOnlineCameraFit = true;
    }

    if (!_pendingOnlineCameraFit || inLocalTrip || c.isBusy) return;

    final lat = c.driverLat;
    final lng = c.driverLng;
    if (lat == null || lng == null) return;

    _pendingOnlineCameraFit = false;
    unawaited(_fitCameraToOnlineRadius(LatLng(lat, lng)));
  }

  Set<Circle> _buildCircles(DriverHomeController c) {
    final circles = <Circle>{};
    final inLocalTrip = c.isLocalAcceptedRide && c.acceptedRide != null;

    if (c.isOnline && !c.isBusy && !inLocalTrip) {
      final lat = c.driverLat;
      final lng = c.driverLng;
      if (lat != null && lng != null) {
        circles.add(Circle(
          circleId: const CircleId('online_search_radius'),
          center: LatLng(lat, lng),
          radius: _onlineSearchRadiusKm * 1000,
          fillColor: AppColors.primary.withValues(alpha: 0.08),
          strokeColor: AppColors.primary.withValues(alpha: 0.45),
          strokeWidth: 2,
        ));
      }
    }

    if (c.isOnline && !c.isBusy && c.activeRequests.isNotEmpty) {
      final nearest = c.nearestRequest;
      if (nearest != null &&
          !(nearest.fromLat == 0 && nearest.fromLng == 0)) {
        final t = _pulseController.value;
        circles.add(Circle(
          circleId: const CircleId('offer_pulse'),
          center: LatLng(nearest.fromLat, nearest.fromLng),
          radius: 35 + t * 50,
          fillColor: AppColors.primary.withValues(alpha: 0.1 + t * 0.1),
          strokeColor: AppColors.primary.withValues(alpha: 0.45 + t * 0.35),
          strokeWidth: 2,
        ));
      }
    }

    return circles;
  }

  void _syncOffers(List<TripRequest> offers) {
    final ids = offers.map((o) => o.id).toSet();
    for (final id in ids) {
      _offerFirstSeen.putIfAbsent(id, () => DateTime.now());
    }
    _knownOfferIds.removeWhere((id) => !ids.contains(id));
    _offerFirstSeen.removeWhere((id, _) => !ids.contains(id));

    final nearest = offers.isNotEmpty ? offers.first.id : null;
    if (nearest != null &&
        !_knownOfferIds.contains(nearest) &&
        nearest != _lastPulsedOfferId) {
      _knownOfferIds.add(nearest);
      _lastPulsedOfferId = nearest;
      unawaited(DriverOfferSounds.playNewOffer());
    }

    if (_selectedOfferId != null && !ids.contains(_selectedOfferId)) {
      _selectedOfferId = nearest;
      setState(() {});
    } else if (_selectedOfferId == null && nearest != null) {
      _selectedOfferId = nearest;
      setState(() {});
    }
  }

  TripRequest? _selectedOffer(DriverHomeController c) {
    if (_selectedOfferId == null) return c.nearestRequest;
    for (final r in c.activeRequests) {
      if (r.id == _selectedOfferId) return r;
    }
    return c.nearestRequest;
  }

  bool _isStaleOffer(String id) {
    final seen = _offerFirstSeen[id];
    if (seen == null) return false;
    return DateTime.now().difference(seen) > const Duration(seconds: 30);
  }

  LatLng? _cameraTarget(DriverHomeController c) {
    if (c.driverLat != null && c.driverLng != null) {
      return LatLng(c.driverLat!, c.driverLng!);
    }
    if (c.isLocalAcceptedRide && c.acceptedRide != null) {
      final r = c.acceptedRide!;
      if (r.fromLat != 0 && r.fromLng != 0) {
        return LatLng(r.fromLat, r.fromLng);
      }
    }
    return null;
  }

  LatLng _cameraTargetOrWorld(DriverHomeController c) =>
      _cameraTarget(c) ?? const LatLng(41.2995, 69.2401);

  void _ensureTripOrigin(TripRequest ride) {
    if (ride.fromLat != 0 || ride.fromLng != 0) {
      _tripOrigin ??= LatLng(ride.fromLat, ride.fromLng);
    }
  }

  Future<void> _prefillDestination(TripRequest ride) async {
    final to = ride.to.trim();
    if (to.isEmpty || _destination != null) return;
    setState(() => _prefillingDestination = true);
    try {
      final coords = await _locationService.coordsFromAddress(
        to,
        regionBias: 'uzbekistan',
      );
      if (!mounted || coords == null) return;
      setState(() {
        _destination = LatLng(coords.lat, coords.lng);
        _prefillingDestination = false;
      });
      await _calculateRoute();
    } catch (_) {
      if (mounted) setState(() => _prefillingDestination = false);
    }
  }

  void _resetTripState() {
    _tripPosSub?.cancel();
    _tripPosSub = null;
    _tripPhase = _TripPhase.pick;
    _tripOrigin = null;
    _destination = null;
    _tripPolylines.clear();
    _routeKm = null;
    _calculating = false;
    _calcError = null;
    _lastTripPos = null;
    _drivenKm = 0;
    _liveFare = 0;
    _arrived = false;
    _finishing = false;
    _prefillingDestination = false;
    _distToPassengerM = null;
  }

  Future<void> _onMapTap(LatLng latLng) async {
    final c = context.read<DriverHomeController>();
    if (!c.isLocalAcceptedRide) return;
    if (_tripPhase != _TripPhase.pick) return;
    setState(() {
      _destination = latLng;
      _tripPolylines.clear();
      _routeKm = null;
      _calcError = null;
    });
    await _calculateRoute();
  }

  Future<void> _calculateRoute() async {
    final dest = _destination;
    final origin = _tripOrigin;
    if (dest == null || origin == null) return;
    setState(() {
      _calculating = true;
      _calcError = null;
    });
    try {
      final candidate = RouteCandidate(
        id: 'trip',
        startLat: origin.latitude,
        startLng: origin.longitude,
        directionLabel: '',
        directionDegrees: 0,
        distanceKm: 0,
        durationMin: 0,
        stops: [
          RouteStop(
            orderId: 'dest',
            sequence: 0,
            lat: dest.latitude,
            lng: dest.longitude,
          ),
        ],
      );
      final result = await _directionsService.fetchDirections(candidate);
      if (!mounted) return;
      final points = _polylineDecoder.decode(result.polyline);
      setState(() {
        _routeKm = result.distanceKm;
        _tripPolylines
          ..clear()
          ..add(Polyline(
            polylineId: const PolylineId('route'),
            points: points,
            color: _green,
            width: 5,
          ));
        _calculating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _calculating = false;
        _calcError = context.tr('driver_map_route_calc_failed');
      });
    }
  }

  Future<void> _startNavigation() async {
    if (_routeKm == null) return;
    setState(() {
      _tripPhase = _TripPhase.navigating;
      _drivenKm = 0;
      _lastTripPos = null;
      _arrived = false;
      _liveFare = FareCalculator.calculate(distanceKm: 0);
    });
    _tripPosSub?.cancel();
    _tripPosSub = null;
    _startTripTracking();
  }

  void _startPickupTracking() {
    _tripPosSub?.cancel();
    _tripPosSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(_onPickupPosition);
  }

  void _startTripTracking() {
    _tripPosSub?.cancel();
    _tripPosSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onTripPosition);
  }

  void _onPickupPosition(Position p) {
    final origin = _tripOrigin;
    if (origin == null) return;
    final distM = Geolocator.distanceBetween(
      p.latitude,
      p.longitude,
      origin.latitude,
      origin.longitude,
    );
    if (!mounted) return;
    setState(() => _distToPassengerM = distM);
  }

  void _onTripPosition(Position p) {
    final cur = LatLng(p.latitude, p.longitude);
    if (_lastTripPos != null) {
      final d = Geolocator.distanceBetween(
            _lastTripPos!.latitude,
            _lastTripPos!.longitude,
            cur.latitude,
            cur.longitude,
          ) /
          1000;
      if (d.isFinite && d > 0) _drivenKm += d;
    }
    _lastTripPos = cur;

    final origin = _tripOrigin;
    double? distToPassengerM;
    if (origin != null) {
      distToPassengerM = Geolocator.distanceBetween(
        cur.latitude,
        cur.longitude,
        origin.latitude,
        origin.longitude,
      );
    }

    final dest = _destination;
    double? distToDestM;
    if (dest != null) {
      distToDestM = Geolocator.distanceBetween(
        cur.latitude,
        cur.longitude,
        dest.latitude,
        dest.longitude,
      );
    }
    final remaining =
        _routeKm == null ? 0.0 : (_routeKm! - _drivenKm).clamp(0.0, _routeKm!);
    final arrived =
        (distToDestM != null && distToDestM <= 60) || remaining <= 0.15;

    if (!mounted) return;
    setState(() {
      _distToPassengerM = distToPassengerM;
      _liveFare = FareCalculator.calculate(distanceKm: _drivenKm);
      _arrived = arrived;
    });
  }

  Set<Marker> _buildMarkers(DriverHomeController c) {
    final markers = <Marker>{};

    if (c.isLocalAcceptedRide && c.acceptedRide != null) {
      final ride = c.acceptedRide!;
      _ensureTripOrigin(ride);
      if (_tripOrigin != null) {
        markers.add(Marker(
          markerId: const MarkerId('passenger'),
          position: _tripOrigin!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: context.tr('driver_map_passenger_marker')),
        ));
      }
      if (_destination != null) {
        markers.add(Marker(
          markerId: const MarkerId('destination'),
          position: _destination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow:
              InfoWindow(title: context.tr('driver_map_destination_marker')),
        ));
      }
      return markers;
    }

    if (c.isOnline && !c.isBusy) {
      for (var i = 0; i < c.activeRequests.length; i++) {
        final r = c.activeRequests[i];
        if (r.fromLat == 0 && r.fromLng == 0) continue;
        final isNearest = i == 0;
        final isSelected = r.id == _selectedOfferId;
        final stale = _isStaleOffer(r.id);
        final highlight = isNearest || isSelected;
        markers.add(Marker(
          markerId: MarkerId('offer_${r.id}'),
          position: LatLng(r.fromLat, r.fromLng),
          alpha: highlight ? 1.0 : (stale ? 0.55 : 0.75),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            highlight
                ? BitmapDescriptor.hueAzure
                : BitmapDescriptor.hueOrange,
          ),
          zIndexInt: highlight ? 2 : 1,
          onTap: () => setState(() => _selectedOfferId = r.id),
          infoWindow: InfoWindow(
            title: highlight
                ? '⭐ ${context.tr('driver_map_nearest_offer')}'
                : context.tr('driver_map_offer'),
            snippet: r.from,
          ),
        ));
      }
    }
    return markers;
  }

  Future<void> _acceptOffer(TripRequest ride) async {
    final c = context.read<DriverHomeController>();
    final result = await c.acceptRide(ride);
    if (!mounted) return;
    if (!result.success) {
      if (result.error != null) widget.onSnack(result.error!, Colors.orange);
      return;
    }
    _resetTripState();
    _ensureTripOrigin(ride);
    unawaited(_prefillDestination(ride));
    setState(() {});
  }

  Future<void> _finishTrip() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await widget.onFinishLocalTrip(_liveFare);
      if (!mounted) return;
      _resetTripState();
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _confirmAbandon() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('driver_map_leave_trip_title')),
        content: Text(context.tr('driver_map_leave_trip_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('no')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('driver_map_yes_leave'),
                style: const TextStyle(color: Color(0xFFB71C1C))),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    await widget.onAbandonLocalTrip();
    _resetTripState();
    setState(() {});
  }

  bool _showPhonePanel(TripRequest ride) {
    final nearPassenger =
        _distToPassengerM != null && _distToPassengerM! <= 120;
    return nearPassenger || _arrived;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverHomeController>();

    if (!c.isLocalAcceptedRide && _tripOrigin != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _resetTripState();
          setState(() {});
        }
      });
    } else if (c.isLocalAcceptedRide && c.acceptedRide != null) {
      final ride = c.acceptedRide!;
      _ensureTripOrigin(ride);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_tripPosSub == null) _startPickupTracking();
        if (!_prefillingDestination &&
            _destination == null &&
            ride.to.trim().isNotEmpty) {
          unawaited(_prefillDestination(ride));
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (c.isOnline && !c.isBusy) {
        _syncOffers(c.activeRequests);
      }
      _syncOnlineCamera(c);
    });

    final inLocalTrip = c.isLocalAcceptedRide && c.acceptedRide != null;
    final showOffers = c.isOnline && !c.isBusy && c.activeRequests.isNotEmpty;
    final selected = showOffers ? _selectedOffer(c) : null;
    _syncPulseAnimation(showOffers);

    return PopScope(
      canPop: !inLocalTrip,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !inLocalTrip) return;
        await _confirmAbandon();
      },
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) => GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: _cameraTargetOrWorld(c), zoom: 14),
              markers: _buildMarkers(c),
              circles: _buildCircles(c),
              polylines: inLocalTrip ? _tripPolylines : const {},
              myLocationEnabled: c.isOnline,
              myLocationButtonEnabled: c.isOnline,
              onMapCreated: (controller) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _syncOnlineCamera(context.read<DriverHomeController>());
                });
              },
              onTap: _onMapTap,
            ),
          ),

          // Yuqori holat paneli
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!c.hasInternet) _internetBanner(),
                    if (c.isBusy &&
                        c.acceptedRide != null &&
                        !c.isLocalAcceptedRide)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ActiveRideCard(
                          ride: c.acceptedRide!,
                          onComplete: widget.onCompleteNonLocalRide,
                        ),
                      ),
                    if (!inLocalTrip && c.isOnline && !showOffers)
                      _statusChip(
                        icon: Icons.hourglass_top,
                        label: context.tr('driver_map_waiting_passenger'),
                        color: _green,
                      ),
                    if (showOffers)
                      _statusChip(
                        icon: Icons.notifications_active,
                        label: _fmt('driver_map_offers_count', {
                          'n': '${c.activeRequests.length}',
                        }),
                        color: AppColors.primary,
                      ),
                    if (inLocalTrip)
                      _statusChip(
                        icon: _tripPhase == _TripPhase.navigating
                            ? (_arrived
                                ? Icons.flag
                                : Icons.navigation)
                            : Icons.edit_location_alt,
                        label: _tripPhase == _TripPhase.navigating
                            ? (_arrived
                                ? context.tr('driver_map_trip_arrived')
                                : context.tr('driver_map_trip_navigating'))
                            : context.tr('driver_map_pick_destination'),
                        color: _green,
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Pastki panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (inLocalTrip && c.acceptedRide != null) ...[
                    if (_showPhonePanel(c.acceptedRide!))
                      _phonePanel(c.acceptedRide!),
                    _tripBottomPanel(c.acceptedRide!),
                  ] else if (showOffers && selected != null)
                    _offerBottomPanel(selected, c)
                  else
                    _workBottomPanel(c),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _internetBanner() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFB71C1C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(context.tr('no_internet'),
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ]),
      );

  Widget _statusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
          ],
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                    fontSize: 14)),
          ),
        ]),
      );

  Widget _workBottomPanel(DriverHomeController c) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.12), blurRadius: 10),
          ],
        ),
        child: MainActionButtons(
          hasScheduleToday: c.hasScheduleToday,
          isOnline: c.isOnline,
          onStart: widget.onStartWork,
          onEnd: widget.onEndWork,
        ),
      );

  Widget _offerBottomPanel(TripRequest ride, DriverHomeController c) {
    final isNearest = c.nearestRequest?.id == ride.id;
    final stale = _isStaleOffer(ride.id);
    final m = ride.secsLeft ~/ 60;
    final s = ride.secsLeft % 60;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: isNearest
            ? Border.all(color: AppColors.primary, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.14), blurRadius: 12),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(isNearest ? Icons.star : Icons.place,
                color: isNearest ? AppColors.primary : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isNearest
                    ? context.tr('driver_map_nearest_offer')
                    : context.tr('driver_map_offer'),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            if (stale && !isNearest)
              Text(context.tr('driver_map_stale_offer'),
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
          ]),
          const SizedBox(height: 8),
          Text('📍 ${ride.from}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
          if (ride.to.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('🏁 ${ride.to}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.timer, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text('$m:${s.toString().padLeft(2, '0')} қолди',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (ride.distanceKm > 0)
              Text('${ride.distanceKm.toStringAsFixed(1)} км',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade700)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  c.dismissRequest(ride);
                  if (_selectedOfferId == ride.id) {
                    setState(() => _selectedOfferId = null);
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB71C1C),
                  side: const BorderSide(color: Color(0xFFB71C1C)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(context.tr('driver_map_reject'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: c.isBusy ? null : () => _acceptOffer(ride),
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(context.tr('driver_map_accept'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _phonePanel(TripRequest ride) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
          ],
        ),
        child: Row(children: [
          const Icon(Icons.phone, color: _green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ride.userPhone.isNotEmpty ? ride.userPhone : '—',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton.icon(
            onPressed: ride.userPhone.isEmpty
                ? null
                : () => callPhone(ride.userPhone),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.call, size: 18),
            label: Text(context.tr('trip_call_driver')),
          ),
        ]),
      );

  Widget _tripBottomPanel(TripRequest ride) {
    if (_tripPhase == _TripPhase.navigating) {
      return _buildNavPanel(ride);
    }
    return _buildPickPanel(ride);
  }

  Widget _buildPickPanel(TripRequest ride) {
    final toHint = ride.to.trim();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (toHint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.flag, color: _green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(toHint,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
          if (_prefillingDestination) ...[
            Row(children: [
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(context.tr('driver_map_geocoding_destination')),
            ]),
          ] else if (_destination == null) ...[
            Row(children: [
              const Icon(Icons.touch_app, color: _green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('driver_map_pick_destination_hint'),
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ),
            ]),
          ] else if (_calculating) ...[
            Row(children: [
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(context.tr('driver_map_calculating_distance')),
            ]),
          ] else if (_calcError != null) ...[
            Row(children: [
              Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_calcError!,
                    style: TextStyle(color: Colors.red.shade700)),
              ),
              TextButton(
                  onPressed: _calculateRoute,
                  child: Text(context.tr('driver_map_retry'))),
            ]),
          ] else if (_routeKm != null) ...[
            Row(children: [
              const Icon(Icons.navigation, color: _green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _fmt('driver_map_destination_km', {
                    'km': _routeKm!.toStringAsFixed(1),
                  }),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _destination = null;
                  _tripPolylines.clear();
                  _routeKm = null;
                }),
                child: Text(context.tr('driver_map_change_destination')),
              ),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startNavigation,
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.navigation),
                label: Text(context.tr('driver_map_start_navigation')),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: _confirmAbandon,
            child: Text(context.tr('driver_map_cancel_trip'),
                style: TextStyle(color: Color(0xFFB71C1C))),
          ),
        ],
      ),
    );
  }

  Widget _buildNavPanel(TripRequest ride) {
    final remaining =
        _routeKm == null ? 0.0 : (_routeKm! - _drivenKm).clamp(0.0, _routeKm!);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(_arrived ? Icons.flag : Icons.navigation,
                color: _green, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
              _arrived
                  ? context.tr('driver_map_trip_arrived')
                  : _fmt('driver_map_remaining_km', {
                      'km': remaining.toStringAsFixed(1),
                    }),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fmt('driver_map_current_fare_km', {
                      'km': _drivenKm.toStringAsFixed(1),
                    }),
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                    Text('${formatMoney(_liveFare)}',
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: _green)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _finishing ? null : _finishTrip,
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                ),
                child: _finishing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(context.tr('driver_map_finish_trip'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
