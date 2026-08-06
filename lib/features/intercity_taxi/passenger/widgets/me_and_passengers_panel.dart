import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../intercity_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/phone_launcher.dart';
import '../../../../models/intercity_booking.dart';
import '../../../../repositories/entertainment_repository.dart';
import '../../../../repositories/intercity_bookings_repository.dart';
import '../../../entertainment/passenger/screens/entertainment_list_screen.dart';
import '../controllers/intercity_taxi_controller.dart';
import '../controllers/me_and_passengers_controller.dart';
import 'intercity_pickup_sheet.dart';

class MeAndPassengersPanel extends StatefulWidget {
  const MeAndPassengersPanel({super.key});

  @override
  State<MeAndPassengersPanel> createState() => _MeAndPassengersPanelState();
}

class _MeAndPassengersPanelState extends State<MeAndPassengersPanel> {
  int _selectedRating = 0;
  bool _ratingSubmitted = false;
  bool _ratingLoading = false;
  bool _previewLoading = false;
  String? _previewError;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MeAndPassengersController>();
    if (!c.isPanelVisible) {
      return const SizedBox.shrink();
    }

    final isPassengerPick = c.isPassengerPick;
    final isPreview = c.isPreview;
    final isBookingStep = c.isBookingStep;
    final collapsed = !isBookingStep && c.isSheetCollapsed;
    final initialSize = isBookingStep
        ? MeAndPassengersController.sheetMid
        : MeAndPassengersController.sheetMin;

