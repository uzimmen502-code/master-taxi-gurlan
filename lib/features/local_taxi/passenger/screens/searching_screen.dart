import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/active_trip.dart';
import '../../../../models/nearby_driver.dart';
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
        if (mounted) Navigator.of(context).pop();
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
              if (mounted) Navigator.pop(context);
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
          Expanded(child: _driversList(c)),
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
        if (c.isSearching) ...[
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

  Widget _driversList(SearchingController c) {
    if (c.drivers.isEmpty) {
      return Center(
        child: Text(
          c.isSearching
              ? context.tr('drivers_searching')
              : context.tr('drivers_not_found'),
          style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        ),
      );
    }
    return Column(children: [
      if (c.pendingDriverId.isEmpty)
        Container(
          color: Colors.amber.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Icon(Icons.touch_app, size: 16, color: Colors.amber.shade800),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                context.tr('select_driver_to_send'),
                style: TextStyle(
                    fontSize: 12, color: Colors.amber.shade900),
              ),
            ),
          ]),
        ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: c.drivers.length,
          itemBuilder: (_, i) {
            final d = c.drivers[i];
            final isPending = c.pendingDriverId == d.driver.id;
            final isRejected = c.rejectedByIds.contains(d.driver.id);
            final hasPendingOther =
                c.pendingDriverId.isNotEmpty && !isPending;
            return _DriverTile(
              driver: d,
              isPending: isPending,
              isRejected: isRejected,
              disabled: isRejected || hasPendingOther,
              onTap: (isPending || isRejected || hasPendingOther)
                  ? null
                  : () => c.selectDriver(d),
            );
          },
        ),
      ),
    ]);
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

class _DriverTile extends StatelessWidget {
  const _DriverTile({
    required this.driver,
    this.isPending = false,
    this.isRejected = false,
    this.disabled = false,
    this.onTap,
  });

  final NearbyDriver driver;
  final bool isPending;
  final bool isRejected;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = driver.driver;

    Color bg = Colors.white;
    Color border = Colors.transparent;
    if (isPending) {
      bg = const Color(0xFFE3F2FD); // light blue — yuborildi
      border = AppColors.primary;
    } else if (isRejected) {
      bg = Colors.grey.shade200;
    }

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
        ],
      ),
      child: Opacity(
        opacity: (disabled && !isPending) ? 0.45 : 1.0,
        child: Row(children: [
          Text(isPending ? '⏳' : '🚕',
              style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
                Text(
                  '${d.car} · ${d.plate}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600),
                ),
                if (isPending)
                  Text(
                    context.tr('sent_waiting_response'),
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600),
                  )
                else if (isRejected)
                  Text(
                    context.tr('rejected_short'),
                    style: TextStyle(fontSize: 11, color: Colors.red),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                driver.distanceKm > 0
                    ? '${driver.distanceKm.toStringAsFixed(1)} км'
                    : context.tr('no_gps_short'),
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              if (!disabled && !isPending && !isRejected)
                const Icon(Icons.send,
                    color: AppColors.primary, size: 18),
              if (isPending)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
        ]),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: tile,
      ),
    );
  }
}
