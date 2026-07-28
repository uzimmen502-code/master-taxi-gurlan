import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/active_trip.dart';
import '../../../../repositories/driver_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../services/location_service.dart';
import '../controllers/searching_controller.dart';
import '../widgets/passenger_search_map_view.dart';
import 'local_taxi_active_trip_screen.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';

class SearchingScreen extends StatelessWidget {
  const SearchingScreen({
    super.key,
    required this.from,
    required this.to,
    required this.taxiType,
    this.tripId,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
  });

  final String from;
  final String to;
  final String taxiType;
  final String? tripId;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SearchingController>(
      create: (ctx) => SearchingController(
        ridesRepo: ctx.read<RidesRepository>(),
        driverRepo: ctx.read<DriverRepository>(),
        locationService: ctx.read<LocationService>(),
        from: from,
        to: to,
        taxiType: taxiType,
        existingTripId: tripId,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropoffLat: dropoffLat,
        dropoffLng: dropoffLng,
      )..start(),
      child: const _SearchingView(),
    );
  }
}

class _SearchingView extends StatefulWidget {
  const _SearchingView();

  @override
  State<_SearchingView> createState() => _SearchingViewState();
}

class _SearchingViewState extends State<_SearchingView> {
  static const _blue = AppColors.primary;

  bool _acceptedDialogShown = false;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SearchingController>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final err = c.consumeError();
      if (err != null) _snack(context.trMsg(err));

      if (!_acceptedDialogShown) {
        final accepted = c.consumeAcceptedTrip();
        if (accepted != null) {
          _acceptedDialogShown = true;
          _openActiveTrip(accepted);
        }
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await c.cancelByUser();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: PassengerSearchMapView(
                fromLat: c.fromLat,
                fromLng: c.fromLng,
                radiusKm: c.currentRadiusKm,
                drivers: c.drivers,
                isSearching: c.isSearching,
                pickupLabel: context.tr('passenger_map_you'),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      _roundIconButton(
                        icon: Icons.close,
                        onPressed: () async {
                          await c.cancelByUser();
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _statusChip(c)),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: _bottomPanel(c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) =>
      Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: IconButton(
          icon: Icon(icon, color: _blue),
          onPressed: onPressed,
        ),
      );

  Widget _statusChip(SearchingController c) {
    if (c.isSearching) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _blue,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
          ],
        ),
        child: Row(children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fmt('radius_timer', {
                    'km': c.currentRadiusKm.toInt().toString(),
                    'sec': c.seconds.toString(),
                  }),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  _fmt('cycle_progress', {
                    'current': '${c.cycle + 1}',
                    'total': '3',
                  }),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8),
        ],
      ),
      child: Text(
        context.tr('no_free_driver_now'),
        style: TextStyle(
            fontWeight: FontWeight.w600, color: Colors.grey.shade800),
      ),
    );
  }

  Widget _bottomPanel(SearchingController c) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.14), blurRadius: 12),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _addressRow(
              icon: Icons.circle,
              color: AppColors.primary,
              text: c.from,
            ),
            if (c.to.isNotEmpty) ...[
              const SizedBox(height: 6),
              _addressRow(
                icon: Icons.location_on,
                color: Colors.red,
                text: c.to,
              ),
            ],
            const SizedBox(height: 10),
            if (c.isSearching) ...[
              Text(
                context.tr('searching_broadcast_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              if (c.drivers.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _fmt('nearby_drivers_count', {'n': '${c.drivers.length}'}),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ] else ...[
              Text(
                context.tr('drivers_not_found'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(backgroundColor: _blue),
                child: Text(context.tr('back_short')),
              ),
            ],
          ],
        ),
      );

  Widget _addressRow({
    required IconData icon,
    required Color color,
    required String text,
  }) =>
      Row(children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ),
      ]);

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
    ));
  }

  String _fmt(String key, Map<String, String> vars) {
    var text = context.tr(key);
    vars.forEach((k, v) {
      text = text.replaceAll('{$k}', v);
    });
    return text;
  }

  void _openActiveTrip(ActiveTrip trip) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LocalTaxiActiveTripScreen(
          tripId: trip.id,
          initialTrip: trip,
        ),
      ),
    );
  }
}