    return DraggableScrollableSheet(
      controller: c.draggableController,
      initialChildSize: initialSize,
      minChildSize: MeAndPassengersController.sheetMin,
      maxChildSize: MeAndPassengersController.sheetMax,
      snap: true,
      snapSizes: MeAndPassengersController.sheetSnaps,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: IntercityColors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildSheetHeader(context, c),
            if (collapsed && c.myBooking != null)
              Expanded(
                child: _wrapSheetDrag(
                  context,
                  c,
                  child: SingleChildScrollView(
                    controller: scroll,
                    physics: const NeverScrollableScrollPhysics(),
                    child: _buildCollapsedActiveBody(context, c),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: EdgeInsets.zero,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (isPassengerPick && c.previewRide != null)
                      _buildPassengerPickBody(context, c)
                    else if (isPreview && c.previewRide != null)
                      _buildPreviewBody(context, c)
                    else if (c.myBooking != null) ...[
                      const _Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InfoTile(
                              icon: Icons.person_outline,
                              label: context.tr('driver_label'),
                              value: c.myBooking!.driverName,
                            ),
                            const SizedBox(height: 6),
                            _InfoTile(
                              icon: Icons.directions_car_outlined,
                              label: context.tr('car_label'),
                              value: c.myBooking!.carNumber,
                            ),
                            const SizedBox(height: 6),
                            _InfoTile(
                              icon: Icons.location_on_outlined,
                              label: context.tr('route_label'),
                              value: c.routeDisplayLabel(
                                Localizations.localeOf(context),
                              ),
                            ),
                            if (c.needsPickup) ...[
                              const SizedBox(height: 10),
                              _PickupPromptBanner(
                                onTap: () => _openPickupSheet(context, c),
                              ),
                            ] else if (c.myBooking!.hasPickupAddress) ...[
                              const SizedBox(height: 6),
                              _InfoTile(
                                icon: Icons.place_outlined,
                                label: context.tr('tooltip_pickup'),
                                value: c.myBooking!.pickupAddress,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const _Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: _buildActionButtons(context, c),
                      ),
                      if (c.myBooking!.status ==
                          IntercityBookingStatus.completed) ...[
                        const _Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: _ratingSubmitted ||
                                  (c.myBooking!.passengerRating ?? 0) > 0
                              ? _RatingDone(
                                  rating: c.myBooking!.passengerRating ??
                                      _selectedRating,
                                )
                              : _RatingWidget(
                                  driverName: c.myBooking!.driverName,
                                  selected: _selectedRating,
                                  loading: _ratingLoading,
                                  onRate: (r) =>
                                      setState(() => _selectedRating = r),
                                  onSubmit: () => _submitRating(context, c),
                                ),
                        ),
                      ],
                      if (c.rosterBookings.isNotEmpty) ...[
                        const _Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: Text(
                            '${context.tr('co_passengers')} '
                            '(${c.rosterBookings.length})',
                            style: TextStyle(
                              fontSize: 12,
                              color: IntercityColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        ...c.rosterBookings
                            .map((b) => _PassengerTile(booking: b)),
                      ] else if (!c.isLoading) ...[
                        const _Divider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: Text(
                            context.tr('no_co_passengers'),
                            style: TextStyle(
                              fontSize: 12,
                              color: IntercityColors.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (c.isLoading)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _wrapSheetDrag(
    BuildContext context,
    MeAndPassengersController c, {
    required Widget child,
    VoidCallback? onTap,
  }) {
    final screenH = MediaQuery.of(context).size.height;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragUpdate: (details) {
        c.dragSheetBy(-details.delta.dy / screenH);
      },
      onVerticalDragEnd: (_) => c.snapSheetToNearest(),
      child: child,
    );
  }

  Widget _buildSheetHeader(BuildContext context, MeAndPassengersController c) {
    return _wrapSheetDrag(
      context,
      c,
      onTap: c.isBookingStep ? null : c.toggleSheetExpanded,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: IntercityColors.textFaint,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            if (c.isPassengerPick)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${context.tr('passengers')} soni',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              )
            else if (c.isPreview)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Бронни тасдиқланг',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              )
            else
              Row(
                children: [
                  Icon(
                    Icons.people_outline,
                    color: IntercityColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('me_and_passengers'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: IntercityColors.primary,
                      ),
                    ),
                  ),
                  if (c.myBooking != null)
                    _StatusBadge(booking: c.myBooking!),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsedActiveBody(
    BuildContext context,
    MeAndPassengersController c,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.needsPickup) ...[
            _PickupPromptBanner(
              compact: true,
              onTap: () => _openPickupSheet(context, c),
            ),
            const SizedBox(height: 8),
          ],
          _buildActionButtons(context, c, compact: true),
        ],
      ),
    );
  }

  Future<void> _openPickupSheet(
    BuildContext context,
    MeAndPassengersController c,
  ) async {
    final booking = c.myBooking;
    if (booking == null || !c.needsPickup) return;
    await IntercityPickupSheet.show(context, booking: booking);
  }

  Widget _buildActionButtons(
    BuildContext context,
    MeAndPassengersController c, {
    bool compact = false,
  }) {
    final vPad = compact ? 8.0 : 10.0;
    final booking = c.myBooking;
    final showEntertainment = booking != null &&
        IntercityBookingStatus.active.contains(booking.status);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: IntercityColors.primary,
                  side: BorderSide(color: IntercityColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: EdgeInsets.symmetric(vertical: vPad),
                ),
                onPressed: () => callPhone(booking!.driverPhone),
                icon: const Icon(Icons.phone, size: 16),
                label: Text(
                  context.tr('call_lowercase'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: IntercityColors.danger,
                  side: BorderSide(color: IntercityColors.danger),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: EdgeInsets.symmetric(vertical: vPad),
                ),
                onPressed: () => _confirmCancel(context, c),
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: Text(
                  context.tr('cancel'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        if (showEntertainment) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepPurple.shade700,
                side: BorderSide(color: Colors.deepPurple.shade200),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.symmetric(vertical: vPad),
              ),
              onPressed: () => _openEntertainment(context, booking),
              icon: const Icon(Icons.movie_outlined, size: 16),
              label: const Text(
                'Kino',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openEntertainment(
    BuildContext context,
    IntercityBooking booking,
  ) async {
    final repo = context.read<EntertainmentRepository>();
    final ok = await repo.userHasEntertainmentAccess(
      userPhone: booking.userPhone,
      driverId: booking.driverId,
      bookingId: booking.id,
    );
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Кинони фақат тасдиқланган бронингиз бўлганда томоша қила оласиз.',
          ),
        ),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntertainmentListScreen(
          driverId: booking.driverId,
          driverName: booking.driverName,
          userPhone: booking.userPhone,
          bookingId: booking.id,
        ),
      ),
    );
  }

  Widget _buildPassengerPickBody(
    BuildContext context,
    MeAndPassengersController c,
  ) {
    final ride = c.previewRide!;
    final taxiCtrl = context.watch<IntercityTaxiController>();
    final maxSeats = ride.availableSeats.clamp(1, 4);
    final total = ride.price * taxiCtrl.passengers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.routeDisplayLabel(Localizations.localeOf(context)),
            style: TextStyle(fontSize: 13, color: IntercityColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            'Бўш ўрин: $maxSeats',
            style: TextStyle(fontSize: 12, color: IntercityColors.textFaint),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: IntercityColors.surfaceSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: IntercityColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.people_outline,
                    color: IntercityColors.primary, size: 20),
                const SizedBox(width: 12),
                Text(
                  context.tr('passengers'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                _pickCounterBtn(
                  Icons.remove,
                  taxiCtrl.passengers <= 1
                      ? null
                      : () => taxiCtrl.decPassengersForSeats(),
                  IntercityColors.surfaceSoft,
                  IntercityColors.textMuted,
                ),
                const SizedBox(width: 12),
                Text(
                  '${taxiCtrl.passengers}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: IntercityColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                _pickCounterBtn(
                  Icons.add,
                  taxiCtrl.passengers >= maxSeats
                      ? null
                      : () => taxiCtrl.incPassengersForSeats(maxSeats),
                  IntercityColors.primary,
                  IntercityColors.onPrimary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Жами:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                formatMoney(total),
                style: TextStyle(
                  color: IntercityColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: c.cancelPassengerPick,
                  child: const Text('Бекор'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: IntercityColors.primary,
                    foregroundColor: IntercityColors.onPrimary,
                  ),
                  onPressed: () => c.confirmPassengerCount(),
                  child: const Text(
                    'Давом etish',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pickCounterBtn(
    IconData icon,
    VoidCallback? onTap,
    Color bg,
    Color iconColor,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }

  Widget _buildPreviewBody(
    BuildContext context,
    MeAndPassengersController c,
  ) {
    final ride = c.previewRide!;
    final taxiCtrl = context.watch<IntercityTaxiController>();
    final total = ride.price * taxiCtrl.passengers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PreviewRow('👤', 'Ҳайдовчи', ride.driverName),
          _PreviewRow('🚗', 'Машина', '${ride.carModel} • ${ride.carNumber}'),
          _PreviewRow(
            '📍',
            'Йўналиш',
            ride.routeDisplayLabel(Localizations.localeOf(context)),
          ),
          _PreviewRow('🕐', 'Жўнаш', _formatPreviewTime(ride.departureTime)),
          _PreviewRow('💺', 'Йўловчилар', '${taxiCtrl.passengers} та'),
          const SizedBox(height: 10),
          Divider(color: IntercityColors.border),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Жами:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                formatMoney(total),
                style: TextStyle(
                  color: IntercityColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          if (_previewError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: IntercityColors.dangerSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: IntercityColors.danger),
              ),
              child: Text(
                _previewError!,
                style: TextStyle(color: IntercityColors.danger, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _previewLoading ? null : () => c.backToPassengerPick(),
                  child: const Text('Орқaga'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: IntercityColors.primary,
                    foregroundColor: IntercityColors.onPrimary,
                  ),
                  onPressed:
                      _previewLoading ? null : () => _confirmPreview(context, c),
                  child: _previewLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: IntercityColors.surface,
                          ),
                        )
                      : const Text(
                          'Тасдиқлаш',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPreview(
    BuildContext context,
    MeAndPassengersController c,
  ) async {
    final ride = c.previewRide;
    if (ride == null) return;

    setState(() {
      _previewLoading = true;
      _previewError = null;
    });

    try {
      final taxiCtrl = context.read<IntercityTaxiController>();
      final (booking, errorKey) = await taxiCtrl.bookRide(
        ride,
        defaultPassengerName: 'Йўловчи',
      );

      if (!mounted) return;
      if (errorKey != null) {
        setState(() {
          _previewLoading = false;
          _previewError = context.trMsg(errorKey);
        });
        return;
      }
      if (booking == null) {
        setState(() {
          _previewLoading = false;
          _previewError = context.tr('error');
        });
        return;
      }

      setState(() => _previewLoading = false);
      c.attachWithBooking(ride.id, booking);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Брон муваффақиятли юборилди!'),
          backgroundColor: IntercityColors.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewLoading = false;
        _previewError = e.toString();
      });
    }
  }

  String _formatPreviewTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _confirmCancel(
    BuildContext context,
    MeAndPassengersController c,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('cancel_booking_title')),
        content: Text(context.tr('cancel_booking_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('no')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: IntercityColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('yes_cancel')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final booking = c.myBooking!;
    try {
      await IntercityBookingsRepository().cancelBooking(
        bookingId: booking.id,
        reason: 'passenger_cancel',
      );
      if (!context.mounted) return;
      context.read<IntercityTaxiController>().applyLocalBookingStats(
            driverId: booking.driverId,
            userGender: booking.userGender,
            passengerDelta: -booking.passengers,
          );
      c.detach();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Хатолик: $e'),
          backgroundColor: IntercityColors.danger,
        ),
      );
    }
  }

  Future<void> _submitRating(
    BuildContext context,
    MeAndPassengersController c,
  ) async {
    if (_selectedRating == 0) return;
    setState(() => _ratingLoading = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('updateIntercityDriverRating')
          .call({
        'driverId': c.myBooking!.driverId,
        'rating': _selectedRating,
        'bookingId': c.myBooking!.id,
      });
      if (!mounted) return;
      setState(() {
        _ratingSubmitted = true;
        _ratingLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _ratingLoading = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Хатолик: $e'),
          backgroundColor: IntercityColors.danger,
        ),
      );
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.booking});

  final IntercityBooking booking;

  @override
  Widget build(BuildContext context) {
    final isPending = booking.status == IntercityBookingStatus.pending;
    final isCompleted = booking.status == IntercityBookingStatus.completed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isPending
            ? IntercityColors.warningSoft
            : isCompleted
                ? IntercityColors.infoSoft
                : IntercityColors.successSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPending
              ? IntercityColors.warning
              : isCompleted
                  ? IntercityColors.border
                  : IntercityColors.border,
        ),
      ),
      child: Text(
        isPending
            ? context.tr('status_pending_label')
            : isCompleted
                ? context.tr('trip_completed')
                : context.tr('booking_confirmed'),
        style: TextStyle(
          fontSize: 11,
          color: isPending
              ? IntercityColors.warning
              : isCompleted
                  ? IntercityColors.info
                  : IntercityColors.primary,
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow(this.emoji, this.label, this.value);

  final String emoji;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, color: IntercityColors.textMuted),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: IntercityColors.textFaint),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 12, color: IntercityColors.textMuted),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PassengerTile extends StatelessWidget {
  const _PassengerTile({required this.booking});

  final IntercityBooking booking;

  String? _subtitle(BuildContext context) {
    final age = ageFromBirthDate(booking.userBirthDate);
    final parts = <String>[];
    if (age != null && age > 0) {
      parts.add('$age ${context.tr('age_years')}');
    }
    if (booking.district.isNotEmpty) {
      parts.add(booking.district);
    }
    if (booking.passengers > 1) {
      parts.add('${booking.passengers} ${context.tr('passengers')}');
    }
    if (parts.isEmpty) return null;
    return parts.join('  •  ');
  }

  @override
  Widget build(BuildContext context) {
    final female = booking.userGender == 'female';
    final subtitle = _subtitle(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Text(female ? '👩' : '👨', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.userName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: IntercityColors.textFaint),
                  ),
              ],
            ),
          ),
          if (booking.userPhone.isNotEmpty)
            IconButton(
              onPressed: () => callPhone(booking.userPhone),
              icon: Icon(
                Icons.phone,
                color: IntercityColors.primary,
                size: 20,
              ),
              style: IconButton.styleFrom(
                backgroundColor: IntercityColors.successSoft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: IntercityColors.surfaceSoft);
}

class _RatingWidget extends StatelessWidget {
  const _RatingWidget({
    required this.driverName,
    required this.selected,
    required this.loading,
    required this.onRate,
    required this.onSubmit,
  });

  final String driverName;
  final int selected;
  final bool loading;
  final void Function(int) onRate;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${context.tr('rate_driver')}: $driverName',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(5, (i) {
            return GestureDetector(
              onTap: () => onRate(i + 1),
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  i < selected ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 32,
                ),
              ),
            );
          }),
        ),
        if (selected > 0) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: IntercityColors.primary,
                foregroundColor: IntercityColors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: loading ? null : onSubmit,
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: IntercityColors.surface,
                      ),
                    )
                  : Text(context.tr('submit')),
            ),
          ),
        ],
      ],
    );
  }
}

class _RatingDone extends StatelessWidget {
  const _RatingDone({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...List.generate(
          5,
          (i) => Icon(
            i < rating ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: 22,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          context.tr('rating_sent'),
          style: TextStyle(
            color: IntercityColors.primary,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _PickupPromptBanner extends StatelessWidget {
  const _PickupPromptBanner({
    required this.onTap,
    this.compact = false,
  });

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IntercityColors.warningSoft,
      borderRadius: BorderRadius.circular(compact ? 10 : 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 10,
          ),
          child: Row(
            children: [
              Icon(
                Icons.edit_location_alt_outlined,
                color: IntercityColors.warning,
                size: compact ? 18 : 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('intercity_enter_pickup_btn'),
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: IntercityColors.warning,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: IntercityColors.warning,
                size: compact ? 18 : 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
