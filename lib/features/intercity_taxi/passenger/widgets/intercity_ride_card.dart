import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/intercity_ride.dart';

class IntercityRideCard extends StatelessWidget {
  final IntercityRide ride;
  final VoidCallback onCall;
  final VoidCallback onBook;

  const IntercityRideCard({
    super.key,
    required this.ride,
    required this.onCall,
    required this.onBook,
  });

  static const Color _green = AppColors.courierGreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderRow(context),
            const SizedBox(height: 10),
            _buildRouteRow(context),
            const SizedBox(height: 6),
            _buildInfoRow(
              icon: Icons.directions_car_outlined,
              iconColor: Colors.grey.shade500,
              left: '${ride.carModel}  •  ${ride.carNumber}',
              leftStyle: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              right: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${context.tr('available_seats')}:',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 4),
                  _SeatsBadge(seats: ride.availableSeats),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildActionsRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.green.shade100,
          child: Text(
            ride.driverName.isNotEmpty
                ? ride.driverName[0].toUpperCase()
                : '?',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  ride.driverName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              if (ride.rating > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 14),
                    const SizedBox(width: 2),
                    Text(
                      ride.rating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'Янги ҳайдовчи',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              formatPrice(ride.price),
              style: const TextStyle(
                color: _green,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              context.tr('sum'),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteRow(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.location_on_outlined,
            color: Colors.green.shade400, size: 16),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _buildRouteLabel(ride, Localizations.localeOf(context)),
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required Color iconColor,
    required String left,
    required Widget right,
    TextStyle? leftStyle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            left,
            style: leftStyle ?? const TextStyle(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: right,
          ),
        ),
      ],
    );
  }

  Widget _buildActionsRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ride.femaleCount > 0 || ride.maleCount > 0)
                Text(
                  '${ride.femaleCount > 0 ? "${context.tr('gender_female')} 👩: ${ride.femaleCount} ${context.tr('passengers_unit')}  " : ""}'
                  '${ride.maleCount > 0 ? "${context.tr('gender_male')} 👨: ${ride.maleCount} ${context.tr('passengers_unit')}" : ""}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    color: Colors.grey.shade400,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${context.tr('departure_time_label')}: '
                    '${_formatTime(ride.departureTime)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onCall,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.phone,
                size: 18,
                weight: 700,
                color: Colors.green.shade700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 36,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade600,
              elevation: 0,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: ride.availableSeats > 0 ? onBook : null,
            child: Text(
              context.tr('book_btn'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _buildRouteLabel(IntercityRide ride, Locale locale) {
    return ride.routeDisplayLabel(locale);
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _SeatsBadge extends StatelessWidget {
  const _SeatsBadge({required this.seats});

  final int seats;

  @override
  Widget build(BuildContext context) {
    final hasSeats = seats > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: hasSeats ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '💺 $seats',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: hasSeats ? Colors.green.shade700 : Colors.red.shade700,
        ),
      ),
    );
  }
}
