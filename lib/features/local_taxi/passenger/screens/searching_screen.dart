import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/active_trip.dart';
import '../../../../repositories/driver_repository.dart';
import '../../../../repositories/rides_repository.dart';
import '../../../../services/location_service.dart';
import '../controllers/searching_controller.dart';
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
  });

  final String from;
  final String to;
  final String taxiType;

  /// Mavjud `trips/{id}` ni tiklash (qayta yaratmaslik).
  final String? tripId;

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

    // Side-effects: snackbar va dialog.
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
        backgroundColor: AppColors.scaffold,
        appBar: AppBar(
          title: Text(context.tr('searching_driver_title')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              await c.cancelByUser();
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ),
        body: Column(children: [
          _statusBanner(c),
          _addressRow(
            icon: Icons.circle,
            color: AppColors.primary,
            text: c.from,
          ),
          if (c.to.isNotEmpty)
            _addressRow(
              icon: Icons.location_on,
              color: Colors.red,
              text: c.to,
            ),
          const Divider(height: 1),
          Expanded(child: _searchingBody(c)),
        ]),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // Sections
  // ────────────────────────────────────────────────────────────────────
  Widget _statusBanner(SearchingController c) {
    return Container(
      color: _blue,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(children: [
        if (c.driverReserved) ...[
          const Icon(Icons.check_circle, color: Colors.white, size: 48),
          const SizedBox(height: 8),
          Text(
            context.tr('driver_found_waiting'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          ),
        ] else if (c.isSearching) ...[
          const CircularProgressIndicator(
              color: Colors.white, strokeWidth: 3),
          const SizedBox(height: 12),
          Text(
            _fmt('radius_timer', {
              'km': c.currentRadiusKm.toInt().toString(),
              'sec': c.seconds.toString(),
            }),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            _fmt('cycle_progress', {
              'current': '${c.cycle + 1}',
              'total': '3',
            }),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ] else ...[
          const Icon(Icons.sentiment_dissatisfied,
              color: Colors.white70, size: 48),
          const SizedBox(height: 8),
          Text(
            context.tr('no_free_driver_now'),
            style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('retry_later'),
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: _blue),
            child: Text(context.tr('back_short')),
          ),
        ],
      ]),
    );
  }

  Widget _addressRow({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  /// Broadcast modeli — yo'lovchi haydovchini tanlamaydi, faqat kutadi.
  /// So'rov radius ichidagi barcha haydovchilarga avtomatik yuborilgan;
  /// birinchi qabul qilgan haydovchi bilan bog'lanadi.
  Widget _searchingBody(SearchingController c) {
    if (!c.isSearching) {
      return Center(
        child: Text(
          context.tr('drivers_not_found'),
          style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        ),
      );
    }

    if (c.driverReserved) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.directions_car,
                color: AppColors.primary, size: 56),
            const SizedBox(height: 14),
            Text(
              context.tr('driver_found_waiting'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      );
    }

    final nearby = c.drivers.length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.podcasts, color: Colors.grey.shade400, size: 56),
          const SizedBox(height: 14),
          Text(
            context.tr('searching_broadcast_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          if (nearby > 0) ...[
            const SizedBox(height: 8),
            Text(
              _fmt('nearby_drivers_count', {'n': '$nearby'}),
              style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ]),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // Side-effects
  // ────────────────────────────────────────────────────────────────────
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
