import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/phone_launcher.dart';
import '../../../../core/utils/map_launcher.dart';
import '../../../../models/intercity_booking.dart';
import '../../../../repositories/intercity_bookings_repository.dart';
import '../../../../repositories/schedules_repository.dart';
import '../../../driver_schedule/screens/driver_schedule_screen.dart';
import '../../../entertainment/driver/widgets/driver_entertainment_picker.dart';
import '../controllers/intercity_driver_panel_controller.dart';
import '../intercity_route_stops.dart';
import '../widgets/intercity_booking_request_dialog.dart';
import '../widgets/intercity_pickup_route_card.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../utils/intercity_places.dart';

class IntercityDriverPanelScreen extends StatelessWidget {
  const IntercityDriverPanelScreen({
    super.key,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.driverCar,
    required this.driverPlate,
  });

  final String driverId;
  final String driverName;
  final String driverPhone;
  final String driverCar;
  final String driverPlate;

  static const _primary = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => IntercityDriverPanelController(
        driverId: driverId,
        driverName: driverName,
        driverPhone: driverPhone,
        driverCar: driverCar,
        driverPlate: driverPlate,
        bookingsRepo: ctx.read<IntercityBookingsRepository>(),
        schedulesRepo: ctx.read<SchedulesRepository>(),
      )..init(),
      child: const _IntercityDriverPanelView(),
    );
  }
}

class _IntercityDriverPanelView extends StatefulWidget {
  const _IntercityDriverPanelView();

  @override
  State<_IntercityDriverPanelView> createState() =>
      _IntercityDriverPanelViewState();
}

