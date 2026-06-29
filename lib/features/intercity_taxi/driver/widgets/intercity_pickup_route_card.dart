import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/utils/map_launcher.dart';
import '../controllers/intercity_driver_panel_controller.dart';

/// Haydovchi panelida optimallashtirilgan olib ketish marshruti.
class IntercityPickupRouteCard extends StatelessWidget {
  const IntercityPickupRouteCard({
    super.key,
    required this.primaryColor,
  });

  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Consumer<IntercityDriverPanelController>(
      builder: (context, c, _) {
        if (!c.canCalculatePickupRoute && c.pickupRoute == null) {
          return const SizedBox.shrink();
        }

        final route = c.pickupRoute;
        final trip = c.tripData;
        final from = (trip?['from'] as String?)?.trim() ?? '';
        final to = (trip?['to'] as String?)?.trim() ?? '';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: primaryColor.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('intercity_pickup_route_title'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: primaryColor,
                ),
              ),
              if (from.isNotEmpty && to.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  context
                      .tr('intercity_pickup_route_chain')
                      .replaceAll('{from}', from)
                      .replaceAll('{to}', to),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: c.isCalculatingRoute || !c.canCalculatePickupRoute
                      ? null
                      : () => c.calculatePickupRoute(),
                  icon: c.isCalculatingRoute
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        )
                      : const Icon(Icons.route, size: 18),
                  label: Text(context.tr('pickup_passengers_btn')),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              if (c.routeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _routeErrorText(context, c.routeError!),
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
              ],
              if (route != null) ...[
                const SizedBox(height: 10),
                Text(
                  context
                      .tr('intercity_pickup_route_total')
                      .replaceAll('{km}', route.totalDistanceKm.toStringAsFixed(1))
                      .replaceAll('{min}', '${route.totalDurationMin}'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                ...route.stops.map(
                  (stop) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${stop.sequence}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context
                                    .tr('intercity_pickup_route_stop')
                                    .replaceAll('{name}', context.trMsg(stop.booking.userName))
                                    .replaceAll('{address}', stop.label),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              if (stop.booking.passengers > 1)
                                Text(
                                  context
                                      .tr('intercity_pickup_route_passengers')
                                      .replaceAll(
                                        '{count}',
                                        '${stop.booking.passengers}',
                                      ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await openMapsPickupRoute(route);
                      if (!context.mounted || ok) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('maps_open_failed')),
                        ),
                      );
                    },
                    icon: const Icon(Icons.navigation, size: 18),
                    label: Text(context.tr('intercity_pickup_route_start_nav')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _routeErrorText(BuildContext context, String code) {
    switch (code) {
      case 'pickup_route_no_gps':
        return context.tr('intercity_pickup_route_no_gps');
      case 'pickup_route_no_trip':
        return context.tr('intercity_pickup_route_no_trip');
      default:
        return context.tr('intercity_pickup_route_failed');
    }
  }
}
