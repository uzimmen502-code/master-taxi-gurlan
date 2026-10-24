import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/intercity_ride.dart';
import '../../intercity_tap_target.dart';
import '../intercity_colors.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: IntercityColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IntercityColors.border),
        boxShadow: [
          BoxShadow(
            color: IntercityColors.primary.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
              iconColor: IntercityColors.textMuted,
              left: '${ride.carModel}  •  ${ride.carNumber}',
              leftStyle: const TextStyle(
                fontSize: 12,
                color: IntercityColors.textMuted,
              ),
              right: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Узун таржимада (рус тили) қатор сиғмаса — кесилади,
                  // overflow бўлмайди.
                  Flexible(
                    child: Text(
                      '${context.tr('available_seats')}:',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: IntercityColors.textMuted,
                      ),
                    ),
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
          backgroundColor: IntercityColors.successSoft,
          child: Text(
            ride.driverName.isNotEmpty
                ? ride.driverName[0].toUpperCase()
                : '?',
            style: const TextStyle(
              color: AppColors.primaryText,
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
                    color: IntercityColors.text,
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
                    const Icon(Icons.star, color: IntercityColors.gold, size: 14),
                    const SizedBox(width: 2),
                    Text(
                      ride.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 12,
                        color: IntercityColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  context.tr('ic_ux_new_driver'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: IntercityColors.info,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
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
                color: IntercityColors.success,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              context.tr('sum'),
              style: const TextStyle(
                fontSize: 12,
                color: IntercityColors.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteRow(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.location_on_outlined,
          color: AppColors.primaryText,
          size: 16,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _buildRouteLabel(ride, Localizations.localeOf(context)),
            style: const TextStyle(
              fontSize: 13,
              color: IntercityColors.text,
              fontWeight: FontWeight.w500,
            ),
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
            style: leftStyle ??
                const TextStyle(fontSize: 13, color: IntercityColors.text),
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
    final hasSeats = ride.availableSeats > 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ride.femaleCount > 0 || ride.maleCount > 0)
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    if (ride.femaleCount > 0)
                      IntercityIconText(
                        icon: Icons.female,
                        iconSize: 16,
                        iconColor: IntercityColors.textMuted,
                        text: '${context.tr('gender_female')}: '
                            '${ride.femaleCount} ${context.tr('passengers_unit')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: IntercityColors.textMuted,
                        ),
                      ),
                    if (ride.maleCount > 0)
                      IntercityIconText(
                        icon: Icons.male,
                        iconSize: 16,
                        iconColor: IntercityColors.textMuted,
                        text: '${context.tr('gender_male')}: '
                            '${ride.maleCount} ${context.tr('passengers_unit')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: IntercityColors.textMuted,
                        ),
                      ),
                  ],
                ),
              Row(
                children: [
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.access_time,
                      color: IntercityColors.textMuted,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${context.tr('departure_time_label')} '
                      '${_formatTime(ride.departureTime)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: IntercityColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        IntercityTapTarget(
          label: context.tr('call_lowercase'),
          onTap: onCall,
          radius: 12,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: IntercityColors.border),
              borderRadius: BorderRadius.circular(12),
              color: IntercityColors.surfaceSoft,
            ),
            child: const Icon(
              Icons.phone,
              size: 20,
              color: AppColors.primaryText,
            ),
          ),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: IntercityTapTarget.minSize,
          ),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: IntercityColors.primary,
              foregroundColor: IntercityColors.onPrimary,
              disabledBackgroundColor: IntercityColors.border,
              disabledForegroundColor: IntercityColors.textMuted,
              elevation: 0,
              minimumSize: const Size(0, IntercityTapTarget.minSize),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: hasSeats ? onBook : null,
            // Ўчиқ тугма сабабини айтади: жой қолмаган.
            child: Text(
              hasSeats ? context.tr('book_btn') : context.tr('ic_ux_seats_full'),
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
    return Semantics(
      label: context.tr('ic_ux_free_seats').replaceAll('{n}', '$seats'),
      excludeSemantics: true,
      child: _badge(hasSeats),
    );
  }

  Widget _badge(bool hasSeats) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: hasSeats ? IntercityColors.successSoft : IntercityColors.dangerSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.airline_seat_recline_normal,
              size: 14,
              color: hasSeats ? IntercityColors.success : IntercityColors.danger,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '$seats',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: hasSeats ? IntercityColors.success : IntercityColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