class _IntercityDriverPanelViewState extends State<_IntercityDriverPanelView>
    with WidgetsBindingObserver {
  String? _lastDialogId;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tryShowPendingDialog();
    }
  }

  Future<void> _tryShowPendingDialog() async {
    if (!mounted || _dialogOpen) return;
    final c = context.read<IntercityDriverPanelController>();
    if (c.pending.isEmpty) return;
    await _openBookingDialog(c, c.pending.first);
  }

  Future<void> _openBookingDialog(
    IntercityDriverPanelController c,
    IntercityBooking b,
  ) async {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;
    _lastDialogId = b.id;

    await showIntercityBookingRequestDialog(
      context: context,
      booking: b,
      routeDisplay: IntercityPlaces.tripRouteDisplay(
        c.tripData,
        locale: Localizations.localeOf(context),
      ),
      onAccept: () => c.accept(b.id),
      onReject: () => c.reject(b.id),
    );

    if (!mounted) return;
    _dialogOpen = false;
    c.dialogShown();
    _tryShowPendingDialog();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<IntercityDriverPanelController>();
    final trip = c.tripData;
    final route = IntercityPlaces.tripRouteDisplay(
      trip,
      locale: Localizations.localeOf(context),
    );
    final price = (trip?['price'] as num?)?.toInt() ?? 0;
    final hour = (trip?['hour'] as num?)?.toInt() ?? 8;
    final seats = c.seatsLeft;

    if (c.pendingDialogBookingId != null &&
        c.pendingDialogBookingId != _lastDialogId) {
      final id = c.pendingDialogBookingId!;
      IntercityBooking? booking;
      for (final b in [...c.pending, ...c.bookings]) {
        if (b.id == id) {
          booking = b;
          break;
        }
      }
      if (booking != null) {
        final b = booking;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openBookingDialog(c, b);
        });
      }
    }

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(context.tr('intercity_taxi')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
          ),
        ],
      ),
      body: c.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              children: [
                _tripCard(
                  context,
                  c,
                  route,
                  hour,
                  seats,
                  price,
                ),
                const SizedBox(height: 12),
                DriverEntertainmentPicker(
                  driverId: c.driverId,
                  primaryColor: IntercityDriverPanelScreen._primary,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('auto_accept_bookings')),
                  subtitle: Text(context.tr('auto_accept_off_hint'),
                      style: const TextStyle(fontSize: 11)),
                  value: c.autoAccept,
                  onChanged: (v) => c.setAutoAccept(v),
                ),
                if (c.canCalculatePickupRoute || c.pickupRoute != null) ...[
                  const SizedBox(height: 12),
                  IntercityPickupRouteCard(
                    primaryColor: IntercityDriverPanelScreen._primary,
                  ),
                ],
                if (c.pending.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Text(context.tr('pending_bookings_header'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.orange)),
                    const Spacer(),
                    Text(context.tr('count_items')
                        .replaceAll('{count}', '${c.pending.length}'),
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade700)),
                  ]),
                  const SizedBox(height: 6),
                  ...c.pending.map(
                    (b) => _PendingBookingCard(
                      booking: b,
                      routeDisplay: IntercityPlaces.tripRouteDisplay(
                        c.tripData,
                        locale: Localizations.localeOf(context),
                      ),
                      onOpen: () => _openBookingDialog(c, b),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(children: [
                  Text(context.tr('passenger_list_header'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  Text(context.tr('count_items')
                      .replaceAll('{count}', '${c.confirmedBookings.length}'),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ]),
                const SizedBox(height: 8),
                if (c.confirmedBookings.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      context.tr('bookings_waiting_empty'),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ...c.confirmedBookings.map((b) => _passengerCard(context, c, b)),
                if (c.allPassengersPickedUp)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.directions_car),
                        label: Text(
                          context.tr('start_trip'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _confirmStartTrip(context),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _tripCard(
    BuildContext context,
    IntercityDriverPanelController c,
    String route,
    int hour,
    int seats,
    int price,
  ) {
    final listed = c.isListed;
    final onPanel = c.isOnPanel;
    final scheduleDate = c.tripData?['scheduleDate'] as String? ?? '';
    final total = c.totalSeats;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: listed ? AppColors.primaryMid : Colors.grey.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            listed
                ? (onPanel
                    ? context.tr('trip_listed_active')
                    : context.tr('trip_listed_panel_closed'))
                : context.tr('trip_finished'),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: listed ? AppColors.primaryDark : Colors.grey)),
        if (scheduleDate.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
              context
                  .tr('schedule_date')
                  .replaceAll('{date}', scheduleDate),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
        const SizedBox(height: 6),
        Text(route,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('рџ•ђ ${context.tr('departure')}: ${hour.toString().padLeft(2, '0')}:00'),
        Text(
            total > 0
                ? context
                    .tr('seats_ratio')
                    .replaceAll('{left}', '$seats')
                    .replaceAll('{total}', '$total')
                : context
                    .tr('seats_count_only')
                    .replaceAll('{left}', '$seats')),
        Text(
            context
                .tr('price_per_passenger')
                .replaceAll('{price}', formatPrice(price))
                .replaceAll('{sum}', context.tr('sum'))),
        if (!onPanel && listed)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              context.tr('panel_closed_visible_hint').replaceAll(
                '{date}',
                scheduleDate.isNotEmpty
                    ? scheduleDate
                    : context.tr('tomorrow_short'),
              ),
              style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openReturnSchedule(context, c),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: Text(context.tr('return_route')),
            style: OutlinedButton.styleFrom(
              foregroundColor: IntercityDriverPanelScreen._primary,
              side: BorderSide(color: Colors.blue.shade200),
            ),
          ),
        ),
        if (listed) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(ctx.tr('end_trip_title')),
                    content: Text(ctx.tr('end_trip_body')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(ctx.tr('no'))),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(ctx.tr('yes_end_trip'),
                              style: const TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (ok == true) await c.endTripListing();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade200),
              ),
              child: Text(context.tr('end_trip_btn')),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _openReturnSchedule(
    BuildContext context,
    IntercityDriverPanelController c,
  ) async {
    final stops = intercityRouteStopsFromTrip(c.tripData);
    if (stops.length < 2) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('route_info_not_found'))),
      );
      return;
    }
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DriverScheduleScreen(
          taxiType: 'intercity',
          driverName: c.driverName,
          driverPhone: c.driverPhone,
          driverCar: c.driverCar,
          driverPlate: c.driverPlate,
          initialRouteStops: stops,
          initialRouteReversed: true,
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case IntercityBookingStatus.pending:
        return context.tr('status_pending_label');
      case IntercityBookingStatus.confirmed:
        return context.tr('booking_confirmed');
      case IntercityBookingStatus.cancelled:
        return context.tr('status_cancelled');
      case IntercityBookingStatus.completed:
        return context.tr('status_completed');
      default:
        return status;
    }
  }

  Widget _passengerCard(
    BuildContext context,
    IntercityDriverPanelController c,
    IntercityBooking b,
  ) {
    final pickup = b.hasPickupAddress
        ? b.pickupAddress
        : context.tr('passenger_no_pickup');
    final age = ageFromBirthDate(b.userBirthDate);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('рџ‘¤ ${context.trMsg(b.userName)} вЂў ${b.userPhone}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        if (b.userGender.isNotEmpty)
          _infoRow(
            b.userGender == 'female' ? 'рџ‘©' : 'рџ‘Ё',
            context.tr(b.userGender == 'female'
                ? 'gender_female' : 'gender_male'),
          ),
        if (age != null)
          _infoRow(
            'рџЋ‚',
            '$age ${context.tr('age_years')}',
          ),
        if (b.passengers > 1)
          _infoRow(
            'рџ’є',
            '${b.passengers} ${context.tr('passengers')}',
          ),
        Text('рџ“Ќ $pickup', style: const TextStyle(fontSize: 12)),
        if (b.hasPickupGps) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              border: Border.all(color: Colors.green.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on,
                    color: Colors.green.shade600, size: 14),
                const SizedBox(width: 4),
                Text(
                  context.tr('gps_received'),
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (b.dropoffNote.isNotEmpty)
          Text('рџЏЃ ${b.dropoffNote}', style: const TextStyle(fontSize: 12)),
        Text(
            'вњ… ${_statusLabel(b.status)} вЂў рџ’° ${formatPrice(b.totalAmount)} ${context.tr('sum')} вЂў #${b.shortRef}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        Row(children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => callPhone(b.userPhone),
            icon: const Icon(Icons.call, color: IntercityDriverPanelScreen._primary),
          ),
          if (b.hasPickupGps)
            TextButton.icon(
              onPressed: () => openMapsNavigation(
                lat: b.pickupLat!,
                lng: b.pickupLng!,
                label: b.pickupAddress,
              ),
              icon: const Icon(Icons.map, size: 16),
              label: const Text('рџ“Ќ GPS'),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => c.complete(b.id),
            child: Text(context.tr('complete_btn')),
          ),
        ]),
        const SizedBox(height: 8),
        if (!b.pickedUp)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                b.userGender == 'female'
                    ? context.tr('picked_up_female')
                    : context.tr('picked_up_male'),
              ),
              onPressed: () => c.pickUp(b.id),
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
              const SizedBox(width: 6),
              Text(
                b.userGender == 'female'
                    ? context.tr('picked_up_female')
                    : context.tr('picked_up_male'),
                style: const TextStyle(color: Colors.green),
              ),
            ],
          ),
      ]),
    );
  }

  Future<void> _confirmStartTrip(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('start_trip_confirm_title')),
        content: Text(context.tr('start_trip_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('confirm')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<IntercityDriverPanelController>().startTrip();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr('trip_started_success')),
      backgroundColor: Colors.green,
    ));
  }

  Widget _infoRow(String emoji, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('$emoji $text', style: const TextStyle(fontSize: 12)),
      );
}

/// РљСѓС‚РёР»РјРѕТ›РґР°РіРё Р±СЂРѕРЅ вЂ” РґРёР°Р»РѕРі Р№СћТ›РѕР»СЃР° ТіР°Рј В«ТљР°Р±СѓР»В» РѕС‡РёТ› Т›РѕР»Р°РґРё.
class _PendingBookingCard extends StatelessWidget {
  const _PendingBookingCard({
    required this.booking,
    required this.routeDisplay,
    required this.onOpen,
  });

  final IntercityBooking booking;
  final String routeDisplay;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context
                .tr('pending_seats_line')
                .replaceAll('{name}', context.trMsg(booking.userName))
                .replaceAll('{passengers}', '${booking.passengers}'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(routeDisplay, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.touch_app, size: 18),
              label: Text(context.tr('accept_reject_call')),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
